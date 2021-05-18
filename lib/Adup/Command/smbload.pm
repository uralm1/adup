package Adup::Command::smbload;
use Mojo::Base 'Mojolicious::Command';

#use Data::Dumper;
use Adup::Ural::Dblog;

has description => '* Load dbf from smb server and start preprocess job';
has usage => "Usage: APPLICATION smbload\n";

sub run {
  my $self = shift;
  my $app = $self->app;

  my $log = Adup::Ural::Dblog->new($app->mysql_adup->db, login=>'automatic', state=>0);

  if ($app->check_workers) {
    # concurrency checks
    my $upload_task_id = $app->db_task_id('preprocess_id');
    my $sync_task_id = $app->db_task_id('sync_id');
    my $merge_task_id = $app->db_task_id('merge_id');
    if ($sync_task_id == 0 && $merge_task_id == 0 && $upload_task_id == 0) {
      my $id = $app->minion->enqueue('smbload');
      # there is no session when started from command line
      return 0;
    } elsif ($upload_task_id > 0) {
      say 'Preprocess task is already running. Command cancelled.';
      $log->l(info=>'Произошла ошибка запуска задания загрузки. Работает задание постобработки.', state=>1);
    } elsif ($sync_task_id > 0) {
      say 'Sync task is running. Command cancelled. You can repeat your request later.';
      $log->l(info=>'Произошла ошибка запуска задания загрузки. Работает задание расчёта изменений.', state=>1);
    } elsif ($merge_task_id > 0) {
      say 'Merge task is running. Command cancelled. You can repeat your request later.';
      $log->l(info=>'Произошла ошибка запуска задания загрузки. Работает задание применения изменений.', state=>1);
    }
  } else {
    say 'Command cancelled. Execution subsystem error.';
    $log->l(info=>'Произошла ошибка запуска задания загрузки. Недоступна подсистема исполнения.', state=>1);
  }
  return 1;
}


1;
