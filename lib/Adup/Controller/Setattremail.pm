package Adup::Controller::Setattremail;
use Mojo::Base 'Mojolicious::Controller';

use Carp;
use Net::LDAP qw(LDAP_SUCCESS LDAP_INSUFFICIENT_ACCESS LDAP_NO_SUCH_OBJECT LDAP_SIZELIMIT_EXCEEDED);
use Net::LDAP::Util qw(canonical_dn escape_filter_value);
use Encode qw(decode);
use MIME::Base64 qw(decode_base64url);
#use Data::Dumper;

sub email {
  my $self = shift;
  return undef unless $self->authorize({admin=>1});

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
    my $filter = "(&(objectCategory=person)(|(objectClass=user)(objectClass=contact))(|(cn=$esc_search)(sAMAccountName=$esc_search)))";
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
      my $uac = $entry->get_value('userAccountControl') || 0x200;
      push @$res_tab, { dn => $entry->dn, # we assume dn to be octets string
	cn => decode('utf-8', $entry->get_value('displayName')),
	disabled => ($uac & 2) == 2,
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

  $self->render(template => 'setattr/email',
    res_tab => $res_tab,
    search => $search,
  );
}


sub emailpost {
  my $self = shift;
  return undef unless $self->authorize({admin=>1});

  my $v = $self->validation;
  return $self->redirect_to('email') unless ($v->has_data);

  my $search = $v->optional('s')->param || '';

  my $seldn = $v->required('ug')->param;
  if ($v->is_valid) { # check ug
    $seldn = decode_base64url($seldn, 1);
    #say "DN: $seldn";

    # max attribute length is 64
    my $email = $v->optional('email', 'not_empty', 'trim')->size(1, 64)->param;

    unless ($v->has_error) {
      #say "email: $email";
      # connect to AD
      my $ldap = Net::LDAP->new($self->config->{ldap_servers}, port => 389, timeout => 10, version => 3);
      if ($ldap) {
        my $mesg = $ldap->bind($self->config->{ldap_user}, password => $self->config->{ldap_pass});
        unless ($mesg->code) {

          my $res = $ldap->search(base => $seldn, scope => 'base',
            filter => '(&(objectCategory=person)(|(objectClass=user)(objectClass=contact)))',
            attrs => ['mail']
          );
          if ($res->code) {
            carp "LDAP search error ".$res->error;
            $self->flash(oper => 'Ошибка загрузки аттрибутов глобального каталога.');
	    $ldap->unbind;
            return $self->redirect_to($self->url_for('email')->query(s => $search));
          }
	  my $entry = $res->entry(0);

	  # mail
	  my $oldemail = $entry->get_value('mail');
	  my $do_update;
          if (defined($email) && $email ne '') {
	    $entry->replace(mail => $email);
	    $do_update = 1;
	  } else {
	    if ($oldemail) {
	      $entry->delete(mail => []);
	      $do_update = 1;
	    }
	  }
	  if ($do_update) {
	    #say Dumper $entry;
	    $mesg = $entry->update($ldap);
	    if ($mesg->code) {
	      carp "LDAP modify error (mail) ".$mesg->error;
	      $self->flash(oper => 'Ошибка изменения глобального каталога.');
	    } else {
	      $self->flash(oper => 'Записано успешно.');
	    }
	  } else {
	    $self->flash(oper => 'Изменения отсутствуют.');
	  }

	  $ldap->unbind;
	} else {
          carp "LDAP bind error ".$mesg->error;
          $self->flash(oper => 'Ошибка авторизации при подключении к глобальному каталогу.');
        }
      } else {
        carp "LDAP creation error $@";
        $self->flash(oper => 'Ошибка подключения к глобальному каталогу.');
      }
    } else {
      $self->flash(oper => 'Ошибка. Неверный адрес электронной почты.');
    }
  } else {
    $self->flash(oper => 'Ошибка. Пользователь не выбран.');
  }

  $self->redirect_to($self->url_for('email')->query(s => $search));
}


1;
