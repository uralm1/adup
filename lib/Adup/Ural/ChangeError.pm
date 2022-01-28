package Adup::Ural::ChangeError;
use Mojo::Base 'Adup::Ural::Change';

use Mojo::Util qw(xml_escape);
use Carp;
use Adup::Ural::LdapListsUtil qw(unescape_dn_value_full);


# my $obj = Adup::Ural::ChangeError->new($name, $dn, 'author');
sub new {
  my ($class, $name, $dn, $author) = @_;
  my $self = $class->SUPER::new($name, $dn, $author);

  $self->{error} = 'н/д';

  return $self;
}

#
# getters
#
sub type_human {
  return 'Ошибка';
}

sub type_robotic {
  return 99;
}

sub info_human {
  my $self = shift;
  my $r = '<b>DN:</b> '.xml_escape(unescape_dn_value_full($self->{dn})).'<br>';
  $r .= '<span class="info-error">'.xml_escape($self->{error}).'</span>';
  return $r;
}


# $obj->set_error($error);
sub set_error {
  my ($self, $error) = @_;
  croak 'Error text required' unless defined $error;
  $self->{error} = $error;
}

# $err = $obj->error;
sub error {
  return shift->{error};
}


# merge goes from the base object
###


1;
