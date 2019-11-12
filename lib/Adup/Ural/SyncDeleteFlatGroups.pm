package Adup::Ural::SyncDeleteFlatGroups;
use Mojo::Base -base;

use Carp;
use POSIX qw(ceil);
use Mojo::mysql;
use Net::LDAP qw(LDAP_SUCCESS LDAP_INSUFFICIENT_ACCESS LDAP_NO_SUCH_OBJECT LDAP_SIZELIMIT_EXCEEDED);
use Net::LDAP::Util qw(canonical_dn ldap_explode_dn escape_filter_value escape_dn_value);
use Encode qw(decode);
#use Data::Dumper;
use Adup::Ural::ChangeFlatGroupDelete;
use Adup::Ural::ChangeUserFlatGroup;
use Adup::Ural::ChangeError;
use Adup::Ural::Dblog;

# 1/undef = Adup::Ural::SyncDeleteFlatGroups::do_sync(
#   db => $db_adup,
#   ldap => $ldap,
#   log => $log,
#   job => $job,
#   user => $remote_user
# );
sub do_sync {
  my (%args) = @_;
  for (qw/db ldap log job user/) { croak 'Required parameters missing' unless defined $args{$_}};
  say "in SyncDeleteFlatGroups subtask";

  # load flatdepts table from database to memory hash
  my %fg_hash; # cn is a key
  my $e = eval {
    my $r = $args{db}->query("SELECT id, cn \
      FROM flatdepts \
      ORDER BY id ASC");
    while (my $next = $r->hash) {
      $fg_hash{$next->{cn}} = $next->{id};
    }
    $r->finish;
  };
  unless (defined $e) {
    carp 'SyncDeleteFlatGroups - database fatal error (query flatdepts)';
    return undef;
  }

  # load persons table from database to memory
  my %pers_hash; #fio cut to 64 is a key
  $e = eval {
    my $r = $args{db}->query("SELECT fio, dup, flatdept_id \
      FROM persons \
      ORDER BY id ASC");
    while (my $next = $r->hash) {
      $pers_hash{substr($next->{fio}, 0, 64)} = $next->{flatdept_id} if $next->{dup} == 0;
      # warning duplicates... have to fix to later
    }
    $r->finish;
  };
  unless (defined $e) {
    carp 'SyncDeleteFlatGroups - database fatal error (query persons)';
    return undef;
  }


  my $fgldapbase = $args{job}->app->config->{flatgroups_ldap_base};

  #
  ### begin of flat groups loop ###
  #
  my $res = $args{ldap}->search(base => $fgldapbase, scope => 'sub',
    filter => '(&(objectCategory=group)(objectClass=group))', 
    attrs => ['cn', 'grouptype', 'description', 'member']
  );
  if ($res->code && $res->code != LDAP_NO_SUCH_OBJECT) {
    $args{log}->l(state => 11, info => "Удаление групп почтового справочника. Произошла ошибка поиска в AD.");
    carp 'SyncDeleteFlatGroups - ldap search error: '.$res->error;
    return undef;
  }

  my $entries_total = $res->count;
  #say "Found entries: $entries_total";
  my $mod = int($entries_total / 20) || 1;
  my $entry_count = 0;
  my $delete_changes_count = 0;
  my $user_delete_flatgroup_changes_count = 0;

  while (my $entry = $res->shift_entry) {
    ## consume results
    my $dn = decode('utf-8', $entry->dn);
    my $cn = decode('utf-8', $entry->get_value('cn'));
    my $name = decode('utf-8', $entry->get_value('description')) || $cn;
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
	my $member_cn = decode('utf-8', $cnhr->{CN});
        my $id_from_hash = $pers_hash{$member_cn};
        if (!defined $id_from_hash or $fg_hash{$cn} != $id_from_hash) {
	  #say "$member_cn in $name";
	  my $c = Adup::Ural::ChangeUserFlatGroup->new($member_cn, $dn, $args{user})
	    ->member_cn($member_cn)
	    ->member_dn($member)
	    ->flatgroup_name($name);
  
	  $c->todb(db => $args{db});

	  $user_delete_flatgroup_changes_count++;
	}
      }

    }

    # update progress
    $entry_count ++;
    if ($entry_count % $mod == 0) {
      my $percent = ceil($entry_count / $entries_total * 100);
      $args{job}->note(
	progress => $percent,
	info => "$percent% Завершающая синхронизация групп почтового справочника",
      );
    }

  } # entries loop

  $args{log}->l(info => "Завершающая синхронизация групп почтового справочника. Создано $user_delete_flatgroup_changes_count изменений по удалению пользователей из групп почтового справочника, $delete_changes_count изменений удаления групп, по $entry_count группам почтового справочника.");

  return 1;
}


1;
