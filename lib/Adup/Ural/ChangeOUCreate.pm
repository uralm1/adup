package Adup::Ural::ChangeOUCreate;
use Mojo::Base 'Adup::Ural::Change';

use Mojo::Util qw(xml_escape);
use Carp;
use Net::LDAP qw(LDAP_SUCCESS LDAP_INSUFFICIENT_ACCESS);
use Net::LDAP::Util qw(ldap_explode_dn unescape_dn_value);
use Adup::Ural::Dblog;


# my $obj = Adup::Ural::ChangeOUCreate->new($name, $dn, 'author');
sub new {
  my ($class, $name, $dn, $author) = @_;
  my $self = $class->SUPER::new($name, $dn, $author);

  $self->{dept_name} = 'Не задано';
  $self->{level} = 0;

  return $self;
}

#
# getters
#
sub type_human {
  return 'Создание подразделения';
}

sub type_robotic {
  return 20;
}

sub info_human {
  my $self = shift;

  my $r = '<b>DN:</b> '.xml_escape(unescape_dn_value($self->{dn})).'<br>';
  $r .= '<b>Создание</b> подразделения '.xml_escape($self->{level}).'-го уровня иерархии.';
  $r .= '<br><span class="info-attr">Наименование:</span> &laquo;'.xml_escape($self->{dept_name}).'&raquo;<br>';
  $r .= '<div class="info-warn"><b>Зависимости!</b> Примените все изменения подразделений более верхнего уровня иерархии перед утверждением данного изменения.</div>' if $self->{level} > 0;

  return $r;
}


# $obj->set_level_dept_name(0, 'new dept name');
sub set_level_dept_name {
  my ($self, $level, $dept_name) = @_;
  croak 'Department level required' unless defined $level;
  croak 'Department name required' unless defined $dept_name;
  $self->{level} = $level;
  $self->{dept_name} = $dept_name;
}

# $dept_name = $obj->dept_name;
sub dept_name {
  return shift->{dept_name};
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

  #say "DN: $self->{dn}";
  my $aofh = ldap_explode_dn($self->{dn});
  croak 'DN is invalid' unless $aofh;
  my $n = $aofh->[0]{OU};
  croak 'OU extraction failure' unless $n;

  # really add ldap ou
  my $mesg = $args{ldap}->add($self->{dn},
    attrs => [
      objectClass => [ qw/top organizationalUnit/ ],
      ou => $n,
      description => $self->{dept_name},
    ]
  );

  if ($mesg->code == LDAP_SUCCESS) {
    my $r = $self->deletedb(db => $args{db});
    # save to archive
    $self->toarchive(db => $args{db}) if $r;
    return $r;
  }

  carp 'Merge - create OU error: '.$mesg->error." for DN: $self->{dn}" if $mesg->code;
  if ($mesg->code == LDAP_INSUFFICIENT_ACCESS) {
    $args{log}->l(state=>91, info=>'Ошибка применения изменения-создания подразделения: Недостаточно прав для выполнения операции.');
  }
  return undef;
}

1;
