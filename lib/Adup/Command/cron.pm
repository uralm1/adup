package Adup::Command::cron;
use Mojo::Base 'Mojolicious::Command';

use Carp;
use Mojo::IOLoop;
use Mojo::Log;
use Algorithm::Cron;

has description => '* Run builtin internal scheduler';
has usage => "Usage: APPLICATION cron\n";

sub run {
  my $self = shift;
  my $app = $self->app;
  my $log = $app->log;

  binmode(STDOUT, ':utf8');
  #binmode(STDERR, ':utf8');

  # select right schedule and command
  my ($sh, $cmd);
  if ($app->config('smbload_schedules')) {
    $sh = $app->config('smbload_schedules');
    $cmd = 'smbload';
  } elsif ($app->config('zupload_schedules')) {
    $sh = $app->config('zupload_schedules');
    $cmd = 'zupload';
  } else {
    $log->warn('No schedules are defined. Scheduler process will exit.');
    return 0;
  }

  if (!$sh || ref($sh) ne 'ARRAY' || !@$sh) {
    $log->warn('Config parameter *_schedules is undefined or empty. Scheduler process will exit.');
    return 0;
  }

  $log->info("Internal scheduler process started.");

  # use Poll reactor to catch signals, or we have to call EV::Signal to install signals into EV
  Mojo::IOLoop->singleton->reactor(Mojo::Reactor::Poll->new);

  local $SIG{INT} = local $SIG{TERM} = sub { Mojo::IOLoop->stop };

  Mojo::IOLoop->next_tick(sub {
    $self->_cron($sh, $_, $cmd) for (0 .. $#$sh);
  });

  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
  $log->info("Internal scheduler finished.");
}

sub _cron() {
  my ($self, $sh, $idx, @cmd) = @_;
  my $log = $self->app->log;
  my $crontab = $sh->[$idx];
  carp 'Bad crontab' unless $crontab;

  my $cron = Algorithm::Cron->new(
    base => 'local',
    crontab => $crontab,
  );
  $log->info("Schedule ($idx: \"$crontab\") active.");

  my $time = time;
  # $cron, $time goes to closure
  my $task;
  $task = sub {
    $time = $cron->next_time($time);
    while ($time - time <= 0) {
      #say "Time diff negative!";
      $time = $cron->next_time($time);
    }
    Mojo::IOLoop->timer(($time - time) => sub {
      $log->info("EVENT from schedule ($idx) started.");
      my $e = eval { $self->app->commands->run(@cmd) };
      my $es = (defined $e) ? "code: $e":"with error: $@";
      $log->info("EVENT from schedule ($idx) finished $es.");
      $task->();
    });
  };
  $task->();
}

#-------------------------------------------------

1;
