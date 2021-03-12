package Adup::Controller::Manual;
use Mojo::Base 'Mojolicious::Controller';

use Carp;
use Net::LDAP qw(LDAP_SUCCESS LDAP_INSUFFICIENT_ACCESS LDAP_NO_SUCH_OBJECT LDAP_SIZELIMIT_EXCEEDED);
use Net::LDAP::Util qw(canonical_dn escape_filter_value);
use Encode qw(decode);
use MIME::Base64 qw(decode_base64url);
#use Data::Dumper;

sub manual {
  my $self = shift;
  return undef unless $self->authorize($self->allow_all_roles);

  my $search = $self->param('s');
  my $res_tab;

  if ($search) {
    # perform search
    my $ldap = Net::LDAP->new($self->config->{ldap_servers}, port => 389, timeout => 10, version => 3);
    unless ($ldap) {
      carp "LDAP creation error $@";
      return $self->render(text => "Ошибка подключения к глобальному каталогу.");
    }

    my $mesg = $ldap->bind($self->config->{ldap_user}, password => $self->config->{ldap_pass});
    if ($mesg->code) {
      carp "LDAP bind error ".$mesg->error;
      return $self->render(text => "Произошла ошибка авторизации при подключении к глобальному каталогу.");
    }

    #search ldap
    my $esc_search = escape_filter_value($search).'*'; #security filtering
    #my $filter = "(&(objectCategory=person)(objectClass=user)(!(userAccountControl:1.2.840.113556.1.4.803:=2))(|(cn=$esc_search)(sAMAccountName=$esc_search)))";
    my $filter = "(&(objectCategory=person)(objectClass=user)(|(cn=$esc_search)(sAMAccountName=$esc_search)))";
    my $res = $ldap->search(base => $self->config->{personnel_ldap_base}, scope => 'sub',
      filter => $filter,
      attrs => ['displayName', 'title', 'department',
        'sAMAccountName', 'userAccountControl', 'mail'],
      sizelimit => 5
    );
    if ($res->code && $res->code != LDAP_SIZELIMIT_EXCEEDED && $res->code != LDAP_NO_SUCH_OBJECT) {
      carp "LDAP search error ".$res->error;
      return $self->render(text => "Произошла ошибка поиска в глобальном каталоге.");
    }

    #my $count = $res->count; say "found: $count";
    my $i = 0;
    $res_tab = [];
    foreach my $entry ($res->entries) {
      #$entry->dump;
      push @$res_tab, { dn => $entry->dn, # we assume dn to be octets string
	cn => decode('utf-8', $entry->get_value('displayName')),
	disabled => ($entry->get_value('userAccountControl') & 2) == 2,
	title => decode('utf-8', $entry->get_value('title')),
	department => decode('utf-8', $entry->get_value('department')),
	login => lc decode('utf-8', $entry->get_value('sAMAccountName')),
	email => decode('utf-8', $entry->get_value('mail')),
      };
      last if ++$i >= 5;
    }

    $ldap->unbind;

  } else {
    $search = '';
  }

  $self->render(
    res_tab => $res_tab,
    search => $search,
  );
}


sub manpost {
  my $self = shift;
  return undef unless $self->authorize($self->allow_all_roles);

  my $v = $self->validation;
  return $self->redirect_to('manual') unless ($v->has_data);

  my $search = $v->optional('s')->param || '';

  my $seldn = $v->required('ug')->param;
  if ($v->is_valid) { # check ug
    $seldn = decode_base64url($seldn, 1);
    #say "DN: $seldn";

    my $fio = $v->required('fio', 'trim')->param;
    my $login = $v->required('login', 'trim')->param;
    my $email = $v->optional('email', 'trim')->param;

    unless ($v->has_error) {
      #say "fio: $fio, login: $login, email: $email";
      return $self->render(template => 'manual/new_user',
        u_fio => $fio,
        u_login => $login,
        u_email => $email
      );

    } else {
      $self->flash(oper => 'Проблема с данными.');
    }
  } else {
    $self->flash(oper => 'Ошибка. Пользователь не выбран.');
  }

  $self->redirect_to($self->url_for('manual')->query(s => $search));
}


1;
