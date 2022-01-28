package Adup::Ural::ChangeFlatGroupDelete;
use Mojo::Base 'Adup::Ural::Change';

use Mojo::Util qw(xml_escape);
use Carp;
use Net::LDAP qw(LDAP_SUCCESS LDAP_INSUFFICIENT_ACCESS LDAP_NO_SUCH_OBJECT);
use Net::LDAP::Util qw(ldap_explode_dn);
use Adup::Ural::LdapListsUtil qw(checkdnbase unescape_dn_value_full);
use Adup::Ural::Dblog;


# my $obj = Adup::Ural::ChangeFlatGroupDelete->new($name, $dn, 'author');
sub new {
  my ($class, $name, $dn, $author) = @_;
  my $self = $class->SUPER::new($name, $dn, $author);

  return $self;
}

#
# getters
#
sub type_human {
  return 'Удаление группы почтового справочника';
}

sub type_robotic {
  return 11;
}

sub info_human {
  my $self = shift;

  my $r = '<b>DN:</b> '.xml_escape(unescape_dn_value_full($self->{dn})).'<br>';
  $r .= '<b>Удаление группы почтового справочника корпоративной почты.</b>';
  $r .= '<br><span class="info-attr">Подразделение:</span> &laquo;'.xml_escape($self->{name}).'&raquo;<br>';

  return $r;
}


# 1 or undef = $obj->merge(
#     author => 'author',
#     db => $mysql->db,
#     ldap => $ldap,
#     config => $config,
#     log => $log
#   );
sub merge {
  my ($self, %args) = @_;
  for (qw/db ldap config log/) { croak 'Required parameters missing' unless defined $args{$_}};
  croak 'flatgroups_ldap_base config required' unless defined $args{config}{flatgroups_ldap_base};
  $args{author} ||= 'н/д';
  $self->_set_merged($args{author});

  #say "DN: $self->{dn}";
  # safety check
  unless (checkdnbase($self->{dn}, $args{config}{flatgroups_ldap_base})) {
    carp "Merge - refuse to delete flatgroup, bad base in DN: $self->{dn}";
    return undef;
  }

  # really delete ldap group
  my $mesg = $args{ldap}->delete($self->{dn});

  if ($mesg->code == LDAP_SUCCESS) {
    my $r = $self->deletedb(db => $args{db});
    # save to archive
    $self->toarchive(db => $args{db}) if $r;
    return $r;
  }

  carp 'Merge - delete flatgroup error: '.$mesg->error." for DN: $self->{dn}" if $mesg->code;
  if ($mesg->code == LDAP_INSUFFICIENT_ACCESS) {
    $args{log}->l(state=>91, info=>'Ошибка применения изменения-удаления группы почтового справочника: Недостаточно прав для выполнения операции.');
  }
  return undef;
}

1;
