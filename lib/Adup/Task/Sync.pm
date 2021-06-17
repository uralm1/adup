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

my @SYNC_SEQUENCE = (
  { name => 'SyncCreateOUs', ref => \&Adup::Ural::SyncCreateOUs::do_sync },
  { name => 'SyncCreateFlatGroups', ref => \&Adup::Ural::SyncCreateFlatGroups::do_sync,
    pre_stop => [0, 1],
    pre_stop_msg => 'Проведена неполная предварительная синхронизация. Примените изменения создания подразделений и групп, затем перезапустите задание расчета изменений для полной синхронизации.',
  },
  { name => 'SyncAttributesCreateMoveUsers', ref => \&Adup::Ural::SyncAttributesCreateMoveUsers::do_sync },
  { name => 'SyncDeleteFlatGroups', ref => \&Adup::Ural::SyncDeleteFlatGroups::do_sync },
  { name => 'SyncDeleteUsers', ref => \&Adup::Ural::SyncDeleteUsers::do_sync },
  { name => 'SyncDeleteOUs', ref => \&Adup::Ural::SyncDeleteOUs::do_sync },
  { name => 'SyncDisableDismissed', ref => \&Adup::Ural::SyncDisableDismissed::do_sync },
);

sub register {
  my ($self, $app) = @_;

  $app->helper(percent_sync_task => sub { 100 / scalar @SYNC_SEQUENCE });

  $app->minion->add_task(sync => \&_sync);
}


# internal
sub _sync {
  my ($job, $remote_user) = @_;
  my $app = $job->app;

  my $guard = $job->minion->guard('upload_job_guard', 3600);
  my $guard1 = $job->minion->guard('sync_job_guard', 3600);
  unless ($guard && $guard1) {
    $app->log->error("Exited sync $$: ".$job->id.'. Other concurrent job is active.');
    return $job->finish('Other concurrent job is active');
  }

  $app->log->info("Start sync $$: ".$job->id);
  my $db_adup = $app->mysql_adup->db;

  my $log = Adup::Ural::Dblog->new($db_adup, login=>$remote_user, state=>10);

  my $ldap = Net::LDAP->new($app->config->{ldap_servers}, port => 389, timeout => 10, version => 3);
  unless ($ldap) {
    $log->l(state=>11, info=>"Произошла ошибка подключения к глобальному каталогу");
    return $job->fail("LDAP creation error $@");
  }

  my $mesg = $ldap->bind($app->config->{ldap_user}, password => $app->config->{ldap_pass});
  if ($mesg->code) {
    $log->l(state=>11, info=>"Произошла ошибка авторизации при подключении к глобальному каталогу");
    return $job->fail("LDAP bind error ".$mesg->error);
  }

  $app->set_task_state($db_adup, $TASK_ID, $job->id);

  my $e = eval {
    $db_adup->query("DELETE FROM changes");
  };
  unless (defined $e) {
    $app->reset_task_state($db_adup, $TASK_ID);
    $ldap->unbind;
    return $job->fail('Changes table cleanup error');
  }

  # Run subtasks
  my $idx = 0;
  for my $seq_el (@SYNC_SEQUENCE) {
    my $c = $seq_el->{ref}->(
      db => $db_adup,
      ldap => $ldap,
      log => $log,
      job => $job,
      user => $remote_user,
      pos => $idx
    );
    unless (defined $c) {
      $app->reset_task_state($db_adup, $TASK_ID);
      $ldap->unbind;
      return $job->fail("$seq_el->{name} fatal error");
    }
    $seq_el->{_result} = $c;

    if ($seq_el->{pre_stop}) {
      my $check = 0;
      $check ||= $SYNC_SEQUENCE[$_]->{_result} > 0 for @{$seq_el->{pre_stop}};
      if ($check) {
        $log->l(info => $seq_el->{pre_stop_msg});
        $app->reset_task_state($db_adup, $TASK_ID);
        $ldap->unbind;
        $app->log->info("Pre-finish $$: ".$job->id);
        return $job->finish;
      }
    }

    $idx++;
  }
  # done

  $app->reset_task_state($db_adup, $TASK_ID);
  $ldap->unbind;

  $app->log->info("Finish $$: ".$job->id);
  $job->finish;
}


1;
__END__
