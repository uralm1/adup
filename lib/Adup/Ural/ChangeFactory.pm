package Adup::Ural::ChangeFactory;
use Mojo::Base -base;

use Carp;
use Mojo::JSON qw(from_json);


# $obj = Adup::Ural::ChangeFactory->fromdb(id => $id, json => $jsrec);
sub fromdb {
  my ($class, %args) = @_;
  croak 'Id/JSON required' unless defined $args{id} and defined $args{json};

  my $h = from_json $args{json};
  croak 'JSON bad type' unless ref($h) eq 'HASH';

  $h->{id} = $args{id};
  my $class_type = $h->{type};
  return bless $h, $class_type;
}


1;
