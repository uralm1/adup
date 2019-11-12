package Adup::Controller::Setattrphoto;
use Mojo::Base 'Mojolicious::Controller';

use Carp;
use Net::LDAP qw(LDAP_SUCCESS LDAP_INSUFFICIENT_ACCESS LDAP_NO_SUCH_OBJECT LDAP_NO_SUCH_ATTRIBUTE LDAP_SIZELIMIT_EXCEEDED);
use Net::LDAP::Util qw(canonical_dn escape_filter_value);
use Encode qw(decode);
use MIME::Base64 qw(decode_base64url decode_base64);
#use Data::Dumper;


sub photo {
  my $self = shift;
  return undef unless $self->authorize({admin=>1, photo=>1});

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
    my $filter = "(&(objectCategory=person)(|(objectClass=user)(objectClass=contact))(cn=$esc_search))";
    my $res = $ldap->search(base => $self->config->{personnel_ldap_base}, scope => 'sub',
      filter => $filter,
      attrs => ['displayName', 'title', 'department', 
	'userAccountControl'],
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
      };
      last if ++$i >= 5; 
    }

    $ldap->unbind;

  } else {
    $search = '';
  }

  $self->render(template => 'setattr/photo',
    res_tab => $res_tab,
    search => $search,
  );
}


sub view {
  my $self = shift;
  return undef unless $self->authorize({admin=>1, photo=>1});

  my $v = $self->validation;
  return $self->redirect_to('photo') unless ($v->has_data);

  my $dn = $v->required('r')->param;
  if ($v->is_valid) {
    $dn = decode_base64url($dn, 1);
    #say "DN: $dn";

    # connect to AD
    my $ldap = Net::LDAP->new($self->config->{ldap_servers}, port => 389, timeout => 10, version => 3);
    if ($ldap) {
      my $mesg = $ldap->bind($self->config->{ldap_user}, password => $self->config->{ldap_pass});
      unless ($mesg->code) {

	my $res = $ldap->search(base => $dn, scope => 'base',
	  filter => '(&(objectCategory=person)(|(objectClass=user)(objectClass=contact)))',
	  attrs => ['thumbnailPhoto']
	);
	if ($res->code == LDAP_SUCCESS && $res->count == 1) {
	  if (my $jpeg = $res->entry(0)->get_value('thumbnailPhoto')) {
	    $ldap->unbind;
	    return $self->render(data => $jpeg, format => 'jpeg');
	  } else {
	    $ldap->unbind;
            $self->res->headers->cache_control('no-cache');
	    return $self->reply->static('img/no-photo-icon.png');
	  }
	}

	$ldap->unbind;
	carp "LDAP search error ".$res->error;
      } else {
	carp "LDAP bind error ".$mesg->error;
      }
    } else {
      carp "LDAP object creation error $@";
    }
    $self->res->headers->cache_control('no-cache');
    return $self->reply->static('img/error-icon.png');

  } # param valid
  return $self->render(text => 'Ошибка.', status => 500);
}


sub photopost {
  my $self = shift;
  return undef unless $self->authorize({admin=>1, photo=>1});

  # request limit
  if ($self->req->is_limit_exceeded) {
    $self->flash(oper => 'Ошибка! Слишком большой файл.');
    $self->redirect_to('photo');
    return undef;
  }

  my $v = $self->validation;
  return $self->redirect_to('photo') unless ($v->has_data);

  my $search = $v->optional('s')->param || '';
  my $del = $v->optional('del')->param;
  my $cam = $v->optional('cam')->param;
 
  my $seldn = $v->required('ug')->param;
  if ($v->is_valid) { # check ug
    $seldn = decode_base64url($seldn, 1);
    #say "DN: $seldn";

    # open camera
    return $self->_open_cam($seldn, $search) if $cam;

    $v->optional('photo')->upload;

    unless ($v->has_error) {
      my $upl = $v->size(0, 16384)->param;
      if ($v->is_valid) {
	if ($upl->size) {
	  unless ($del) {
	    #say "SIZE VALID - FILE";
	    $self->_set_photo($seldn, $upl->slurp);

	  } else {
            $self->flash(oper => 'Ошибка. Выберите что-то одно - или файл, или удаление.');
	  }

	} else {
	  if ($del) {
	    #say "SIZE 0 - REMOVE";
	    $self->_del_photo($seldn);

	  } else {
            $self->flash(oper => 'Изменения отсутствуют.');
	  }

	}
      } else {
        $self->flash(oper => 'Ошибка. Файл не загружен, размер файла больше 16 кб.');
      }

    } else {
      $self->flash(oper => 'Ошибка. Файл не загружен.');
    }
  } else {
    $self->flash(oper => 'Ошибка. Пользователь не выбран.');
  }

  $self->redirect_to($self->url_for('photo')->query(s => $search));
}


# internal
# $self->_set_photo($seldn, $jpeg);
sub _set_photo {
  my ($self, $seldn, $jpeg) = @_;

  # connect to AD
  my $ldap = Net::LDAP->new($self->config->{ldap_servers}, port => 389, timeout => 10, version => 3);
  if ($ldap) {
    my $mesg = $ldap->bind($self->config->{ldap_user}, password => $self->config->{ldap_pass});
    unless ($mesg->code) {

      $mesg = $ldap->modify($seldn,
	replace => {
	  thumbnailPhoto => [ $jpeg ],
	}
      );
      if ($mesg->code) {
	carp "LDAP modify error ".$mesg->error;
	$self->flash(oper => 'Ошибка изменения глобального каталога.');
      } else {
	$self->flash(oper => 'Записано успешно.');
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
}


# $self->_del_photo($seldn);
sub _del_photo {
  my ($self, $seldn) = @_;

  # connect to AD
  my $ldap = Net::LDAP->new($self->config->{ldap_servers}, port => 389, timeout => 10, version => 3);
  if ($ldap) {
    my $mesg = $ldap->bind($self->config->{ldap_user}, password => $self->config->{ldap_pass});
    unless ($mesg->code) {

      $mesg = $ldap->modify($seldn,
	replace => {
	  thumbnailPhoto => [],
	}
      );
      if ($mesg->code) {
	carp "LDAP modify error ".$mesg->error;
	$self->flash(oper => 'Ошибка изменения глобального каталога.');
      } else {
	$self->flash(oper => 'Фотография удалена.');
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
}


# return $self->_open_cam($seldn, $search);
sub _open_cam {
  my ($self, $seldn, $search) = @_;

  # connect to AD
  my $ldap = Net::LDAP->new($self->config->{ldap_servers}, port => 389, timeout => 10, version => 3);
  if ($ldap) {
    my $mesg = $ldap->bind($self->config->{ldap_user}, password => $self->config->{ldap_pass});
    unless ($mesg->code) {

      my $res = $ldap->search(base => $seldn, scope => 'base',
        filter => '(&(objectCategory=person)(|(objectClass=user)(objectClass=contact)))',
        attrs => ['displayName']
      );
      if ($res->code) {
	carp "LDAP search error ".$res->error;
        $self->flash(oper => 'Ошибка чтения аттрибутов глобального каталога.');

      } else {
	if ($res->count > 0) {
	  my $entry = $res->entry(0);
	  return $self->render(template => 'setattr/photocam',
	    seldn => $seldn,
	    name => decode('utf-8', $entry->get_value('displayName')) || 'Нет данных',
	    back_url => $self->url_for('photo')->query(s => $search),
	  );

	} else {
	  carp "LDAP search error (2)".$res->error;
          $self->flash(oper => 'Ошибка поиска в глобальном каталоге.');
	}
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
  return $self->redirect_to($self->url_for('photo')->query(s => $search));
}


sub campost {
  my $self = shift;
  return undef unless $self->authorize({admin=>1, photo=>1});

  my $v = $self->validation;
  return $self->redirect_to('photo') unless ($v->has_data);

  my $backurl = $v->optional('backurl')->param || 'photo';

  my $seldn = $v->required('seldn')->param;
  if ($v->is_valid) { # check seldn
    $seldn = decode_base64url($seldn, 1);
    #say "DN: $seldn";

    my $pic = $v->required('pic')->like(qr/^data:image\/jpeg;base64/)->param;
    unless ($v->has_error) {
      $pic =~ s/^data:image\/jpeg;base64,//;
      $pic =~ s/ /+/g;
      my $jpeg = decode_base64($pic);
      if ($jpeg) {
	$self->_set_photo($seldn, $jpeg);

      } else {
        $self->flash(oper => 'Ошибка. Проблема с данными (2).');
      }

    } else {
      $self->flash(oper => 'Ошибка. Проблема с данными (1).');
    }

  } else {
    $self->flash(oper => 'Ошибка. Пользователь не выбран.');
  }

  $self->redirect_to($backurl);
}


1;
