package Adup::Task::Merge;
use Mojo::Base 'Mojolicious::Plugin';

use Carp;
use POSIX qw(ceil);
use Mojo::mysql;
use Net::LDAP qw(LDAP_SUCCESS LDAP_INSUFFICIENT_ACCESS);
use Net::LDAP::Util qw(canonical_dn);
use Encode qw(encode_utf8 decode);
#use Data::Dumper;
use Adup::Ural::ChangeFactory;
use Adup::Ural::Change;
use Adup::Ural::ChangeUserCreate;
use Adup::Ural::ChangeUserDelete;
use Adup::Ural::ChangeUserFlatGroup;
use Adup::Ural::ChangeUserDisableDismissed;
use Adup::Ural::ChangeAttr;
use Adup::Ural::ChangeOUCreate;
use Adup::Ural::ChangeOUDelete;
use Adup::Ural::ChangeOUModify;
use Adup::Ural::ChangeFlatGroupCreate;
use Adup::Ural::ChangeFlatGroupDelete;
use Adup::Ural::ChangeFlatGroupModify;
use Adup::Ural::ChangeError;
use Adup::Ural::Dblog;

my $TASK_ID = 'merge_id';
# $TASK_LOG_STATE_SUCCESS = 90;
# $TASK_LOG_STATE_ERROR = 91;


sub register {
  my ($self, $app) = @_;
  $app->minion->add_task(merge => \&_merge);
}


# internal
sub _merge {
  my ($job, $remote_user) = @_;

  $job->app->log->info("Start merge $$: ".$job->id);
  my $db_adup = $job->app->mysql_adup->db;

  my $log = Adup::Ural::Dblog->new($db_adup, login=>$remote_user, state=>90);

  my $ldap = Net::LDAP->new($job->app->config->{ldap_servers}, port => 389, timeout => 10, version => 3);
  unless ($ldap) {
    $log->l(state=>91, info=>"Произошла ошибка подключения к глобальному каталогу");
    return $job->fail("LDAP creation error $@");
  }

  my $mesg = $ldap->bind($job->app->config->{ldap_user}, password => $job->app->config->{ldap_pass});
  if ($mesg->code) {
    $log->l(state=>91, info=>"Произошла ошибка авторизации при подключении к глобальному каталогу");
    return $job->fail("LDAP bind error ".$mesg->error);
  }

  $job->app->set_task_state($db_adup, $TASK_ID, $job->id);

  # merging changes for types ... in sequence
  # see type_robotic field in change objects
  my @merge_sequence = (
    { type => 0, desc => 'абстракт', rep_no => 0},
    { type => 99, desc => 'ошибки', rep_no => 0},
    { type => 20, desc => 'создание подразделений', rep_no => 1},
    { type => 22, desc => 'изменение подразделений', rep_no => 1},
    { type => 10, desc => 'создание групп почтового справочника', rep_no => 1},
    { type => 12, desc => 'изменение групп почтового справочника', rep_no => 1},
    { type => 2, desc => 'создание пользователей', rep_no => 1},
    { type => 1, desc => 'аттрибутов', rep_no => 1},
    { type => 13, desc => 'удаление пользователей из групп почтового справочника', rep_no => 1},
    { type => 5, desc => 'перемещение пользователей', rep_no => 1},
    { type => 8, desc => 'блокирование пользователей', rep_no => 1},
    { type => 11, desc => 'удаление групп почтового справочника', rep_no => 1},
    { type => 21, desc => 'удаление подразделений', rep_no => 1},
    { type => 14, desc => 'отключение архивных пользователей', rep_no => 1},
  );

  my $log_buf;

  #
  # begin of merge sequence main loop
  #
  for my $seq_el (@merge_sequence) {
    my $mt = $seq_el->{type};
    say "Merging changes type $mt";
    my $res;
    my $m_order_tmpl = '';
    # use metadata ordering when changing departments
    if ($mt == 20 || $mt == 22) {
      $m_order_tmpl = 'metadata ASC,'; #create/modify depts
    } elsif ($mt == 21) {
      $m_order_tmpl = 'metadata DESC,'; #delete depts
    }

    my $e = eval {
      $res = $db_adup->query("SELECT id, name, c \
        FROM changes WHERE type = ? \
        ORDER BY $m_order_tmpl id ASC", $mt);
    };
    unless (defined $e) {
      $job->app->reset_task_state($db_adup, $TASK_ID);
      return $job->fail('Merge - database fatal error');
    }
    my $changes_count = 0;
    my $changes_approved_count = 0;
    my $changes_processed_count = 0;
    my $changes_total = $res->rows;
    my $mod = int($changes_total / 20) || 1;
    while (my $next = $res->hash) {
      my $c = Adup::Ural::ChangeFactory->fromdb(id=>$next->{id}, json=>$next->{c});
      if ($c->approved) {
	if ($c->merge(author=>$remote_user, db=>$db_adup, ldap=>$ldap, config=>$job->app->config, log=>$log)) {
	  $changes_processed_count++;
	} else {
	  $log->l(state=>91, info=>"Изменение-$seq_el->{desc} не применено. Возникла ошибка при применении изменения-$seq_el->{desc}: $next->{name}.");
	}
        $changes_approved_count++;
      }

      # update progress
      $changes_count++;
      if ($changes_count % $mod == 0) {
	my $percent = ceil($changes_count / $changes_total * 100);
        $job->note(
	  progress => $percent,
          # mysql minion backend bug workaround
	  info => encode_utf8("$percent% Выполняется изменение-$seq_el->{desc}"),
	);
      }
    }
    $res->finish;

    #say "Approved: $changes_approved_count, Processed: $changes_processed_count, Total: $changes_total";
    if ($changes_approved_count > 0) {
      $log_buf .= ' ' if $log_buf;
      $log_buf .= "Изменение-$seq_el->{desc}, утверждено: $changes_approved_count, применено: $changes_processed_count, всего: $changes_total.";
    } elsif ($seq_el->{rep_no}) {
      $log_buf .= ' ' if $log_buf;
      $log_buf .= "Изменение-$seq_el->{desc}, отсутствуют утверждённые.";
    }
  }
  #
  # end of merge sequence main loop
  #

  $log->l(info => 'Отчёт о применении изменений. '.$log_buf) if $log_buf;

  $job->app->reset_task_state($db_adup, $TASK_ID);
  $ldap->unbind;

  $job->app->log->info("Finish $$: ".$job->id);
  $job->finish;
}


1;
__END__
