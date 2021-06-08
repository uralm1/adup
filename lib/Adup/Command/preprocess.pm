package Adup::Command::preprocess;
use Mojo::Base 'Mojolicious::Command';

#use Data::Dumper;
use Adup::Ural::Dblog;

has description => '* Start dbf preprocess job via commandline';
has usage => "Usage: APPLICATION preprocess\n";

sub run {
  my $self = shift;
  my $app = $self->app;

  my $log = Adup::Ural::Dblog->new($app->mysql_adup->db, login=>'automatic', state=>0);

  if ($app->can_start_task(
    sub {
      say "Command cancelled. Execution subsystem error or other task is running: $_.";
      $log->l(info=>'Произошла ошибка запуска задания постобработки файла ИС "Галактика". Недоступна подсистема исполнения или система занята исполнением другого задания.', state=>1);
    }
  )) {
    my $id = $app->minion->enqueue(preprocess => ['automatic']);
    # there is no session when started from command line
    return 0;
  }
  return 1;
}


1;
