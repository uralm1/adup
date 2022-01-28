package Adup::Ural::ChangeUserDisableDismissed;
use Mojo::Base 'Adup::Ural::Change';

use Mojo::Util qw(xml_escape);
use Carp;
use Net::LDAP qw(LDAP_SUCCESS LDAP_INSUFFICIENT_ACCESS LDAP_ALREADY_EXISTS);
use Net::LDAP::Util qw(ldap_explode_dn escape_dn_value);
use Adup::Ural::LdapListsUtil qw(unescape_dn_value_full);
use Adup::Ural::Dblog;

#use Data::Dumper;

# my $obj = Adup::Ural::ChangeUserDisableDismissed->new($name, $dn, 'author');
sub new {
  my ($class, $name, $dn, $author) = @_;
  my $self = $class->SUPER::new($name, $dn, $author);

  $self->{cn} = undef;
  $self->{login} = undef;
  $self->{email} = undef;

  return $self;
}

#
# getters
#
sub type_human {
  return 'Блокирование архивной учётной записи';
}

sub type_robotic {
  return 14;
}

sub info_human {
  my $self = shift;

  my $r = '<span class="info-error">ОБНАРУЖЕНА АКТИВНАЯ АРХИВНАЯ УЧЁТНАЯ ЗАПИСЬ УВОЛЕННОГО СОТРУДНИКА!</span><br>';
  $r .= '<b>DN:</b> '.xml_escape(unescape_dn_value_full($self->{dn})).'<br>';
  $r .= '<b>Отключение включенной архивной учётной записи пользователя в &laquo;УВОЛЕННЫХ&raquo;</b><br>';
  $r .= '<span class="info-attr">ФИО:</span> &laquo;'.xml_escape($self->{cn}).'&raquo;<br>';
  $r .= '<span class="info-attr">Логин:</span> '.xml_escape($self->{login}).'<br>' if $self->{login};
  if ($self->{email}) {
    $r .= '<span class="info-attr">Указан Email:</span> '.xml_escape($self->{email}).'<br>' ;
    $r .= '<div class="info-note">Вручную проверьте, возможно всё ещё открыт почтовый ящик и интернет доступ пользователя.</div>';
  }
  $r .= '<div class="info-warn"><b>Внимание!</b> Применение изменения вызовет прекращение доступа пользователя.</div>' unless $self->{disabled};

  return $r;
}


# $cn = $obj->cn;
# $obj->cn($new_cn);
sub cn {
  my ($self, $new_cn) = @_;
  return $self->{cn} unless $new_cn;
  $self->{cn} = $new_cn;
}

# $login = $obj->login;
# $obj->login($new_login);
sub login {
  my ($self, $new_login) = @_;
  return $self->{login} unless $new_login;
  $self->{login} = $new_login;
}

# $email = $obj->email;
# $obj->email($new_email);
sub email {
  my ($self, $new_email) = @_;
  return $self->{email} unless $new_email;
  $self->{email} = $new_email;
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
  croak 'dismissed_ou_dn config required' unless defined $args{config}{dismissed_ou_dn};
  $args{author} ||= 'н/д';
  $self->_set_merged($args{author});

  #say "DN: $self->{dn}";
  # get user entry first
  my $mesg = $args{ldap}->search(base => $self->{dn}, scope => 'base',
    filter => '(&(objectCategory=person)(objectClass=user))',
    attrs => ['userAccountControl'],
  );
  if ($mesg->code) {
    # LDAP_NO_SUCH_OBJECT error too
    carp 'Merge - disable dismissed user error (bad serach): '.$mesg->error." for DN: $self->{dn}";
    return undef;
  }

  if ($mesg->count > 0) {
    my $entry = $mesg->entry(0);
    my $uac = $entry->get_value('userAccountControl') || 0x200; # NORMAL_ACCOUNT

    # disable user account
    if (($uac & 2) != 2) {
      $entry->replace('userAccountControl' => ($uac | 2)); # set ACCOUNTDISABLE bit
      $mesg = $entry->update($args{ldap});
      if ($mesg->code) {
	carp 'Merge - disable dismissed user error (cant disable account): '.$mesg->error." for DN: $self->{dn}";
	if ($mesg->code == LDAP_INSUFFICIENT_ACCESS) {
	  $args{log}->l(state=>91, info=>'Ошибка применения изменения-блокирование архивной учетной записи (отключение учетной записи): Недостаточно прав для выполнения операции.');
	}
	return undef;
      }
      $args{ldap}->sync($mesg);
    }

    my $r = $self->deletedb(db => $args{db});
    # save to archive
    $self->toarchive(db => $args{db}) if $r;
    return $r;
  }

  return undef;
}

1;
