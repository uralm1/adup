package Adup::Task::Zupprocess;
use Mojo::Base 'Mojolicious::Plugin';

use Carp;
use POSIX qw(ceil);
#use Data::Dumper;

use Adup::Ural::Dblog;
#use Adup::Ural::FlatGroupNamingAI qw(flatgroup_ai);
use Adup::Ural::ZupLoader;

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
  my $app = $job->app;

  $app->log->info("Start zupprocess $$: ".$job->id);
  my $db_adup = $app->mysql_adup->db;

  my $dblog = Adup::Ural::Dblog->new($db_adup, login=>$remote_user, state=>0);

  $app->set_task_state($db_adup, $TASK_ID, $job->id);

  my $loader = eval {
    Adup::Ural::ZupLoader->new($job->app, $db_adup,
      sub { $job->note(progress => shift, info => shift) }
    )
  };
  if ($@) {
    $dblog->l(info=>'Ошибка загрузки из 1С "ЗУП" - неверный адрес сервера', state=>1);
    $app->reset_task_state($db_adup, $TASK_ID);
    return $job->finish('Failed: bad server url');
  }

  #$job->note(
  #  progress => 0,
  #  info => "0% Соединение с сервером..."
  #);

  my @load_results;
  eval {
    $loader->upload_data;
    @load_results = $loader->process_data;
  };
  if ($@) {
    local $_ = $@;
    my $msg;
    if (/^org not found/i) { $msg = 'Ошибка: запрошенная организация отсутствует в 1С' }
    elsif (/^response/i) { $msg = 'Произошла ошибка веб-запроса к серверу 1С' }
    elsif (/^json response/i) { $msg = 'Произошла ошибка разбора формата данных, полученных с сервера 1C' }
    elsif (/^database tables cleanup/i) { $msg = 'Произошла ошибка очистки таблиц данных' }
    elsif (/^database insert to table persons/i) { $msg = 'Произошла ошибка записи таблицы persons, операция прервана' }
    elsif (/^database update/i) { $msg = 'Произошла ошибка обновления дубликатов в таблице persons, операция прервана' }
    elsif (/^database insert to table depts/i) { $msg = 'Произошла ошибка записи таблицы подразделений' }
    elsif (/^database insert to table flatdepts/i) { $msg = 'Произошла ошибка записи подразделений в плоском формате' }
    else { $msg = "Произошла ошибка: $@" }
    $dblog->l(state => 1, info => $msg);
    $app->reset_task_state($db_adup, $TASK_ID);
    return $job->fail($@);
  }

  $loader = undef;
  $dblog->l(info => "Загружены данные 1С \"ЗУП\" по $load_results[0] сотрудникам и выполнен разбор оргструктуры по $load_results[1]/$load_results[2] подразделениям");

  $app->reset_task_state($db_adup, $TASK_ID);

  $app->log->info("Finish $$: ".$job->id);
  $job->finish;
}


1;
__END__
