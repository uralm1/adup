package Adup::Ural::ChangeUserFlatGroup;
use Mojo::Base 'Adup::Ural::Change';

use Mojo::Util qw(xml_escape);
use Carp;
use Net::LDAP qw(LDAP_SUCCESS LDAP_INSUFFICIENT_ACCESS LDAP_ALREADY_EXISTS);
use Net::LDAP::Util qw(ldap_explode_dn canonical_dn unescape_dn_value);
use Adup::Ural::Dblog;
use Encode qw(decode_utf8);

#use Data::Dumper;

has 'member_cn';
has 'member_dn';
has 'flatgroup_name';

# my $obj = Adup::Ural::ChangeUserFlatGroup->new($name, $dn, 'author');
sub new {
  my ($class, $name, $dn, $author) = @_;
  my $self = $class->SUPER::new($name, $dn, $author);

  return $self;
}


sub type_human {
  return 'Удаление пользователя из группы почтового справочника';
}

sub type_robotic {
  return 13;
}

sub info_human {
  my $self = shift;

  my $r = '<b>DN:</b> '.xml_escape(unescape_dn_value($self->{dn})).'<br>';
  $r .= '<b>Удаление</b> учётной записи пользователя <b>из группы почтового справочника.</b><br>';
  $r .= '<span class="info-attr">ФИО:</span> '.xml_escape($self->member_cn).'<br>';
  $r .= '<span class="info-attr">Группа почтового справочника:</span> &laquo;'.xml_escape($self->flatgroup_name).'&raquo;.';

  return $r;
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
  for (qw/member_dn/) { croak "$_ attribute is missing" unless defined $self->{$_}};
  $args{author} ||= 'н/д';
  $self->_set_merged($args{author});

  #say "DN: $self->{dn}";
  #say 'Member DN: '.decode_utf8($self->member_dn);
  # really remove user from group
  my $mesg = $args{ldap}->modify($self->{dn},
    delete => {
      member => [ decode_utf8($self->member_dn) ],
    }
  );

  if ($mesg->code == LDAP_SUCCESS) {
    my $r = $self->deletedb(db => $args{db});
    # save to archive
    $self->toarchive(db => $args{db}) if $r;
    return $r;
  }

  carp 'Merge - remove user from flatgroup error: '.$mesg->error." for DN: $self->{dn}" if $mesg->code;
  if ($mesg->code == LDAP_INSUFFICIENT_ACCESS) {
    $args{log}->l(state=>91, info=>'Ошибка применения изменения-удаления пользователя из группы почтового справочника: Недостаточно прав для выполнения операции.');
  }
  return undef;
}

1;
