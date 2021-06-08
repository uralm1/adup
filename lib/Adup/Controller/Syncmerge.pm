package Adup::Controller::Syncmerge;
use Mojo::Base 'Mojolicious::Controller';

use Carp;
use POSIX qw(ceil);
use Mojo::mysql;


sub post {
  my $self = shift;
  return undef unless $self->authorize({admin=>1});

  if ($self->can_start_task(
    sub {
      if (/^.+/) {
        $self->flash(oper => 'В настоящий момент уже исполняется другая задача. Повторите попытку запуска позже.');
      } else {
        $self->flash(oper => 'Запуск невозможен. Обнаружена неисправность подсистемы исполнения.');
      }
    }
  )) {
    my $id = $self->minion->enqueue(merge => [$self->stash('remote_user')]);
    $self->session(mtid => $id);
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
