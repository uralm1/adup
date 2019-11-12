package Adup::Command::merge;
use Mojo::Base 'Mojolicious::Command';

#use Data::Dumper;
use Adup::Ural::Dblog;

has description => '* Start merge job via commandline';
has usage => "Usage: APPLICATION merge\n";

sub run {
  my $self = shift;
  my $app = $self->app;

  my $log = Adup::Ural::Dblog->new($app->mysql_adup->db, login=>'automatic', state=>90);

  if ($app->check_workers) {
    # concurrency checks
    my $upload_task_id = $app->db_task_id('preprocess_id');
    my $sync_task_id = $app->db_task_id('sync_id');
    my $merge_task_id = $app->db_task_id('merge_id');
    if ($upload_task_id == 0 && $sync_task_id == 0 && $merge_task_id == 0) {
      my $id = $app->minion->enqueue(merge => ['automatic']);
      # there is no session when started from command line
      return 0;
    } elsif ($merge_task_id > 0) {
      say 'Merge task is already running. Command cancelled.';
      $log->l(info=>'Произошла ошибка запуска применения изменений. Задание применения изменений уже запущено.', state=>91);
    } elsif ($upload_task_id > 0) {
      say 'Preprocess task is running. Command cancelled. You can repeat your request later.';
      $log->l(info=>'Произошла ошибка запуска применения изменений. Работает задание постобработки.', state=>91);
    } elsif ($sync_task_id > 0) {
      say 'Sync task is running. Command cancelled. You can repeat your request later.';
      $log->l(info=>'Произошла ошибка запуска применения изменений. Работает задание расчёта изменений.', state=>91);
    }
  } else {
    say 'Command cancelled. Execution subsystem error.';
    $log->l(info=>'Произошла ошибка запуска применения изменений. Недоступна подсистема исполнения.', state=>91);
  }
  return 1;
}


1;
