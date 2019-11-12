package Adup::Ural::ChangeFlatGroupCreate;
use Mojo::Base 'Adup::Ural::Change';

use Mojo::Util qw(xml_escape);
use Carp;
use Net::LDAP qw(LDAP_SUCCESS LDAP_INSUFFICIENT_ACCESS);
use Net::LDAP::Util qw(ldap_explode_dn unescape_dn_value);
use Adup::Ural::Dblog;


# my $obj = Adup::Ural::ChangeFlatGroupCreate->new($name, $dn, 'author');
sub new {
  my ($class, $name, $dn, $author) = @_;
  my $self = $class->SUPER::new($name, $dn, $author);

  $self->{dept_name} = 'Не задано';

  return $self;
}

#
# getters
#
sub type_human {
  return 'Создание группы почтового справочника';
}

sub type_robotic {
  return 10;
}

sub info_human {
  my $self = shift;

  my $r = '<b>DN:</b> '.xml_escape(unescape_dn_value($self->{dn})).'<br>';
  $r .= '<b>Создание</b> группы почтового справочника корпоративной почты.';
  $r .= '<br><span class="info-attr">Подразделение:</span> устанавливается &laquo;'.xml_escape($self->{dept_name}).'&raquo;<br>';

  return $r;
}


# $obj->set_dept_name('new dept name');
sub set_dept_name {
  my ($self, $dept_name) = @_;
  croak 'Department name required' unless defined $dept_name;
  $self->{dept_name} = $dept_name;
}

# $dept_name = $obj->dept_name;
sub dept_name {
  return shift->{dept_name};
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
  my $n = $aofh->[0]{CN};
  croak 'CN extraction failure' unless $n;

  # really add ldap group
  my $mesg = $args{ldap}->add($self->{dn},
    attrs => [
      objectClass => [ qw/top group/ ],
      cn => $n,
      sAMAccountName => $n,
      groupType => 0x2,
      description => $self->{dept_name},
    ]
  );

  if ($mesg->code == LDAP_SUCCESS) {
    my $r = $self->deletedb(db => $args{db});
    # save to archive
    $self->toarchive(db => $args{db}) if $r;
    return $r;
  }

  carp 'Merge - create phone group error: '.$mesg->error." for DN: $self->{dn}" if $mesg->code;
  if ($mesg->code == LDAP_INSUFFICIENT_ACCESS) {
    $args{log}->l(state=>91, info=>'Ошибка применения изменения-создания группы почтового справочника: Недостаточно прав для выполнения операции.');
  }
  return undef;
}

1;
