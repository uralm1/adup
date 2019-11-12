package Adup::Command::resettasks;
use Mojo::Base 'Mojolicious::Command';

#use Data::Dumper;

has description => '** Clean up tasks state';
has usage => "Usage: APPLICATION resettasks\n";

sub run {
  my $self = shift;
  my $app = $self->app;
  my $db = $app->mysql_adup->db;

  $app->reset_task_state($db, $_) for (qw/preprocess_id sync_id merge_id/);
  say 'Tasks states were cleaned up.';

  return 1;
}


1;
