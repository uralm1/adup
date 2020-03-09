package Adup::Command::cron;
use Mojo::Base 'Mojolicious::Command';

use Carp;
use Mojo::IOLoop;
use Mojo::Log;
use Algorithm::Cron;
use Data::Dumper;

has description => 'Run builtin cron agent';
has usage => "Usage: APPLICATION cron\n";

sub run {
  my $self = shift;
  my $app = $self->app;
  my $log = Mojo::Log->new;

  binmode(STDOUT, ':utf8');
  #binmode(STDERR, ':utf8');

  $log->info("start!");
  my $sh = $app->config('smbload_schedules');
  #ref $sh;

  # use new special IOLoop
  my $loop = Mojo::IOLoop->new;
  local $SIG{INT} = local $SIG{TERM} = sub { $loop->stop };

  $loop->next_tick(sub { 
    #$self->_cron($loop, $_, $log) for ("*/2 * * * *", "20 */3 * * * *");
    $self->_cron($loop, $_, $log) for ("*/2 * * * *");
  });

  $loop->start;
  $log->info("end!");
}

sub _cron() {
  my ($self, $loop, $sh, $log) = @_;
  say "in _cron($sh)!";

  my $cron = Algorithm::Cron->new(
    base => 'local',
    crontab => $sh,
  );

  my $time = time;
  # $cron, $time goes to closure
  my $task;
  $task = sub {
    $time = $cron->next_time($time);
    if ($time - time <= 0) {
      say "Time diff negative!!!";
      $time = $cron->next_time($time);
      if ($time - time <= 0) {say "Time diff negative 2!!!";}
    }
    $loop->timer(($time - time) => sub { 
      $log->info("CRON EVENT start!");
      sleep(180);
      $log->info("CRON EVENT end!");
      $task->();
    });
  };
  $task->();
}

#-------------------------------------------------

1;
