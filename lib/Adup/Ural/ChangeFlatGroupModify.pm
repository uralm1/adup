package Adup::Ural::ChangeFlatGroupModify;
use Mojo::Base 'Adup::Ural::Change';

use Mojo::Util qw(xml_escape);
use Carp;
use Net::LDAP qw(LDAP_SUCCESS LDAP_INSUFFICIENT_ACCESS);
use Adup::Ural::LdapListsUtil qw(unescape_dn_value_full);
use Adup::Ural::Dblog;


# my $obj = Adup::Ural::ChangeFlatGroupModify->new($name, $dn, 'author');
sub new {
  my ($class, $name, $dn, $author) = @_;
  my $self = $class->SUPER::new($name, $dn, $author);

  $self->{dept_name} = 'Не задано';
  $self->{old_dept_name} = 'нет данных';

  return $self;
}

#
# getters
#
sub type_human {
  return 'Изменение группы почтового справочника';
}

sub type_robotic {
  return 12;
}

sub info_human {
  my $self = shift;

  my $r = '<b>DN:</b> '.xml_escape(unescape_dn_value_full($self->{dn})).'<br>';
  $r .= '<b>Изменение</b> группы почтового справочника корпоративной почты.';
  $r .= '<br><span class="info-attr">Подразделение:</span> &laquo;'.xml_escape($self->{old_dept_name}).'&raquo; заменяется на &laquo;'.xml_escape($self->{dept_name}).'&raquo;<br>';

  return $r;
}


# $obj->set_dept_names('old dept name', 'new dept name');
sub set_dept_names {
  my ($self, $old_dept_name, $new_dept_name) = @_;
  croak 'Department name required' unless defined $old_dept_name and defined $new_dept_name;
  $self->{dept_name} = $new_dept_name;
  $self->{old_dept_name} = $old_dept_name;
}

# $dept_name = $obj->dept_name;
sub dept_name {
  return shift->{dept_name};
}

# $old_dept_name = $obj->old_dept_name;
sub old_dept_name {
  return shift->{old_dept_name};
}


# 1 or undef = $obj->merge(
#     author => 'author',
#     db => $mysql->db,
#     ldap => $ldap,
#     log => $log
#   );
sub merge {
  my ($self, %args) = @_;
  for (qw/db ldap log/) { croak 'Required parameters missing' unless defined $args{$_}};
  $args{author} ||= 'н/д';
  $self->_set_merged($args{author});

  #say "DN: $self->{dn}";

  # really modify ldap group description
  my $mesg = $args{ldap}->modify($self->{dn},
    replace => { description => $self->{dept_name} }
  );

  if ($mesg->code == LDAP_SUCCESS) {
    my $r = $self->deletedb(db => $args{db});
    # save to archive
    $self->toarchive(db => $args{db}) if $r;
    return $r;
  }

  carp 'Merge - modify phone group error: '.$mesg->error." for DN: $self->{dn}" if $mesg->code;
  if ($mesg->code == LDAP_INSUFFICIENT_ACCESS) {
    $args{log}->l(state=>91, info=>'Ошибка применения изменения-модификации группы почтового справочника: Недостаточно прав для выполнения операции.');
  }
  return undef;
}

1;
