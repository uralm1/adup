package Adup::Ural::ChangeOUModify;
use Mojo::Base 'Adup::Ural::Change';

use Mojo::Util qw(xml_escape);
use Carp;
use Net::LDAP qw(LDAP_SUCCESS LDAP_INSUFFICIENT_ACCESS);
use Net::LDAP::Util qw(ldap_explode_dn unescape_dn_value);
use Adup::Ural::Dblog;


# my $obj = Adup::Ural::ChangeOUModify->new($name, $dn, 'author');
sub new {
  my ($class, $name, $dn, $author) = @_;
  my $self = $class->SUPER::new($name, $dn, $author);

  $self->{dept_name} = 'Не задано';
  $self->{old_dept_name} = 'нет данных';
  $self->{level} = 0;

  return $self;
}

#
# getters
#
sub type_human {
  return 'Изменение подразделения';
}

sub type_robotic {
  return 22;
}

sub info_human {
  my $self = shift;

  my $r = '<b>DN:</b> '.xml_escape(unescape_dn_value($self->{dn})).'<br>';
  $r .= '<b>Изменение</b> подразделения '.xml_escape($self->{level}).'-го уровня иерархии.';
  $r .= '<br><span class="info-attr">Подразделение:</span> &laquo;'.xml_escape($self->{old_dept_name}).'&raquo; заменяется на &laquo;'.xml_escape($self->{dept_name}).'&raquo;<br>';
  #$r .= '<div class="info-warn"><b>Зависимости!</b> Примените все изменения подразделений более верхнего уровня иерархии перед утверждением данного изменения.</div>' if $self->{level} > 0;

  return $r;
}


# $obj->set_level_dept_names(0, 'old dept name', 'new dept name');
sub set_level_dept_names {
  my ($self, $level, $old_dept_name, $new_dept_name) = @_;
  croak 'Department level required' unless defined $level;
  croak 'Department name required' unless defined $old_dept_name and defined $new_dept_name;
  $self->{level} = $level;
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

# $level = $obj->level;
sub level {
  return shift->{level};
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

  # really modify ldap ou
  my $mesg = $args{ldap}->modify($self->{dn},
    replace => { description => $self->{dept_name} }
  );

  if ($mesg->code == LDAP_SUCCESS) {
    my $r = $self->deletedb(db => $args{db});
    # save to archive
    $self->toarchive(db => $args{db}) if $r;
    return $r;
  }

  carp 'Merge - modify OU error: '.$mesg->error." for DN: $self->{dn}" if $mesg->code;
  if ($mesg->code == LDAP_INSUFFICIENT_ACCESS) {
    $args{log}->l(state=>91, info=>'Ошибка применения изменения-модификации подразделения: Недостаточно прав для выполнения операции.');
  }
  return undef;
}

1;
