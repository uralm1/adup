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

    if ($app->check_workers) {
      # concurrency checks
      my $upload_task_id = $app->db_task_id('preprocess_id');
      my $sync_task_id = $app->db_task_id('sync_id');
      my $merge_task_id = $app->db_task_id('merge_id');
      if ($sync_task_id == 0 && $merge_task_id == 0 && $upload_task_id == 0) {
        my $id = $app->minion->enqueue(preprocess => ['automatic']);
        # there is no session
        $app->log->info("Finish $$: ".$job->id);
        $job->finish;
        return 0;

      } elsif ($upload_task_id > 0) {
        $app->log->error('Preprocess task is already running. Command cancelled.');
        $log->l(info=>'Произошла ошибка запуска задания постобработки. Задание постобработки уже запущено, повторный запуск недопустим.', state=>1);

      } elsif ($sync_task_id > 0) {
        $app->log->error('Sync task is running. Command cancelled. You can repeat your request later.');
        $log->l(info=>'Произошла ошибка запуска задания постобработки. Работает задание расчёта изменений.', state=>1);

      } elsif ($merge_task_id > 0) {
        $app->log->error('Merge task is running. Command cancelled. You can repeat your request later.');
        $log->l(info=>'Произошла ошибка запуска задания постобработки. Работает задание применения изменений.', state=>1);
      }

    } else {
      $app->log->error('Command cancelled. Execution subsystem error.');
      $log->l(info=>'Произошла ошибка запуска задания постобработки. Недоступна подсистема исполнения.', state=>1);
    }
    #error exit
  }

  $app->log->error('Error loading Persons.dbf from SMB server, code: '.($? >> 8));
  $log->l(info=>'Произошла ошибка загрузки шаблона Persons с удаленного сервера, код: '.($? >> 8), state=>1);
  $job->finish;
  return 1;
}


1;
