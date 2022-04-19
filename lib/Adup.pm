package Adup;
use Mojo::Base 'Mojolicious';

use Adup::Command::preprocess;
use Adup::Command::sync;
use Adup::Command::merge;
use Adup::Command::smbload;
use Adup::Command::zupload;
use Adup::Command::cron;

our $VERSION = '1.23';

# This method will run once at server start
sub startup {
  my $self = shift;

  # Load configuration from hash returned by config file
  my $config = $self->plugin('Config', { default => {
    secrets => ['643059683fgbcv098098hfg98098'],
  }});
  delete $self->defaults->{config}; # safety - not to pass passwords to stashes

  # Configure the application
  #$self->mode('production');
  #$self->log->level('info');
  $self->secrets($config->{secrets});
  $self->sessions->cookie_name('adup');
  $self->sessions->default_expiration(0);

  exit 1 unless $self->validate_config;

  # upload file limit 16mb
  $self->max_request_size(16777216);

  $self->plugin(Minion => {mysql => $config->{minion_db_conn}});
  # FIXME DEBUG FIXME: open access to minion UI
  $self->plugin('Minion::Admin');

  $self->plugin('Adup::Plugin::MPagenav');
  $self->plugin('Adup::Plugin::Utils');
  $self->plugin('Adup::Plugin::Migrations');

  $self->plugin('Adup::Task::Preprocess');
  $self->plugin('Adup::Task::Zupprocess');
  $self->plugin('Adup::Task::Sync');
  $self->plugin('Adup::Task::Merge');
  $self->plugin('Adup::Task::SmbLoad');
  $self->commands->namespaces(['Mojolicious::Command', 'Minion::Command', 'Adup::Command']);

  $self->defaults(version => $VERSION);

  # update database
  $self->migrate_database;

  # Reset locks
  $self->minion->on(worker => sub { shift->reset({locks=>1}) });

  # Router authentication routine
  $self->hook(before_dispatch => sub {
    my $c = shift;

    my $remote_user;
    my $ah = $c->config('auth_user_header');
    if ($ah) {
      $remote_user = lc($c->req->headers->header($ah));
    } else {
      $remote_user = lc($c->req->env('REMOTE_USER'));
    }
    #FIXME DEBUG FIXME
    $remote_user = 'ural';

    unless ($remote_user) {
      $c->render(text => 'Необходима аутентификация', status => 401);
      return undef;
    }
    $c->stash(remote_user => $remote_user);
    $c->stash(remote_user_role => $c->users_catalog->get_user_role($remote_user));
    unless ($c->stash('remote_user_role')) {
      $c->render(text => 'Неверный пользователь', status => 401);
      return undef;
    }

    return 1;
  });

  # Router
  my $r = $self->routes;

  $r->get('/')->to('index#index');
  $r->get('/about')->to('index#about');

  $r->get('/upload')->to('upload#index');
  $r->post('/upload')->to('upload#post');#
  $r->post('/upload/cu')->to('upload#check');

  $r->get('/zupload')->to('zupload#index');
  $r->post('/zupload')->to('zupload#post');#
  $r->post('/zupload/cu')->to('zupload#check');

  $r->get('/sync')->to('sync#index');
  $r->post('/sync')->to('sync#post');#
  $r->post('/sync/cu')->to('sync#check');

  $r->get('/sync/approve')->to('syncapprove#index');
  $r->post('/sync/approve/aprv1')->to('syncapprove#aprv1');

  $r->post('/sync/merge')->to('syncmerge#post');#
  $r->post('/sync/merge/cu')->to('syncmerge#check');

  $r->get('/sync/mergearchive')->to('syncmergearchive#index');

  $r->get('/room')->to('setattrroom#room');
  $r->post('/room')->to('setattrroom#roompost');

  $r->get('/sot')->to('setattrsot#sot');
  $r->post('/sot')->to('setattrsot#sotpost');

  $r->get('/email')->to('setattremail#email');
  $r->post('/email')->to('setattremail#emailpost');

  $r->get('/photo')->to('setattrphoto#photo');
  $r->get('/photo/view')->to('setattrphoto#view');
  $r->post('/photo')->to('setattrphoto#photopost');
  $r->post('/photo/cam')->to('setattrphoto#campost');

  $r->get('/comp')->to('comp#comp');

  $r->get('/manual')->to('manual#manual');
  $r->post('/manual')->to('manual#manpost');
}


sub validate_config {
  my $self = shift;
  my $c = $self->config;

  my $e = undef;
  for (qw/personnel_ldap_base flatgroups_ldap_base dismissed_ou_dn organization_attr/) {
    unless ($c->{$_}) {
      $e = "Config parameter $_ is not defined!";
      last;
    }
  }
  for (qw/user_cleanup_skip_dn ou_cleanup_skip_dn/) {
    if (!$c->{$_} || ref($c->{$_}) ne 'ARRAY') {
      $e = "Config parameter $_ is not ARRAY!";
      last;
    }
  }
  # only one load schedule is allowed
  if ($c->{smbload_schedules} && $c->{zupload_schedules}) {
    $e = "Only ONE *load_schedule is allowed! Set unused schdules to undef.";
  }

  if ($e) {
    say $e if $self->log->path;
    $self->log->fatal($e);
    return undef;
  }
  1;
}


1;
