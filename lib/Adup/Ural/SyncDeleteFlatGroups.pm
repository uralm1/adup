package Adup::Ural::SyncDeleteFlatGroups;
use Mojo::Base -base;

use Carp;
use POSIX qw(ceil);
use Mojo::mysql;
use Net::LDAP qw(LDAP_SUCCESS LDAP_INSUFFICIENT_ACCESS LDAP_NO_SUCH_OBJECT LDAP_SIZELIMIT_EXCEEDED LDAP_CONTROL_PAGED);
use Net::LDAP::Util qw(canonical_dn ldap_explode_dn escape_filter_value escape_dn_value);
use Net::LDAP::Control::Paged;
use Encode qw(encode_utf8 decode_utf8);
#use Data::Dumper;
use Adup::Ural::ChangeFlatGroupDelete;
use Adup::Ural::ChangeUserFlatGroup;
use Adup::Ural::ChangeError;
use Adup::Ural::Dblog;
use Adup::Ural::DeptsHash;

# 1/undef = Adup::Ural::SyncDeleteFlatGroups::do_sync(
#   db => $db_adup,
#   ldap => $ldap,
#   log => $log,
#   job => $job,
#   user => $remote_user,
#   pos => 3
# );
sub do_sync {
  my (%args) = @_;
  for (qw/db ldap log job user pos/) { croak 'Required parameters missing' unless defined $args{$_}};
  say "in SyncDeleteFlatGroups subtask";

  # load flatdepts table from database to memory hash
  my %fg_hash; # cn is a key
  my $entries_total;
  my $e = eval {
    my $r = $args{db}->query("SELECT id, cn \
FROM flatdepts ORDER BY id ASC");
    $entries_total = $r->rows;
    while (my $next = $r->hash) {
      $fg_hash{$next->{cn}} = $next->{id};
    }
    $r->finish;
  };
  unless (defined $e) {
    carp 'SyncDeleteFlatGroups - database fatal error (query flatdepts)';
    return undef;
  }

  # extract all dept records into one hash cache
  my $depts_hash = Adup::Ural::DeptsHash->new($args{db}) or return undef;

  my $pers_ldapbase = $args{job}->app->config->{personnel_ldap_base};
  my $fg_ldapbase = $args{job}->app->config->{flatgroups_ldap_base};

  # load persons table from database to memory
  my %persons_hash; # cn (fio cut to 64) is a key
  my %dup_persons_hash; # dn is a key
  $e = eval {
    my $r = $args{db}->query("SELECT fio, dup, sovm, dept_id, flatdept_id \
FROM persons ORDER BY id ASC");
    while (my $next = $r->hash) {
      my $dup = $next->{dup};
      my $cn = substr($next->{fio}, 0, 64);
      if ($dup == 0) {
	# unique
        $persons_hash{$cn} = $next->{flatdept_id};
      } elsif ($dup == 1) {
	# dups in different departments
	# create user dn
        my $dn_built = canonical_dn($depts_hash->build_user_dn($cn, $next->{dept_id}, $pers_ldapbase));
        $dup_persons_hash{$dn_built} = $next->{flatdept_id};
	#say $dn_built;
      }
    }
    $r->finish;
  };
  unless (defined $e) {
    carp 'SyncDeleteFlatGroups - database fatal error (query persons)';
    return undef;
  }

  $depts_hash = undef; # free mem

  #
  ### begin of flat groups loop ###
  #
  my $pagedctl = Net::LDAP::Control::Paged->new(size => 100);

  my @searchargs = ( base => $fg_ldapbase, scope => 'sub',
    filter => '(&(objectCategory=group)(objectClass=group))',
    attrs => ['cn', 'grouptype', 'description', 'member'],
    control => [ $pagedctl ]
  );


  my $mod = int($entries_total / 20) || 1;
  my $entry_count = 0;
  my $delete_changes_count = 0;
  my $user_delete_flatgroup_changes_count = 0;
  my $cookie;
  my $res;
  while (1) {
    $res = $args{ldap}->search(@searchargs);

    # break loop on error
    $res->code and last;

    ## consume results
    my $count = $res->count;
    #say "Found entries: $count";
    if ($count > 0) {
      for my $entry ($res->entries) {
	my $dn = decode_utf8($entry->dn);
	my $cn = decode_utf8($entry->get_value('cn'));
	my $name = decode_utf8($entry->get_value('description')) || $cn;
	# verify group type
	my $grouptype = $entry->get_value('grouptype');
	if (!defined $grouptype || $grouptype != 2) {
	  # create errorchange
	  my $c = Adup::Ural::ChangeError->new($cn, $dn, $args{user});
	  $c->set_error('Группа корпоративной почты. В AD найдена группа неправильного типа (смотри имя объекта).');
	  $c->todb(db => $args{db});

	} elsif (!exists $fg_hash{$cn}) {
	  # if cn not exists in flatgroups hash
	  #say $dn;
	  my $c = Adup::Ural::ChangeFlatGroupDelete->new($name, $dn, $args{user});
	  $c->todb(db => $args{db});

	  $delete_changes_count++;
	} else {
	  my $fgid = $fg_hash{$cn};
	  # flat group is actual, get members
	  for my $member ($entry->get_value('member')) {
	    my $aofh = ldap_explode_dn($member);
	    unless ($aofh) {
	      carp 'SyncDeleteFlatGroups - flatgroup member dn explode failure';
	      return undef;
	    }
	    my $cnhr = shift @$aofh;
	    unless ($cnhr) {
	      carp 'SyncDeleteFlatGroups - flatgroup member cn extraction failure';
	      return undef;
	    }
	    my $member_cn = decode_utf8($cnhr->{CN});
	    my $id_from_hash = $persons_hash{$member_cn};
	    if (!defined $id_from_hash or $id_from_hash != $fgid) {
	      #say "$member_cn in $name";
	      $id_from_hash = $dup_persons_hash{canonical_dn(decode_utf8($member))};
	      if (!defined $id_from_hash or $id_from_hash != $fgid ) {
		my $c = Adup::Ural::ChangeUserFlatGroup->new($member_cn, $dn, $args{user})
		  ->member_cn($member_cn)
		  ->member_dn($member)
		  ->flatgroup_name($name);

		$c->todb(db => $args{db});

		$user_delete_flatgroup_changes_count++;
	      }
	    }
	  }

	}

	# update progress
	$entry_count++;
	if ($entry_count % $mod == 0) {
	  my $percent = ceil(($args{pos} + $entry_count / $entries_total) * $args{job}->app->percent_sync_task);
	  $args{job}->note(
	    progress => $percent,
            # mysql minion backend bug workaround
	    info => encode_utf8("$percent% Завершающая синхронизация групп почтового справочника"),
	  );
	}
      } # entries loop

    } # if ($count > 0)

    my ($resp) = $res->control(LDAP_CONTROL_PAGED) or last;
    $cookie = $resp->cookie;

    # continue if cookie is nonempty
    last if (!defined($cookie) || !length($cookie));

    # set cookie in paged control
    $pagedctl->cookie($cookie);
  }

  if (defined($cookie) && length($cookie)) {
    # abnormal exit, so let the server know we dont want any more
    $pagedctl->cookie($cookie);
    $pagedctl->size(0);
    $args{ldap}->search(@searchargs);
  }

  if ($res->code) {
    $args{log}->l(state => 11, info => "Удаление групп почтового справочника. Произошла ошибка поиска в AD.");
    carp 'SyncDeleteFlatGroups - ldap search error: '.$res->error;
    return undef;
  }

  $args{log}->l(info => "Завершающая синхронизация групп почтового справочника. Создано $user_delete_flatgroup_changes_count изменений по удалению пользователей из групп почтового справочника, $delete_changes_count изменений удаления групп, по $entry_count группам почтового справочника.");

  return 1;
}


1;
