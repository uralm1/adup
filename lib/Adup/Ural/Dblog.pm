package Adup::Ural::Dblog;
use Mojo::Base -base;

use Carp;
use Mojo::mysql;

# Adup::Ural::Dblog->new($db, login=>'user', state=>0);
sub new {
  my ($class, $db, %logdata) = @_;
  croak 'Database required' unless defined $db;
  my $self = bless {
    db => $db,
    login => undef,
    state => undef,
  }, $class;
  $self->{login} = $logdata{login} if defined $logdata{login};
  $self->{state} = $logdata{state} if defined $logdata{state};
  return $self;
}

# $obj->l([login=>'user',] [state=>0,] info=>"some log text");
sub l {
  my $self = shift;
  my $logdata = {@_};

  my $login = (defined $logdata->{login}) ? $logdata->{login} : $self->{login};
  my $state = (defined $logdata->{state}) ? $logdata->{state} : $self->{state};
  croak 'Parameter missing' unless (defined $login and defined $state); 

  $logdata->{info} = 'н/д' unless $logdata->{info};
  $login = 'н/д' unless $login;
  my $e = eval {
    $self->{db}->query("INSERT INTO op_log \
      (login, date, state, info) VALUES (?, NOW(), ?, ?)",
      $login, $state, $logdata->{info});
  };
  unless (defined $e) {
    carp "Log record ($login, $state) hasn't been inserted.";
  }
}


1;
