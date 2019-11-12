package Adup::Ural::ChangeAttr;
use Mojo::Base 'Adup::Ural::Change';

use Mojo::Util qw(xml_escape);
use Carp;
use Net::LDAP qw(LDAP_SUCCESS LDAP_INSUFFICIENT_ACCESS LDAP_ALREADY_EXISTS);
use Net::LDAP::Util qw(unescape_dn_value);

use Adup::Ural::Dblog;
use Adup::Ural::AttrTranslate qw(translate);

# my $obj = Adup::Ural::ChangeAttr->new($name, $dn, 'author');
sub new {
  my ($class, $name, $dn, $author) = @_;
  my $self = $class->SUPER::new($name, $dn, $author);

  $self->{attrs} = {};
  $self->{flatgroup} = undef; #don't add user to flatgroup

  return $self;
}

#
# getters
#
sub type_human {
  return 'Изменение аттрибутов';
}

sub type_robotic {
  return 1;
}

sub info_human {
  my $self = shift;
  my $r = '<b>DN:</b> '.xml_escape(unescape_dn_value($self->{dn})).'<br>';
  my $title_pre;
  for (sort keys %{$self->{attrs}}) {
    unless ($title_pre) {
      $r .= '<b>Изменяемые аттрибуты:</b><br>';
      $title_pre = 1;
    }
    $r .= '<span class="info-attr">'.translate($_).':</span> ';
    if (my $old = $self->attr_old($_)) {
      $r .= 'значение &laquo;'.xml_escape($old).'&raquo; заменяется на &laquo;'.xml_escape($self->attr_new($_)).'&raquo;;';
    } else {
      $r .= 'устанавливается &laquo;'.xml_escape($self->attr_new($_)).'&raquo;;';
    }
    $r .= '<br>';
  }
  if ($self->{flatgroup}) {
    $r .= '<b>Пользователь добавляется в группу почтового справочника:</b> &laquo;'.xml_escape($self->{flatgroup}{name}).'&raquo;.';
    $r .= '<div class="info-warn"><b>Зависимости!</b> Примените все изменения подразделений перед утверждением изменения.</div>';
  }
  return $r;
}


# $obj->set_attr('sn', $new_val);
# $obj->set_attr('sn', $old_val, $new_val);
sub set_attr {
  my ($self, $attr, $old, $new) = @_;
  croak 'Attribute/value required' unless defined $attr and defined $old;
  if (defined $new) {
    $self->{attrs}{$attr} = { old => $old, new => $new };
  } else {
    my $t = $self->{attrs}{$attr};
    if (defined $t) {
      $t->{old} = $t->{new};
      $t->{new} = $old;
    } else {
      $self->{attrs}{$attr} = { new => $old };
    }
  }
}

# $obj->set_flatgroup($flatgroup_dn, $flatdept_name);
sub set_flatgroup {
  my ($self, $fgdn, $fgname) = @_;
  croak 'Flatgroup dn and name required' unless defined $fgdn and defined $fgname;
  $self->{flatgroup} = { dn => $fgdn, name => $fgname };
}


# $v = $obj->attr_new('sn');
sub attr_new {
  my ($self, $attr) = @_;
  croak 'Attribute required' unless defined $attr;
  return $self->{attrs}{$attr}{new};
}

# $v = $obj->attr_old('sn');
sub attr_old {
  my ($self, $attr) = @_;
  croak 'Attribute required' unless defined $attr;
  return $self->{attrs}{$attr}{old};
}

# $b = $obj->empty;
sub empty {
  my $self = shift;
  return (scalar keys(%{$self->{attrs}}) or $self->{flatgroup}) ? 0 : 1;
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
  # modify attributes
  my $attrs = $self->{attrs};
  my $repl = {};
  for (keys %$attrs) {
    $repl->{$_} = $attrs->{$_}{new} if (exists $attrs->{$_}{new});
  }
  if (scalar keys %$repl) {
    # really modify ldap user
    my $mesg = $args{ldap}->modify($self->{dn},
      replace => $repl,
    );
    if ($mesg->code) {
      carp 'Merge - modify attributes error: '.$mesg->error." for DN: $self->{dn}";
      if ($mesg->code == LDAP_INSUFFICIENT_ACCESS) {
	$args{log}->l(state=>91, info=>'Ошибка применения изменения-атрибутов учетной записи: Недостаточно прав для выполнения операции.');
      }
      return undef;
    }
  }

  # add user to flat group
  if ($self->{flatgroup}) {
    my $mesg = $args{ldap}->modify($self->{flatgroup}{dn},
      add => { member => [ $self->{dn} ] }
    );
    unless ($mesg->code == LDAP_SUCCESS or $mesg->code == LDAP_ALREADY_EXISTS) {
      carp 'Merge - modify user (adding to flat group) error: '.$mesg->error." for DN: $self->{dn}";
      if ($mesg->code == LDAP_INSUFFICIENT_ACCESS) {
	$args{log}->l(state=>91, info=>'Ошибка применения изменения-атрибутов учетной записи (добавление в группу почтового справочника): Недостаточно прав для выполнения операции.');
      }
      return undef;
    }
  }

  # success
  my $r = $self->deletedb(db => $args{db});
  # save to archive
  $self->toarchive(db => $args{db}) if $r;
  return $r;
}


1;
