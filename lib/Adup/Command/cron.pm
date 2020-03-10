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

  my $sh = $app->config('smbload_schedules');
  if (!$sh || ref($sh) ne 'ARRAY' || !@$sh) {
    $log->info('Config parameter smbload_schedules is undefined or empty. Scheduler process will exit.');
    return 0;
  }

  $log->info("Internal scheduler process started.");

  # use new special IOLoop
  my $loop = Mojo::IOLoop->new;
  local $SIG{INT} = local $SIG{TERM} = sub { $loop->stop };

  $loop->next_tick(sub { 
    $self->_cron($loop, $_) for (@$sh);
  });

  $loop->start;
  $log->info("Internal scheduler finished.");
}

sub _cron() {
  my ($self, $loop, $sh) = @_;
  my $log = $self->app->log;
  #say "in _cron($sh)!";

  my $cron = Algorithm::Cron->new(
    base => 'local',
    crontab => $sh,
  );
  $log->info("Schedule \"$sh\" active.");

  my $time = time;
  # $cron, $time goes to closure
  my $task;
  $task = sub {
    $time = $cron->next_time($time);
    while ($time - time <= 0) {
      #say "Time diff negative!";
      $time = $cron->next_time($time);
    }
    $loop->timer(($time - time) => sub { 
      $log->info("EVENT from schedule \"$sh\" started.");
      $self->app->commands->run('smbload');
      $log->info("EVENT from schedule \"$sh\" finished.");
      $task->();
    });
  };
  $task->();
}

#-------------------------------------------------

1;
