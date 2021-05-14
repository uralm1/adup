package Adup::Task::Sync;
use Mojo::Base 'Mojolicious::Plugin';

use Carp;
use Mojo::mysql;
use Net::LDAP qw(LDAP_SUCCESS LDAP_INSUFFICIENT_ACCESS);
use Net::LDAP::Util qw(canonical_dn escape_filter_value escape_dn_value);
use Encode qw(decode);
#use Data::Dumper;
use Adup::Ural::Dblog;

use Adup::Ural::SyncCreateOUs;
use Adup::Ural::SyncCreateFlatGroups;
use Adup::Ural::SyncAttributesCreateMoveUsers;
use Adup::Ural::SyncDeleteUsers;
use Adup::Ural::SyncDeleteFlatGroups;
use Adup::Ural::SyncDeleteOUs;
use Adup::Ural::SyncDisableDismissed;

my $TASK_ID = 'sync_id';
# $TASK_LOG_STATE_SUCCESS = 10;
# $TASK_LOG_STATE_ERROR = 11;


sub register {
  my ($self, $app) = @_;
  $app->minion->add_task(sync => \&_sync);
}


# internal
sub _sync {
  my ($job, $remote_user) = @_;

  $job->app->log->info("Start sync $$: ".$job->id);
  my $db_adup = $job->app->mysql_adup->db;

  my $log = Adup::Ural::Dblog->new($db_adup, login=>$remote_user, state=>10);

  my $ldap = Net::LDAP->new($job->app->config->{ldap_servers}, port => 389, timeout => 10, version => 3);
  unless ($ldap) {
    $log->l(state=>11, info=>"Произошла ошибка подключения к глобальному каталогу");
    return $job->fail("LDAP creation error $@");
  }

  my $mesg = $ldap->bind($job->app->config->{ldap_user}, password => $job->app->config->{ldap_pass});
  if ($mesg->code) {
    $log->l(state=>11, info=>"Произошла ошибка авторизации при подключении к глобальному каталогу");
    return $job->fail("LDAP bind error ".$mesg->error);
  }

  $job->app->set_task_state($db_adup, $TASK_ID, $job->id);

  my $e = eval {
    $db_adup->query("DELETE FROM changes");
  };
  unless (defined $e) {
    $job->app->reset_task_state($db_adup, $TASK_ID);
    return $job->fail('Changes table cleanup error');
  }

  #
  # SyncCreateOUs subtask
  #
  my $c1 = 0;
  my $c2 = 0;
  unless (defined ($c1 = Adup::Ural::SyncCreateOUs::do_sync(
    db => $db_adup,
    ldap => $ldap,
    log => $log,
    job => $job,
    user => $remote_user
  ))) {
    $job->app->reset_task_state($db_adup, $TASK_ID);
    return $job->fail('SyncCreateOUs fatal error');
  }

  #
  # SyncCreateFlatGroups subtask
  #
  unless (defined ($c2 = Adup::Ural::SyncCreateFlatGroups::do_sync(
    db => $db_adup,
    ldap => $ldap,
    log => $log,
    job => $job,
    user => $remote_user,
  ))) {
    $job->app->reset_task_state($db_adup, $TASK_ID);
    return $job->fail('SyncCreateFlatGroups fatal error');
  }

  if ($c1 > 0 || $c2 > 0) {
    $log->l(info=>"Проведена неполная предварительная синхронизация. Примените изменения создания подразделений и групп, затем перезапустите задание расчета изменений для полной синхронизации.");
    $job->app->reset_task_state($db_adup, $TASK_ID);
    $ldap->unbind;
    say "pre-finish $$: ".$job->id;
    return $job->finish;
  }

  #
  # SyncAttributesCreateMoveUsers subtask
  #
  unless (defined Adup::Ural::SyncAttributesCreateMoveUsers::do_sync(
    db => $db_adup,
    ldap => $ldap,
    log => $log,
    job => $job,
    user => $remote_user,
  )) {
    $job->app->reset_task_state($db_adup, $TASK_ID);
    return $job->fail('SyncAttributesCreateMoveUsers fatal error');
  }

  #
  # SyncDeleteFlatGroups subtask
  #
  unless (defined Adup::Ural::SyncDeleteFlatGroups::do_sync(
    db => $db_adup,
    ldap => $ldap,
    log => $log,
    job => $job,
    user => $remote_user,
  )) {
    $job->app->reset_task_state($db_adup, $TASK_ID);
    return $job->fail('SyncDeleteFlatGroups fatal error');
  }

  #
  # SyncDeleteUsers subtask
  #
  unless (defined Adup::Ural::SyncDeleteUsers::do_sync(
    db => $db_adup,
    ldap => $ldap,
    log => $log,
    job => $job,
    user => $remote_user,
  )) {
    $job->app->reset_task_state($db_adup, $TASK_ID);
    return $job->fail('SyncDeleteUsers fatal error');
  }

  #
  # SyncDeleteOUs subtask
  #
  unless (defined Adup::Ural::SyncDeleteOUs::do_sync(
    db => $db_adup,
    ldap => $ldap,
    log => $log,
    job => $job,
    user => $remote_user,
  )) {
    $job->app->reset_task_state($db_adup, $TASK_ID);
    return $job->fail('SyncDeleteOUs fatal error');
  }

  #
  # SyncDisableDismissed subtask
  #
  unless (defined Adup::Ural::SyncDisableDismissed::do_sync(
    db => $db_adup,
    ldap => $ldap,
    log => $log,
    job => $job,
    user => $remote_user,
  )) {
    $job->app->reset_task_state($db_adup, $TASK_ID);
    return $job->fail('SyncDisableDismissed fatal error');
  }

  $job->app->reset_task_state($db_adup, $TASK_ID);
  $ldap->unbind;

  $job->app->log->info("Finish $$: ".$job->id);
  $job->finish;
}


1;
__END__
