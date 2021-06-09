package Adup::Task::Zupprocess;
use Mojo::Base 'Mojolicious::Plugin';

use Carp;
use POSIX qw(ceil);
use Mojo::mysql;
#use Encode qw(decode encode_utf8);
#use Digest::SHA qw(sha1_hex);
#use Data::Dumper;

use Adup::Ural::Dblog;
#use Adup::Ural::FlatGroupNamingAI qw(flatgroup_ai);

my $TASK_ID = 'zupprocess_id';
# $TASK_LOG_STATE_SUCCESS = 0;
# $TASK_LOG_STATE_ERROR = 1;


sub register {
  my ($self, $app) = @_;
  $app->minion->add_task(zupprocess => \&_load_zup);
}


# internal
sub _load_zup {
  my ($job, $remote_user) = @_;

  $job->app->log->info("Start zupprocess $$: ".$job->id);
  my $db_adup = $job->app->mysql_adup->db;

  my $log = Adup::Ural::Dblog->new($db_adup, login=>$remote_user, state=>0);

  $job->app->set_task_state($db_adup, $TASK_ID, $job->id);

  ##
  for (my $i = 0; $i <= 100; $i+=10) {
    $job->note(
      progress => $i,
      info => "$i% Имитация загрузки из 1с"
    );
    sleep(1);
  }
  ##

  $job->app->reset_task_state($db_adup, $TASK_ID);

  $job->app->log->info("Finish $$: ".$job->id);
  $job->finish;
}


1;
__END__
