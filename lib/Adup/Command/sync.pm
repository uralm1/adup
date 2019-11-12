package Adup::Command::sync;
use Mojo::Base 'Mojolicious::Command';

#use Data::Dumper;
use Adup::Ural::Dblog;

has description => '* Start syncronization job via commandline';
has usage => "Usage: APPLICATION sync\n";

sub run {
  my $self = shift;
  my $app = $self->app;

  my $log = Adup::Ural::Dblog->new($app->mysql_adup->db, login=>'automatic', state=>10);

  if ($app->check_workers) {
    # concurrency checks
    my $upload_task_id = $app->db_task_id('preprocess_id');
    my $sync_task_id = $app->db_task_id('sync_id');
    my $merge_task_id = $app->db_task_id('merge_id');
    if ($upload_task_id == 0 && $merge_task_id == 0 && $sync_task_id == 0) {
      my $id = $app->minion->enqueue(sync => ['automatic']);
      # there is no session when started from command line
      return 0;
    } elsif ($sync_task_id > 0) {
      say 'Syncronization task is already running. Command cancelled.';
      $log->l(info=>'Произошла ошибка запуска расчёта изменений. Задание расчёта измений уже работает.', state=>11);
    } elsif ($upload_task_id > 0) {
      say 'Preprocess task is running. Command cancelled. You can repeat your request later.';
      $log->l(info=>'Произошла ошибка запуска расчёта изменений. Работает задание постобработки.', state=>11);
    } elsif ($merge_task_id > 0) {
      say 'Merge task is running. Command cancelled. You can repeat your request later.';
      $log->l(info=>'Произошла ошибка запуска расчёта изменений. Работает задание применения изменений.', state=>11);
    }
  } else {
    say 'Command cancelled. Execution subsystem error.';
    $log->l(info=>'Произошла ошибка запуска расчёта изменений. Недоступна подсистема исполнения.', state=>11);
  }
  return 1;
}


1;
