package Adup::Ural::ChangeUserDelete;
use Mojo::Base 'Adup::Ural::Change';

use Mojo::Util qw(xml_escape);
use Carp;
use Net::LDAP qw(LDAP_SUCCESS LDAP_INSUFFICIENT_ACCESS LDAP_ALREADY_EXISTS);
use Net::LDAP::Util qw(ldap_explode_dn escape_dn_value);
use Adup::Ural::LdapListsUtil qw(unescape_dn_value_full);
use Adup::Ural::Dblog;

#use Data::Dumper;

# my $obj = Adup::Ural::ChangeUserDelete->new($name, $dn, 'author');
sub new {
  my ($class, $name, $dn, $author) = @_;
  my $self = $class->SUPER::new($name, $dn, $author);

  $self->{cn} = undef;
  $self->{login} = undef;
  $self->{email} = undef;
  $self->{disabled} = undef;

  return $self;
}

#
# getters
#
sub type_human {
  return 'Блокирование учётной записи';
}

sub type_robotic {
  return 8;
}

sub info_human {
  my $self = shift;

  my $r = '<b>DN:</b> '.xml_escape(unescape_dn_value_full($self->{dn})).'<br>';
  if ($self->{disabled}) {
    $r .= '<b>Перенос ранее отключенной учётной записи пользователя в &laquo;УВОЛЕННЫЕ&raquo;</b><br>';
  } else {
    $r .= '<b>Отключение учётной записи пользователя и перенос в &laquo;УВОЛЕННЫЕ&raquo;</b><br>';
  }
  $r .= '<span class="info-attr">ФИО:</span> &laquo;'.xml_escape($self->{cn}).'&raquo;<br>';
  $r .= '<span class="info-attr">Логин:</span> '.xml_escape($self->{login}).'<br>' if $self->{login};
  if ($self->{email}) {
    $r .= '<span class="info-attr">Имеется Email:</span> '.xml_escape($self->{email}).'<br>' ;
    $r .= '<div class="info-note">Вручную зачистите почтовый ящик и интернет доступ пользователя (если имеется).</div>';
  }
  $r .= '<div class="info-warn"><b>Зависимости!</b> Примените все изменения удаления пользователей из групп почтового справочника перед утверждением изменения.</div>';
  $r .= '<div class="info-warn">Если применение изменения завершается с ошибкой, вручную проверьте наличие дублирующейся учётной записи с тем же ФИО в папке &laquo;УВОЛЕННЫЕ&raquo; и удалите или переименуйте её.</div>';
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

# $disabled = $obj->disabled;
# $obj->disabled(1/undef);
sub disabled {
  my ($self, $new_disabled) = @_;
  return $self->{disabled} unless $new_disabled;
  $self->{disabled} = $new_disabled;
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
    carp 'Merge - delete user error (bad serach): '.$mesg->error." for DN: $self->{dn}";
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
	carp 'Merge - delete user error (cant disable account): '.$mesg->error." for DN: $self->{dn}";
	if ($mesg->code == LDAP_INSUFFICIENT_ACCESS) {
	  $args{log}->l(state=>91, info=>'Ошибка применения изменения-блокирование учетной записи (отключение учетной записи): Недостаточно прав для выполнения операции.');
	}
	return undef;
      }
      $args{ldap}->sync($mesg);
    }

    # move user account to DISMISSED
    my $mesg = $args{ldap}->moddn($self->{dn},
      newrdn => 'CN='.escape_dn_value($self->{cn}),
      deleteoldrdn => 1,
      newsuperior => $args{config}{dismissed_ou_dn},
    );
    if ($mesg->code) {
      carp 'Merge - delete user error (move to dismissed): '.$mesg->error." for DN: $self->{dn}";
      if ($mesg->code == LDAP_INSUFFICIENT_ACCESS) {
	$args{log}->l(state=>91, info=>'Ошибка применения изменения-блокирование учетной записи (перемещение учетной записи): Недостаточно прав для выполнения операции.');
      } elsif ($mesg->code == LDAP_ALREADY_EXISTS) {
	$args{log}->l(state=>91, info=>'Ошибка применения изменения-блокирование учетной записи (перемещение учетной записи): В папке УДАЛЕННЫЕ уже существует запись с одинаковым ФИО. Требуется ручное вмешательство.');
      }
      return undef;
    } else {
      my $r = $self->deletedb(db => $args{db});
      # save to archive
      $self->toarchive(db => $args{db}) if $r;
      return $r;
    }
  }

  return undef;
}

1;
