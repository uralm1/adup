package Adup::Controller::Syncmerge;
use Mojo::Base 'Mojolicious::Controller';

use Carp;
use POSIX qw(ceil);
use Mojo::mysql;


sub post {
  my $self = shift;
  return undef unless $self->authorize({admin=>1});

  if ($self->check_workers) {
    # concurrency checks
    my $upload_task_id = $self->db_task_id('preprocess_id');
    my $sync_task_id = $self->db_task_id('sync_id');
    my $merge_task_id = $self->db_task_id('merge_id');
    if ($upload_task_id == 0 && $sync_task_id == 0 && $merge_task_id == 0) {
      my $id = $self->minion->enqueue(merge => [$self->stash('remote_user')]);
      $self->session(mtid => $id);
    } elsif ($merge_task_id > 0) {
      $self->flash(oper => 'Задача применения изменений уже работает. Запуск отменен');
    } elsif ($upload_task_id > 0) {
      $self->flash(oper => 'В настоящий момент исполняется задача загрузки шаблона. Повторите попытку запуска позже');
    } elsif ($sync_task_id > 0) {
      $self->flash(oper => 'В настоящий момент исполняется задача расчёта изменений. Повторите попытку запуска позже');
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
  my $task_id = $self->db_task_id('merge_id');
  my $progress = 0;
  my $info = '';
  if ($task_id == 0) {
    $self->session(mtid => 0) if defined $self->session('mtid');
  } else {
    if (my $j = $self->minion->job($task_id)) {
      $progress = $j->info->{notes}{progress};
      $info = $j->info->{notes}{info};
    }
    $progress = 0 unless defined $progress;
    $info = '' unless defined $info;
  }
  $self->render(json => {mtid => $task_id, progress => $progress, info => $info}, status => 200);
}

1;
