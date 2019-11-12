package Adup::Ural::ChangeUserMove;
use Mojo::Base 'Adup::Ural::Change';

use Mojo::Util qw(xml_escape);
use Carp;
use Net::LDAP qw(LDAP_SUCCESS LDAP_INSUFFICIENT_ACCESS LDAP_ALREADY_EXISTS);
use Net::LDAP::Util qw(ldap_explode_dn unescape_dn_value escape_dn_value);
use Adup::Ural::Dblog;

#use Data::Dumper;

# my $obj = Adup::Ural::ChangeUserMove->new($name, $dn, 'author');
sub new {
  my ($class, $name, $dn, $author) = @_;
  my $self = $class->SUPER::new($name, $dn, $author);

  $self->{cn} = undef;
  $self->{rdn} = undef;
  $self->{sup} = undef;

  return $self;
}

#
# getters
#
sub type_human {
  return 'Перемещение учётной записи';
}

sub type_robotic {
  return 5;
}

sub info_human {
  my $self = shift;

  my $r = '<b>DN:</b> '.xml_escape(unescape_dn_value($self->{dn})).'<br>';
  $r .= '<b>Перемещение учётной записи пользователя</b><br>';
  $r .= '<span class="info-attr">ФИО:</span> '.xml_escape($self->{cn}).'<br>';
  $r .= '<b>Новый DN:</b> '.xml_escape(unescape_dn_value($self->{sup}));
  $r .= '<div class="info-warn"><b>Зависимости!</b> Примените все изменения подразделений перед утверждением изменения.</div>';
  $r .= '<div class="info-warn"><b>Зависимости!</b> Примените все изменения аттрибутов перед утверждением изменения.</div>';

  return $r;
}


# $new_dn = $obj->new_dn;
# $obj->new_dn($new_dn);
sub new_dn {
  my ($self, $new_dn) = @_;
  return join(',', $self->{rdn}, $self->{sup}) unless $new_dn;

  my $aofh = ldap_explode_dn($new_dn);
  croak 'DN is invalid' unless $aofh;
  #say Dumper $aofh;
  my $cnhr = shift @$aofh;
  croak 'CN extraction failure' unless $cnhr;
  $self->{cn} = $cnhr->{CN};
  $self->{rdn} = 'CN='.escape_dn_value($cnhr->{CN});
  my @a;
  for (@$aofh) {
    my ($k, $v) = each %$_;
    push @a, "$k=".escape_dn_value($v);
  }
  $self->{sup} = join ',', @a;
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
  # really move ldap user
  my $mesg = $args{ldap}->moddn($self->{dn},
    newrdn => $self->{rdn},
    deleteoldrdn => 1,
    newsuperior => $self->{sup},
  );

  if ($mesg->code == LDAP_SUCCESS) {
    my $r = $self->deletedb(db => $args{db});
    # save to archive
    $self->toarchive(db => $args{db}) if $r;
    return $r;
  }

  carp 'Merge - move user error: '.$mesg->error." for DN: $self->{dn}" if $mesg->code;
  if ($mesg->code == LDAP_INSUFFICIENT_ACCESS) {
    $args{log}->l(state=>91, info=>'Ошибка применения изменения-перемещения учетной записи пользователя: Недостаточно прав для выполнения операции.');
  }
  return undef;
}


1;
