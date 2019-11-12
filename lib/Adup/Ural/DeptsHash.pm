package Adup::Ural::DeptsHash;
use Mojo::Base -base;

use Mojo::mysql;
use Carp;

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


1;
