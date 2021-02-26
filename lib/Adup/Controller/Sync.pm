package Adup::Controller::Sync;
use Mojo::Base 'Mojolicious::Controller';

use Carp;
use POSIX qw(ceil);
use Mojo::mysql;

sub index {
  my $self = shift;
  return undef unless $self->authorize({admin=>1});

  my $log_active_page = $self->param('p') || 1;
  return unless $self->exists_and_number($log_active_page);

  # check sync task is running
  my $sync_task_id = $self->check_task_in_progress('sync_id', 'stid');
  # check merge task is running
  my $merge_task_id = $self->check_task_in_progress('merge_id', 'mtid');

  my $db = $self->mysql_adup->db;
  # get last upload
  my $last_upload;
  my $e = eval {
    my $log_rec = $db->query("SELECT DATE_FORMAT(date, '%H:%i %e.%m.%Y') AS fdate, \
      login \
      FROM op_log \
      WHERE state = 0 \
      ORDER BY date DESC LIMIT 1");
    if (my $lh = $log_rec->hash) {
      $last_upload = "$lh->{login} $lh->{fdate}";
    } else {
      $last_upload = 'нет данных';
    }
    $log_rec->finish;
  };
  $last_upload = 'Ошибка операции с БД' unless defined $e;

  # paginated log
  my $lines_on_page = $self->config('log_lines_on_page');
  my $lines_total;
  $e = eval {
    my $r = $db->query("SELECT COUNT(*) FROM op_log WHERE state IN (10, 11, 90, 91)");
    $lines_total = $r->array->[0];
    $r->finish;
  };
  return $self->render(text => 'Ошибка операции с БД') unless defined $e;

  my $num_pages = ceil($lines_total / $lines_on_page);
  return $self->render(text => 'Ошибка лога') if ($log_active_page < 1 || ($num_pages > 0 && $log_active_page > $num_pages));

  my $log_rec;
  $e = eval {
    $log_rec = $db->query("SELECT DATE_FORMAT(date, '%H:%i %e.%m.%Y') AS fdate, \
      login, state, info \
      FROM op_log \
      WHERE state IN (10, 11, 90, 91) \
      ORDER BY date DESC LIMIT ? OFFSET ?",
      $lines_on_page, ($log_active_page - 1)*$lines_on_page
    );
  };
  return $self->render(text => 'Ошибка операции с БД') unless defined $e;

  $self->render(
    sync_task_id => $sync_task_id, # undef, 0, >0
    merge_task_id => $merge_task_id, # undef, 0, >0
    last_upload => $last_upload,
    log_lines_total => $lines_total,
    log_num_pages => $num_pages,
    log_active_page => $log_active_page,
    log_rec => $log_rec,
  );
}


sub post {
  my $self = shift;
  return undef unless $self->authorize({admin=>1});

  if ($self->check_workers) {
    # concurrency checks
    my $upload_task_id = $self->db_task_id('preprocess_id');
    my $sync_task_id = $self->db_task_id('sync_id');
    my $merge_task_id = $self->db_task_id('merge_id');
    if ($upload_task_id == 0 && $merge_task_id == 0 && $sync_task_id == 0) {
      my $id = $self->minion->enqueue(sync => [$self->stash('remote_user')]);
      $self->session(stid => $id);
    } elsif ($sync_task_id > 0) {
      $self->flash(oper => 'Задача расчёта изменений уже работает. Запуск отменён');
    } elsif ($upload_task_id > 0) {
      $self->flash(oper => 'В настоящий момент исполняется задача загрузки шаблона. Повторите попытку запуска позже.');
    } elsif ($merge_task_id > 0) {
      $self->flash(oper => 'В настоящий момент исполняется задача применения изменений. Повторите попытку запуска позже.');
    }
  } else {
    $self->flash(oper => 'Запуск невозможен. Обнаружена неисправность подсистемы исполнения.');
  }
  $self->redirect_to('sync');
}


sub check {
  my $self = shift;
  return undef unless $self->authorize({admin=>1});

  # check sync task progress
  my $task_id = $self->db_task_id('sync_id');
  my $progress = 0;
  my $info = '';
  if ($task_id == 0) {
    $self->session(stid => 0) if defined $self->session('stid');
  } else {
    if (my $j = $self->minion->job($task_id)) {
      $progress = $j->info->{notes}{progress};
      $info = $j->info->{notes}{info};
    }
    $progress = 0 unless defined $progress;
    $info = '' unless defined $info;
  }
  $self->render(json => {stid => $task_id, progress => $progress, info => $info}, status => 200);
}

1;
