package Adup::Controller::Setattrroom;
use Mojo::Base 'Mojolicious::Controller';

use Carp;
use Net::LDAP qw(LDAP_SUCCESS LDAP_INSUFFICIENT_ACCESS LDAP_NO_SUCH_OBJECT LDAP_NO_SUCH_ATTRIBUTE LDAP_SIZELIMIT_EXCEEDED);
use Net::LDAP::Util qw(canonical_dn escape_filter_value);
use Encode qw(decode);
use MIME::Base64 qw(decode_base64url);
use Data::Dumper;

use Adup::Ural::LdapListsUtil qw(ldapattrs2list ldaplist2attrs_entry);


sub room {
  my $self = shift;
  return undef unless $self->authorize({admin=>1, room=>1, phone=>1});

  my $search = $self->param('s') // '';
  my $res_tab;

  if ($search ne '') {
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
	'userAccountControl', 'physicalDeliveryOfficeName',
	'telephoneNumber', 'otherTelephone',
	'pager', 'otherPager',
	'facsimileTelephoneNumber', 'otherFacsimileTelephoneNumber',
      ],
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
      # build list of phones
      my @phones = ldapattrs2list($entry, 'telephoneNumber', 'otherTelephone');

      push @$res_tab, { dn => $entry->dn, # we assume dn to be octets string
	cn => decode('utf-8', $entry->get_value('displayName')),
	disabled => ($uac & 2) == 2,
	title => decode('utf-8', $entry->get_value('title')),
	department => decode('utf-8', $entry->get_value('department')),
	room => decode('utf-8', $entry->get_value('physicalDeliveryOfficeName')),
	intphones => join(', ', grep(/^\d{4}$/, @phones)),
	extphones => join(', ', grep(!/^\d{4}$/, @phones)),
	pagers => join(', ', ldapattrs2list($entry, 'pager', 'otherPager')),
	faxes => join(', ', ldapattrs2list($entry, 'facsimileTelephoneNumber', 'otherFacsimileTelephoneNumber')),
      };
      last if ++$i >= 5;
    }

    $ldap->unbind;
  }

  $self->render(template => 'setattr/room',
    res_tab => $res_tab,
    search => $search,
  );
}


sub roompost {
  my $self = shift;
  return undef unless $self->authorize({admin=>1, room=>1, phone=>1});

  my $v = $self->validation;
  return $self->redirect_to('room') unless ($v->has_data);

  my $search = $v->optional('s')->param || '';

  my $seldn = $v->required('ug')->param;
  if ($v->is_valid) { # check ug
    $seldn = decode_base64url($seldn, 1);
    #say "DN: $seldn";

    my $room = $v->optional('room', 'not_empty', 'trim')->like(qr/^.{1,64}$/)->param;
    my $phonevn1 = $v->optional('phonevn1', 'not_empty', 'trim')->like(qr/^\d{4}$/)->param;
    my $phonevn2 = $v->optional('phonevn2', 'not_empty', 'trim')->like(qr/^\d{4}$/)->param;
    my $phonevn3 = $v->optional('phonevn3', 'not_empty', 'trim')->like(qr/^\d{4}$/)->param;
    my $phonegor1 = $v->optional('phonegor1', 'not_empty', 'trim')->like(qr/^\+?[0-9()\- ]{7,22}$/)->param;
    my $phonegor2 = $v->optional('phonegor2', 'not_empty', 'trim')->like(qr/^\+?[0-9()\- ]{7,22}$/)->param;
    my $phonegor3 = $v->optional('phonegor3', 'not_empty', 'trim')->like(qr/^\+?[0-9()\- ]{7,22}$/)->param;
    my $mkan1 = $v->optional('mkan1', 'not_empty', 'trim')->like(qr/^\+?[0-9()\- ]{7,22}$/)->param;
    my $mkan2 = $v->optional('mkan2', 'not_empty', 'trim')->like(qr/^\+?[0-9()\- ]{7,22}$/)->param;
    my $fax1 = $v->optional('fax1', 'not_empty', 'trim')->like(qr/^\+?[0-9()\- ]{7,22}$/)->param;
    my $fax2 = $v->optional('fax2', 'not_empty', 'trim')->like(qr/^\+?[0-9()\- ]{7,22}$/)->param;

    unless ($v->has_error) {
      #say "room: $room, phonevn1: $phonevn1, fax1: $fax1";
      # connect to AD
      my $ldap = Net::LDAP->new($self->config->{ldap_servers}, port => 389, timeout => 10, version => 3);
      if ($ldap) {
        my $mesg = $ldap->bind($self->config->{ldap_user}, password => $self->config->{ldap_pass});
        unless ($mesg->code) {

          my $res = $ldap->search(base => $seldn, scope => 'base',
            filter => '(&(objectCategory=person)(|(objectClass=user)(objectClass=contact)))',
            attrs => ['physicalDeliveryOfficeName',
	      'telephoneNumber', 'otherTelephone',
	      'pager', 'otherPager',
	      'facsimileTelephoneNumber', 'otherFacsimileTelephoneNumber'
	    ]
          );
          if ($res->code) {
            carp "LDAP search error ".$res->error;
            $self->flash(oper => 'Ошибка загрузки аттрибутов глобального каталога.');
	    $ldap->unbind;
            return $self->redirect_to($self->url_for('room')->query(s => $search));
          }
	  my $entry = $res->entry(0);
	  my $update_success;
	  my $update_error;

	  # physicalDeliveryOfficeName
	  my $entry_room = $entry->clone;
	  my $oldroom = $entry_room->get_value('physicalDeliveryOfficeName');
	  my $do_update;
	  if (defined $room) {
	    $entry_room->replace(physicalDeliveryOfficeName => $room);
	    $do_update = 1;
	  } else {
	    if ($oldroom) {
	      $entry_room->delete(physicalDeliveryOfficeName => []);
	      $do_update = 1;
	    }
	  }
	  if ($do_update) {
	    #say Dumper $entry_room;
	    $mesg = $entry_room->update($ldap);
	    if ($mesg->code) {
	      carp "LDAP modify error (room) ".$mesg->error;
	      $update_error = 1;
	    } else {
	      $update_success = 1;
	    }
	  }

	  # telephoneNumber, otherTelephone
	  my $entry_ph = $entry->clone;
	  if (ldaplist2attrs_entry($entry_ph, [ grep $_, $phonevn1, $phonevn2, $phonevn3, $phonegor1, $phonegor2, $phonegor3 ], 'telephoneNumber', 'otherTelephone')) {
	    #say Dumper $entry_ph;
	    $mesg = $entry_ph->update($ldap);
	    if ($mesg->code) {
	      carp "LDAP modify error (phones) ".$mesg->error;
	      $update_error = 1;
	    } else {
	      $update_success = 1;
	    }
          }

	  # pager, otherPager
	  my $entry_mkan = $entry->clone;
	  if (ldaplist2attrs_entry($entry_mkan, [ grep $_, $mkan1, $mkan2 ], 'pager', 'otherPager')) {
	    #say Dumper $entry_mkan;
	    $mesg = $entry_mkan->update($ldap);
	    if ($mesg->code) {
	      carp "LDAP modify error (mkan) ".$mesg->error;
	      $update_error = 1;
	    } else {
	      $update_success = 1;
	    }
          }

	  # facsimileTelephoneNumber, otherFacsimileTelephoneNumber
	  my $entry_fax = $entry->clone;
	  if (ldaplist2attrs_entry($entry_fax, [ grep $_, $fax1, $fax2 ], 'facsimileTelephoneNumber', 'otherFacsimileTelephoneNumber')) {
	    #say Dumper $entry_fax;
	    $mesg = $entry_fax->update($ldap);
	    if ($mesg->code) {
	      carp "LDAP modify error (fax) ".$mesg->error;
	      $update_error = 1;
	    } else {
	      $update_success = 1;
	    }
          }

	  if ($update_error) {
	    $self->flash(oper => 'Ошибка изменения глобального каталога.');
	  } elsif ($update_success) {
	    $self->flash(oper => 'Записано успешно.');
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
      $self->flash(oper => 'Ошибка. Неверно указаны номер комнаты или телефоны (Внутренние NNNN, городские NNNNNNN).');
    }
  } else {
    $self->flash(oper => 'Ошибка. Пользователь не выбран.');
  }

  $self->redirect_to($self->url_for('room')->query(s => $search));
}


1;
