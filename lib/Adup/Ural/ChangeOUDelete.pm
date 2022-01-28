package Adup::Ural::ChangeOUDelete;
use Mojo::Base 'Adup::Ural::Change';

use Mojo::Util qw(xml_escape);
use Carp;
use Net::LDAP qw(LDAP_SUCCESS LDAP_INSUFFICIENT_ACCESS LDAP_NO_SUCH_OBJECT LDAP_NOT_ALLOWED_ON_NONLEAF);
use Net::LDAP::Util qw(ldap_explode_dn);
use Adup::Ural::LdapListsUtil qw(checkdnbase unescape_dn_value_full);
use Adup::Ural::Dblog;


# my $obj = Adup::Ural::ChangeOUDelete->new($name, $dn, 'author');
sub new {
  my ($class, $name, $dn, $author) = @_;
  my $self = $class->SUPER::new($name, $dn, $author);

  $self->{level} = undef;

  return $self;
}

#
# getters
#
sub type_human {
  return 'Удаление подразделения';
}

sub type_robotic {
  return 21;
}

sub info_human {
  my $self = shift;

  my $r = '<b>DN:</b> '.xml_escape(unescape_dn_value_full($self->{dn})).'<br>';
  $r .= '<b>Удаление неактуального подразделения';
  $r .= (defined $self->{level}) ? ' '.xml_escape($self->{level}).'-го уровня иерархии.' : '.';
  $r .= '</b>';
  $r .= '<br><span class="info-attr">Наименование:</span> &laquo;'.xml_escape($self->{name}).'&raquo;<br>';
  $r .= '<div class="info-warn"><b>Зависимости!</b> Примените все изменения пользователей и изменения подразделений более низкого уровня иерархии перед утверждением данного изменения.</div>';
  $r .= '<div class="info-warn"><b>Внимание!</b> Убедитесь, что в удаляемом подразделении отсутствуют учётные записи пользователей и другие вложенные подразделения. В противном случае применение изменения завершится с ошибкой.</div>';

  return $r;
}

# $l = $obj->level;
# $obj->level($new_level);
sub level {
  my ($self, $new_level) = @_;
  return $self->{level} unless defined $new_level;
  $self->{level} = $new_level;
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
  croak 'personnel_ldap_base config required' unless defined $args{config}{personnel_ldap_base};
  $args{author} ||= 'н/д';
  $self->_set_merged($args{author});

  #say "DN: $self->{dn}";
  # safety check
  unless (checkdnbase($self->{dn}, $args{config}{personnel_ldap_base})) {
    carp "Merge - refuse to delete department, bad base in DN: $self->{dn}";
    return undef;
  }

  # really delete ldap OU
  my $mesg = $args{ldap}->delete($self->{dn});

  if ($mesg->code == LDAP_SUCCESS) {
    my $r = $self->deletedb(db => $args{db});
    # save to archive
    $self->toarchive(db => $args{db}) if $r;
    return $r;
  }

  carp 'Merge - delete OU error: '.$mesg->error." for DN: $self->{dn}" if $mesg->code;
  if ($mesg->code == LDAP_INSUFFICIENT_ACCESS) {
    $args{log}->l(state=>91, info=>'Ошибка применения изменения-удаления подразделения: Недостаточно прав для выполнения операции.');
  } elsif ($mesg->code == LDAP_NOT_ALLOWED_ON_NONLEAF) {
    $args{log}->l(state=>91, info=>'Ошибка применения изменения-удаления подразделения: В удаляемом подразделении имеются дочерние объекты.');
  }
  return undef;
}

1;
