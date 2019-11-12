package Adup::Controller::Index;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::mysql;
use Adup::Ural::Changelog;

sub index {
  my $self = shift;
  return undef unless $self->authorize($self->allow_all_roles);

  # get last upload
  my $last_upload;
  my $log_rec;
  my $e = eval {
    $log_rec = $self->mysql_adup->db->query("SELECT DATE_FORMAT(date, '%H:%i %e.%m.%Y') AS fdate, \
      login, info \
      FROM op_log WHERE state = 0 \
      ORDER BY date DESC LIMIT 1");
  };
  if (defined $e) {
    if (my $lh = $log_rec->hash) {
      my $u = $self->oprs($lh->{login});
      $last_upload = "$lh->{fdate},  выполнил: $u,  информация: \"$lh->{info}\""; 
    } else {
      $last_upload = 'Загрузка не производилась';
    }
    $log_rec->finish;
  } else {
    $last_upload = 'Ошибка операции с базой данных';
  }

  # get last merge
  my $last_merge;
  $e = eval {
    $log_rec = $self->mysql_adup->db->query("SELECT DATE_FORMAT(date, '%H:%i %e.%m.%Y') AS fdate, \
      login, info \
      FROM op_log WHERE state = 90 \
      ORDER BY date DESC LIMIT 1");
  };
  if (defined $e) {
    if (my $lh = $log_rec->hash) {
      my $u = $self->oprs($lh->{login});
      $last_merge = "$lh->{fdate},  выполнил: $u,  информация: \"$lh->{info}\""; 
    } else {
      $last_merge = 'Применение изменений не производилось';
    }
    $log_rec->finish;
  } else {
    $last_merge = 'Ошибка операции с базой данных';
  }

  $self->render(
    last_upload => $last_upload,
    last_merge => $last_merge,
  );
}


sub about {
  my $self = shift;
  return undef unless $self->authorize($self->allow_all_roles);

  my $hist;
  if (my $changelog = Adup::Ural::Changelog->new($self->mysql_adup->db, $self->stash('version'), 50)) {
    $hist = $changelog->get_changelog_html;
  } else {
    $hist = 'Информация отсутствует.';
  }
  $self->render(
    hist => $hist,
  );
}

1;
