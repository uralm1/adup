package Adup::Ural::ChangeUserCreate;
use Mojo::Base 'Adup::Ural::Change';

use Mojo::Util qw(xml_escape);
use Carp;
use Net::LDAP qw(LDAP_SUCCESS LDAP_INSUFFICIENT_ACCESS LDAP_ALREADY_EXISTS);
use Adup::Ural::LdapListsUtil qw(unescape_dn_value_full);

use Adup::Ural::Dblog;
use Adup::Ural::AttrTranslate qw(translate);
use Adup::Ural::LoginAI;

#use Data::Dumper;

# my $obj = Adup::Ural::ChangeUserCreate->new($name, $dn, 'author');
sub new {
  my ($class, $name, $dn, $author) = @_;
  my $self = $class->SUPER::new($name, $dn, $author);

  $self->{cn} = 'Не задано';
  $self->{attrs} = {};
  $self->{flatgroup} = undef; #don't add user to flatgroup

  return $self;
}

#
# getters
#
sub type_human {
  return 'Создание учётной записи';
}

sub type_robotic {
  return 2;
}

sub info_human {
  my $self = shift;

  my $r = '<b>DN:</b> '.xml_escape(unescape_dn_value_full($self->{dn}));
  $r .= '<br><b>Создание отключенной учётной записи пользователя</b>';
  for (sort keys %{$self->{attrs}}) {
    $r .= '<br><span class="info-attr">'.translate($_).':</span> ';
    $r .= '&laquo;'.xml_escape($self->attr($_)).'&raquo;;';
  }
  $r .= '<br><b>Пользователь будет добавлен в группу почтового справочника:</b> &laquo;'.xml_escape($self->{flatgroup}{name}).'&raquo;.' if $self->{flatgroup};
  $r .= '<div class="info-warn"><b>Логин</b> пользователя будет автоматически сгенерирован при применении данного изменения.</div>';
  $r .= '<div class="info-warn"><b>Зависимости!</b> Примените все изменения подразделений перед утверждением изменения.</div>';

  return $r;
}


# $obj->set_cn($cn);
sub set_cn {
  my ($self, $cn) = @_;
  croak 'CN required' unless defined $cn;
  $self->{cn} = $cn;
}

# $obj->set_attr('sn', $val);
sub set_attr {
  my ($self, $attr, $val) = @_;
  croak 'Attribute/value required' unless defined $attr and defined $val;
  $self->{attrs}{$attr} = $val;
}

# $obj->set_flatgroup($flatgroup_dn, $flatdept_name);
sub set_flatgroup {
  my ($self, $fgdn, $fgname) = @_;
  croak 'Flatgroup dn and name required' unless defined $fgdn and defined $fgname;
  $self->{flatgroup} = { dn => $fgdn, name => $fgname };
}

# $cn = $obj->cn;
sub cn {
  return shift->{cn};
}

# $v = $obj->attr('sn');
sub attr {
  my ($self, $attr) = @_;
  croak 'Attribute required' unless defined $attr;
  return $self->{attrs}{$attr};
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
  my $aa = $self->{attrs};
  # preheat AI brain
  my $ai = Adup::Ural::LoginAI->new($aa->{sn}, $aa->{givenName}, $aa->{middleName});
  # prepare attributes
  my @attrs = (
    objectClass => [ qw/top user/ ],
    cn => $self->cn,
  );
  push @attrs, %$aa;
  push @attrs, ( 'userAccountControl' => 514 ); # disabled user
  #say Dumper \@attrs;

  # now login recreate loop
  my $mesg;
  for (1..20) {
    my @attrs_copy = @attrs;
    my $login = $ai->login;
    push @attrs_copy, ( 'sAMAccountName' => $login );
    push @attrs_copy, ( 'userPrincipalName' => "$login\@uwc.local" );

    # really try to create ldap user
    $mesg = $args{ldap}->add($self->{dn},
      attrs => \@attrs_copy,
    );

    if ($mesg->code == LDAP_SUCCESS) {
      # add user to flat group
      if ($self->{flatgroup}) {
	$mesg = $args{ldap}->modify($self->{flatgroup}{dn},
	  add => { member => [ $self->{dn} ] }
	);
	unless ($mesg->code == LDAP_SUCCESS or $mesg->code == LDAP_ALREADY_EXISTS) {
	  carp 'Merge - create user (adding to flat group) error: '.$mesg->error." for DN: $self->{dn}";
	  if ($mesg->code == LDAP_INSUFFICIENT_ACCESS) {
	    $args{log}->l(state=>91, info=>'Ошибка применения изменения-создания учетной записи (добавление в группу почтового справочника): Недостаточно прав для выполнения операции.');
	  }
	  return undef;
	}
      }
      # success
      my $r = $self->deletedb(db => $args{db});
      # save to archive
      $self->toarchive(db => $args{db}) if $r;
      return $r;

    } elsif ($mesg->code == LDAP_ALREADY_EXISTS) {
      $ai->next_round;

    } else {
      carp 'Merge - create user error: '.$mesg->error." for DN: $self->{dn}";
      if ($mesg->code == LDAP_INSUFFICIENT_ACCESS) {
	$args{log}->l(state=>91, info=>'Ошибка применения изменения-создания учетной записи пользователя: Недостаточно прав для выполнения операции.');
      }
      return undef;
    }
  } #login recreate loop
  # no tries left
  carp 'Merge - create user error (after 20 tries): '.$mesg->error." for DN: $self->{dn}";
  return undef;
}


1;
