package Adup::Ural::UsersCatalog;
use Mojo::Base -base;

use Carp;
#use Data::Dumper;
use Mojo::mysql;


# Adup::Ural::UsersCatalog->new($mysql_obj);
sub new {
  my ($class, $db_obj) = @_;
  croak "Database object required" unless defined $db_obj;
  my $self = bless {
    db_obj => $db_obj,
    users => undef,
    time => time + 86400,
  }, $class;
  return undef unless( $self->_load($db_obj->db) );
  return $self;
}

# internal
sub _load {
  my ($self, $db) = @_;
  #say 'RELOAD!';
  my $e = eval {
    $self->{users} = {};
    my $rec = $db->query('SELECT login,role FROM users');
    while (my $next = $rec->hash) {
      $self->{users}{$next->{login}} = {
	role => $next->{role},
      };
    }
    $rec->finish;
  };
  unless (defined $e) {
    carp $@;
    return undef;
  }

  return 1;
}

# internal
sub _test_assign {
  my ($self, $users_config) = @_;
  $self->{users} = $users_config;
  return 1;
}

#
# getters
#
sub get_users {
  return shift->{users};
}

# $u_or_undef = $obj->get_user('mylogin')
sub get_user {
  my ($self, $login) = @_;

  # expired?
  if ($self->_expired) { 
    # reload $self->{users}
    return undef unless( $self->_load($self->{db_obj}->db) );
    $self->{time} = time + 86400;
  }

  unless (defined $self->{users}{$login}) {
    carp "Unknown user $login";
    return undef;
  }
  return $self->{users}{$login};
}

# $role_or_undef = $obj->get_user_role('mylogin')
sub get_user_role {
  my ($self, $login) = @_;
  my $u = $self->get_user($login);
  return undef unless defined $u;
  return $u->{role};
}


# internal
# check cache expiration
sub _expired {
  return (time > shift->{time}) ? 1 : undef; 
}


1;
