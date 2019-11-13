package Adup::Ural::DeptsHash;
use Mojo::Base -base;

use Mojo::mysql;
use Carp;
use Net::LDAP::Util qw(escape_dn_value);

# my $depts_hash = Adup::Ural::DeptsHash->new($db);
sub new {
  my ($class, $db) = @_;
  croak 'Database required' unless defined $db;
  my $self = bless {}, $class;

  # first extract all dept records into one hash cache
  my $e = eval {
    my $res = $db->query("SELECT id, name, parent \
      FROM depts \
      ORDER BY id ASC");
    while (my $next = $res->hash) {
      $self->{$next->{id}} = { name=>$next->{name}, parent=>$next->{parent} };
    }
    $res->finish;
  };
  unless (defined $e) {
    carp 'DeptsHash - database fatal error';
    return undef;
  }

  # done
  return $self;
}

#
# usage: $depts_hash->{id}{name} or $depts_hash->{id}{parent}
#


# $user_dn = $dept_hash->build_user_dn($cn, $parent_dept_id, $pers_ldapbase);
sub build_user_dn {
  my ($self, $cn, $parent_id, $ldapbase) = @_;

  my $dn_built = 'CN='.escape_dn_value($cn).',';
  $self->append_dn_hier(undef, $parent_id, \$dn_built);
  $dn_built .= $ldapbase;
  return $dn_built;
}

# $ou_dn = $dept_hash->build_ou_dn($ou_name, $level, $parent_dept_id, $pers_ldapbase);
sub build_ou_dn {
  my ($self, $ou, $level, $parent_id, $ldapbase) = @_;

  my $dn_built = 'OU='.escape_dn_value($ou).',';
  $self->append_dn_hier($level, $parent_id, \$dn_built);
  $dn_built .= $ldapbase;
  return $dn_built;
}


# internal
# $dept_hash->append_dn_hier(undef, $next->{dept_id}, \$dn); (1)
# $depts_hash->append_dn_hier($level, $next->{parent}, \$dn); (2)
sub append_dn_hier {
  my ($self, $level, $cur_parent, $dn_ref) = @_;
 
  if (defined $level) {
    return 1 if ($level == 0);
    #say "processing uplevel: $level";
  } else {
    return 1 if ($cur_parent == 0);
  }

  if (my $vh = $self->{$cur_parent}) {
    my $ouname = substr($vh->{name}, 0, 64);
    my $name_dn = escape_dn_value $ouname;
    $$dn_ref .= "OU=$name_dn,";
    if (defined $level) {
      $self->append_dn_hier(--$level, $vh->{parent}, $dn_ref);
    } else {
      $self->append_dn_hier(undef, $vh->{parent}, $dn_ref);
    }
  } else {
    carp "DN Hierarhy build failure. Unexpected database structure problem.";
    return 0;
  }
}


1;
