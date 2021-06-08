package Adup::Task::SmbLoad;
use Mojo::Base 'Mojolicious::Plugin';

#use Data::Dumper;
use Adup::Ural::Dblog;


sub register {
  my ($self, $app) = @_;
  $app->minion->add_task(smbload => \&_smbload);
}


sub _smbload {
  my $job = shift;
  my $app = $job->app;

  $app->log->info("Start smbload $$: ".$job->id);

  # download file via smbclient
  my $smb_share = $app->config('smb_share');
  my $smb_dom = $app->config('smb_dom');
  my $smb_file = $app->config('smb_file');
  my $upw = $app->config('smb_user').'%'.$app->config('smb_pass');
  my $loc_file = $app->config('galdb_temporary_file');

  my $log = Adup::Ural::Dblog->new($app->mysql_adup->db, login=>'automatic', state=>0);

  #say "starting smbclient";
  my $r = system("smbclient $smb_share -U $upw -W $smb_dom -c 'get $smb_file $loc_file'");
  #say "result is: $r";
  #say "smbclient finished, resultcode is: $?";

  if ($r == 0) {
    $log->l(info=>'Шаблон Persons автоматически скачан с удаленного SMB сервера. Запуск задания постобработки');

    if ($app->can_start_task(
      sub {
        $app->log->error("Command cancelled. Execution subsystem error or other task is running: $_.");
        $log->l(info=>'Произошла ошибка запуска задания постобработки. Недоступна подсистема исполнения или система занята исполнением другого задания.', state=>1);
      }
    )) {
      my $id = $app->minion->enqueue(preprocess => ['automatic']);
      # there is no session
      $app->log->info("Finish $$: ".$job->id);
      $job->finish;
      return 0;
    }
    #error exit
  }

  $app->log->error('Error loading Persons.dbf from SMB server, code: '.($? >> 8));
  $log->l(info=>'Произошла ошибка загрузки шаблона Persons с удаленного сервера, код: '.($? >> 8), state=>1);
  $job->finish;
  return 1;
}


1;
