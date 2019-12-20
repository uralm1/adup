package Adup;
use Mojo::Base 'Mojolicious';

use Adup::Command::smbload;
use Adup::Command::preprocess;
use Adup::Command::sync;
use Adup::Command::merge;
use Adup::Command::resettasks;
use Adup::Ural::UsersCatalog;
use Adup::Ural::OperatorResolver;

our $VERSION = '1.9';

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

  # upload file limit 16mb
  $self->max_request_size(16777216);

  $self->plugin(Minion => {mysql => $config->{minion_db_conn}});
  # FIXME DEBUG FIXME: open access to minion UI
  $self->plugin('Minion::Admin');

  $self->plugin('Adup::Plugin::MPagenav');
  $self->plugin('Adup::Plugin::Utils');

  $self->plugin('Adup::Task::Preprocess');
  $self->plugin('Adup::Task::Sync');
  $self->plugin('Adup::Task::Merge');
  push @{$self->commands->namespaces}, 'Adup::Command';

  $self->defaults(version => $VERSION);

  $self->defaults(uc => Adup::Ural::UsersCatalog->new($self->mysql_adup));
  unless ($self->defaults('uc')) {
    die "Fatal error: Users catalog creation error!";
  }
  $self->log->debug('Users catalog created');

  $self->defaults(oprs => Adup::Ural::OperatorResolver->new($config));

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
    $c->stash(remote_user_role => $c->stash('uc')->get_user_role($remote_user));
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
}


1;
