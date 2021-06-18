package Adup::Task::Zupprocess;
use Mojo::Base 'Mojolicious::Plugin';

use Carp;
use POSIX qw(ceil);
#use Data::Dumper;

use Adup::Ural::Dblog;
#use Adup::Ural::FlatGroupNamingAI qw(flatgroup_ai);
use Adup::Ural::ZupLoader;

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

  my $guard = $job->minion->guard('upload_job_guard', 3600);
  unless ($guard) {
    $app->log->error("Exited zupprocess $$: ".$job->id.'. Other concurrent job is active.');
    return $job->finish('Other concurrent job is active');
  }

  $app->log->info("Start zupprocess $$: ".$job->id);
  my $db_adup = $app->mysql_adup->db;

  my $dblog = Adup::Ural::Dblog->new($db_adup, login=>$remote_user, state=>0);

  my $loader = eval {
    Adup::Ural::ZupLoader->new($app, $db_adup,
      sub { $job->note(progress => shift, info => shift) }
    )
  };
  if ($@) {
    $dblog->l(info=>'Ошибка загрузки из 1С "ЗУП" - неверный адрес сервера', state=>1);
    return $job->finish('Failed: bad server url');
  }

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
    return $job->fail($@);
  }

  $loader = undef;
  $dblog->l(info => "Загружены данные 1С \"ЗУП\" по $load_results[0] сотрудникам и выполнен разбор оргструктуры по $load_results[1]/$load_results[2] подразделениям");

  $app->log->info("Finish $$: ".$job->id);
  $job->finish;
}


1;
__END__
