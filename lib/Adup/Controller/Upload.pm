package Adup::Controller::Upload;
use Mojo::Base 'Mojolicious::Controller';

use Carp;
use POSIX qw(ceil);
use XBase;
use Mojo::mysql;

sub index {
  my $self = shift;
  return undef unless $self->authorize({admin=>1, gala=>1});

  my $log_active_page = $self->param('p') || 1;
  return unless $self->exists_and_number($log_active_page);

  # check dbf processing in progress
  my $upload_task_id = $self->check_task_in_progress('preprocess_id', 'utid');

  # paginated log
  my $lines_on_page = $self->config('log_lines_on_page');
  my $lines_total;
  my $e = eval {
    my $r = $self->mysql_adup->db->query("SELECT COUNT(*) FROM op_log WHERE state = 0 OR state = 1");
    $lines_total = $r->array->[0];
    $r->finish;
  };
  return $self->render(text => 'Ошибка операции с БД') unless defined $e;

  my $num_pages = ceil($lines_total / $lines_on_page);
  return $self->render(text => 'Ошибка лога') if ($log_active_page < 1 || ($num_pages > 0 && $log_active_page > $num_pages));

  my $log_rec;
  $e = eval {
    $log_rec = $self->mysql_adup->db->query("SELECT DATE_FORMAT(date, '%H:%i %e.%m.%Y') AS fdate, \
      login, state, info \
      FROM op_log \
      WHERE state = 0 OR state = 1 \
      ORDER BY date DESC LIMIT ? OFFSET ?",
      $lines_on_page, ($log_active_page - 1)*$lines_on_page
    );
  };
  return $self->render(text => 'Ошибка операции с БД') unless defined $e;

  $self->render(
    upload_task_id => $upload_task_id, # undef, 0, >0
    log_lines_total => $lines_total,
    log_num_pages => $num_pages,
    log_active_page => $log_active_page,
    log_rec => $log_rec,
  );
}


sub post {
  my $self = shift;
  return undef unless $self->authorize({admin=>1, gala=>1});

  # this seems does not work
  if ($self->req->is_limit_exceeded) {
    $self->flash(oper => 'Ошибка! Слишком большой файл.');
    $self->redirect_to('upload');
    return undef;
  }
  my $upl = $self->param('personsdb');
  unless ($upl) {
    $self->flash(oper => 'Ошибка! Неверный параметр.');
    $self->redirect_to('upload');
    return undef;
  }
  unless ($upl->size) {
    $self->flash(oper => 'Ошибка! Файл не загружен.');
    $self->redirect_to('upload');
    return undef;
  }
  
  $upl->move_to($self->config('galdb_temporary_file'));

  my $dbf = eval { new XBase($self->config('galdb_temporary_file')); };
  if (defined $dbf) {
    if (join('|', $dbf->field_names, $dbf->field_types, $dbf->field_lengths) ne
                  $self->config('galdb_fields')) {
      $self->flash(oper => 'База данных не принята! Неверные типы полей.');
      $self->redirect_to('upload');
      return undef;
    }
  } else {
    $self->flash(oper => 'Ошибка! Неверный формат БД.');
    $self->redirect_to('upload');
    return undef;
  }

  $dbf = undef;

  if ($self->check_workers) {
    # concurrency checks
    my $upload_task_id = $self->db_task_id('preprocess_id');
    my $sync_task_id = $self->db_task_id('sync_id');
    my $merge_task_id = $self->db_task_id('merge_id');
    if ($sync_task_id == 0 && $merge_task_id == 0 && $upload_task_id == 0) {
      my $id = $self->minion->enqueue(preprocess => [$self->stash('remote_user')]);
      $self->session(utid => $id);
    } elsif ($upload_task_id > 0) {
      $self->flash(oper => 'Задача загрузки шаблона уже работает. Запуск отменен');
    } elsif ($sync_task_id > 0) {
      $self->flash(oper => 'В настоящий момент исполняется задача расчёта изменений. Повторите попытку запуска позже');
    } elsif ($merge_task_id > 0) {
      $self->flash(oper => 'В настоящий момент исполняется задача применения изменений. Повторите попытку запуска позже');
    }
  } else {
    $self->flash(oper => 'Запуск невозможен. Обнаружена неисправность подсистемы исполнения.');
  }
  #$self->render(text => 'Upload was successful '.$upl->size.' '.$upl->filename);
  $self->redirect_to('upload');
}


sub check {
  my $self = shift;
  return undef unless $self->authorize({admin=>1, gala=>1});

  # check dbf processing in progress
  my $task_id = $self->db_task_id('preprocess_id');
  my $progress = 0;
  my $info = '';
  if ($task_id == 0) {
    $self->session(utid => 0) if defined $self->session('utid');
  } else {
    if (my $j = $self->minion->job($task_id)) {
      $progress = $j->info->{notes}{progress};
      $info = $j->info->{notes}{info};
    }
    $progress = 0 unless defined $progress;
    $info = '' unless defined $info;
  }
  return $self->render(json => {utid => $task_id, progress => $progress, info => $info}, status => 200);
}

1;
