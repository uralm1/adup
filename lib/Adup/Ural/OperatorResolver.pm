package Adup::Ural::OperatorResolver;
use Mojo::Base -base;

use Carp;
use Net::LDAP qw(LDAP_SUCCESS LDAP_NO_SUCH_OBJECT);
use Net::LDAP::Util qw(escape_filter_value);
use Encode qw(decode);
#use Data::Dumper;


# Adup::Ural::OperatorResolver->new($config);
sub new {
  my ($class, $config) = @_;
  croak "Config required" unless defined $config;
  return bless {
    config => $config,
    ops => {},
    time => time + 86400,
  }, $class;
}


# $resolved_operator_name = $obj->resolve($login)
sub resolve {
  my ($self, $login) = @_;
  return undef unless defined $login;

  # expired?
  if ($self->_expired) { 
    $self->{ops} = {}; # empty cache
    $self->{time} = time + 86400;
  }

  # use cache first
  return $self->{ops}{$login} if exists $self->{ops}{$login};
  
  # otherwise, get the data from ldap
  #say "REQUEST!";
  my $config = $self->{config};
  my $ldap = Net::LDAP->new($config->{ldap_servers}, port => 389, timeout => 10, version => 3);
  unless ($ldap) {
    carp "OperatorResolver: LDAP object creation error $@";
    return $login;
  }

  my $mesg = $ldap->bind($config->{ldap_user}, password => $config->{ldap_pass});
  if ($mesg->code) {
    carp "OperatorResolver: LDAP bind error ".$mesg->error;
    return $login;
  }

  my $flogin = escape_filter_value $login;
  my $filter = "(&(objectCategory=person)(objectClass=user)(sAMAccountName=$flogin))";
  $mesg = $ldap->search(base => $config->{ldap_base}, scope => 'sub',
    filter => $filter,
    attrs => ['displayName']
  );
  if ($mesg->code && $mesg->code != LDAP_NO_SUCH_OBJECT) {
    carp "OperatorResolver: LDAP search error ".$mesg->error;
    return $login;
  }
  my $resp;
  if ($mesg->count > 0) {
    my $name = $mesg->entry(0)->get_value('displayName');
    $resp = ($name) ? decode('utf-8', $name)." ($login)" : $login;
  } else {
    $resp = $login;
  }

  $ldap->unbind;

  $self->{ops}{$login} = $resp; # cache the response
  return $resp;
}


# check cache expiration
sub _expired {
  return (time > shift->{time}) ? 1 : undef; 
}

1;
