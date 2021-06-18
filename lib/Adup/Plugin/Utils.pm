package Adup::Plugin::Utils;
use Mojo::Base 'Mojolicious::Plugin';

use Carp;
use Mojo::mysql;
use Mojo::Util qw(xml_escape);

use Adup::Ural::Changelog;
use Adup::Ural::UsersCatalog;
use Adup::Ural::OperatorResolver;


sub register {
  my ( $self, $app, $args ) = @_;
  $args ||= {};

  # database singleton object
  $app->helper(mysql_adup => sub {
    state $mysql_adup = Mojo::mysql->new(shift->config('adup_db_conn'));
  });

  # users catalog singleton object
  $app->helper(users_catalog => sub {
    state $uc = Adup::Ural::UsersCatalog->new(shift->mysql_adup) or
      die "Fatal error: Users catalog creation error!";
  });

  # return undef unless $self->authorize({ admin=>1, gala=>1 });
  $app->helper(authorize => sub {
    my ($c, $roles_href) = @_;

    my $role = $c->stash('remote_user_role');
    return 1 if ($role && $roles_href->{$role});
    $c->app->log->warn("Access is forbidden for role: $role, user: ".$c->stash('remote_user'));
    $c->render(text => 'Доступ запрещён. Обратитесь в группу сетевого администрирования.', status => 401);
    return undef;
  });

  # $self->authorize($self->allow_all_roles);
  $app->helper(allow_all_roles => sub {
    { admin=>1, gala=>1, zup1c=>1, room=>1, phone=>1, sot=>1, photo=>1 };
  });


  # $self->exists_and_number($value)
  # renders error if not number
  $app->helper(exists_and_number => sub {
    my ($self, $v) = @_;
    unless (defined $v && $v =~ /^\d+$/) {
      $self->render(text => 'Ошибка данных');
      return undef;
    }
    return 1;
  });

  # my $bool = $self->check_workers
  $app->helper(check_workers => sub {
    my $self = shift;
    my $stats = $self->minion->stats;
    return ($stats->{active_workers} != 0 || $stats->{inactive_workers} != 0);
  });


  # my $task_id = $self->db_task_id('preprocess_id')
  $app->helper(db_task_id => sub {
    my ($self, $k) = @_;
    my $task_id = 0;
    eval {
      my $r = $self->mysql_adup->db->query("SELECT value FROM state WHERE `key` = ?", $k);
      $task_id = $r->array->[0];
      $r->finish;
    };
    return $task_id;
  });

  # 1/undef = $self->can_start_task()
  # 1/undef = $self->can_start_task(sub { say $_ })
  $app->helper(can_start_task => sub {
    my ($self, $reporting_cb) = @_;
    croak 'Bad reporting callback' if $reporting_cb and ref $reporting_cb ne 'CODE';

    unless ($self->app->check_workers) {
      $_ = '';
      $reporting_cb->($_) if $reporting_cb;
      return undef;
    }

    # concurrency checks
    my $j = $self->minion->jobs(
      { tasks => ['preprocess', 'zupprocess', 'sync', 'merge'],
        states => ['inactive', 'active']
      });
    if ($j->total > 0) {
      $_ = $j->next->{task};
      $reporting_cb->($_) if $reporting_cb;
      return undef;
    }

    return 1;
  });


  # my $task_id = $self->check_task_in_progress('preprocess_id', 'utid')
  $app->helper(check_task_in_progress => sub {
    my ($self, $k, $sesk) = @_;
    my $task_id = $self->db_task_id($k);
    my $s_id = $self->session($sesk);
    if ($task_id == 0) {
      unless (defined $s_id) {
        $task_id = undef; # start
      } else {
        $task_id = $s_id if $s_id > 0; # wait after task start
        # finished
      }
    } else {
      # task_id > 0, we should always wait
      if (defined $s_id and $s_id == 0) {
        $self->session($sesk => $task_id); #some erratic behavior
      }
    }
    return $task_id;
  });


  # $job->app->set_task_state($db, 'preprocess_id', 0)
  $app->helper(set_task_state => sub {
    my ($self, $db, $key, $s) = @_;

    my $e = eval {
      $db->query("UPDATE state SET value = ? WHERE `key` = ?", $s, $key);
    };
    unless (defined $e) {
      # we have to fix croak here
      carp "Set task state failed";
      return undef;
    }
    1;
  });

  # $job->app->reset_task_state($db, 'preprocess_id')
  $app->helper(reset_task_state => sub {
    my ($self, $db, $key) = @_;
    $self->set_task_state($db, $key, 0);
  });


  # html_or_undef = check_newversion
  $app->helper(check_newversion => sub {
    my $c = shift;
    my $coo = $c->cookie('versionA');
    my $cur_version = $c->stash('version');
    if (defined $coo) {
      if ($coo ne $cur_version) {
        $c->cookie(versionA => $cur_version, {path => '/', expires=>time+360000000});
        if (my $changelog = Adup::Ural::Changelog->new($cur_version)) {
	  return '<div id="newversion-modal" class="modal modal-fixed-footer">
<div class="modal-content"><h4>Новая версия '.$changelog->get_version.
'</h4><p><b>Последние улучшения и новинки:</b></p><pre class="newversion-hist">'.$changelog->get_changelog.
'</pre></div><div class="modal-footer"><a href="#!" class="modal-close waves-effect waves-green btn-flat">Отлично</a></div></div>';
	}
      }
    } else {
      $c->cookie(versionA => $cur_version, {path => '/', expires=>time+360000000});
    }
    return undef;
  });

  # my $full_operator_name = oprs($login)
  $app->helper(oprs => sub {
    my ($self, $login) = @_;
    # oprs object singleton
    state $oprs = Adup::Ural::OperatorResolver->new($self->config);
    return $oprs->resolve($login);
  });

  # <%== display_log_hack($info) %>
  $app->helper(display_log_hack => sub {
    my ($self, $line) = @_;
    return join('.<br>Изменение', split(/\.\s+Изменение/, xml_escape($line)));
  });

}

1;
__END__
