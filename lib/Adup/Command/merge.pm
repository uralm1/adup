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

  if ($app->can_start_task(
    sub {
      say "Command cancelled. Execution subsystem error or other task is running: $_.";
      $log->l(info=>'Произошла ошибка запуска применения изменений. Недоступна подсистема исполнения или система занята исполнением другого задания.', state=>1);
    }
  )) {
    my $id = $app->minion->enqueue(merge => ['automatic']);
    # there is no session when started from command line
    return 0;
  }
  return 1;
}


1;
