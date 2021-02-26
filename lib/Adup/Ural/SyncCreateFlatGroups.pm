package Adup::Ural::SyncCreateFlatGroups;
use Mojo::Base -base;

use Carp;
use POSIX qw(ceil);
use Mojo::mysql;
use Net::LDAP qw(LDAP_SUCCESS LDAP_INSUFFICIENT_ACCESS LDAP_NO_SUCH_OBJECT);
use Net::LDAP::Util qw(canonical_dn escape_filter_value escape_dn_value);
use Encode qw(encode_utf8 decode);
#use Data::Dumper;
use Adup::Ural::ChangeFlatGroupCreate;
use Adup::Ural::ChangeFlatGroupModify;
use Adup::Ural::ChangeError;
use Adup::Ural::Dblog;


# changes_count/undef = Adup::Ural::SyncCreateFlatGroups::do_sync(
#   db => $db_adup,
#   ldap => $ldap,
#   log => $log,
#   job => $job,
#   user => $remote_user
# );
sub do_sync {
  my (%args) = @_;
  for (qw/db ldap log job user/) { croak 'Required parameters missing' unless defined $args{$_}};
  say "in SyncCreateFlatGroups subtask";

  #
  ### begin of flat depts main loop ###
  #
  my $res;
  my $e = eval {
    $res = $args{db}->query("SELECT cn, name \
      FROM flatdepts \
      ORDER BY id ASC");
  };
  unless (defined $e) {
    carp 'SyncCreateFlatGroups - database fatal error';
    return undef;
  }

  my $line_count = 0;
  my $lines_total = $res->rows;
  my $changes_count = 0;
  my $mod = int($lines_total / 20) || 1;
  my $fg_ldapbase = $args{job}->app->config->{flatgroups_ldap_base};
  
  while (my $next = $res->hash) {
    #say $next->{name};
    my $name_dn = escape_dn_value $next->{cn};
    my $dn = "CN=$name_dn,$fg_ldapbase";
    #say $dn;
    my $gname = substr($next->{name}, 0, 1024);

    #my $fdn = escape_filter_value $dn; #(distinguishedName=$fdn) #my $filter = "(&(objectCategory=group)(objectClass=group))";
    my $r = $args{ldap}->search(base => $dn, scope => 'base',
      filter => '(&(objectCategory=group)(objectClass=group))',
      attrs => ['name', 'grouptype', 'description']
    );
    if ($r->code && $r->code != LDAP_NO_SUCH_OBJECT) {
      $args{log}->l(state => 11, info => "Синхронизация групп почтового справочника. Произошла ошибка поиска в AD.");
      carp 'SyncCreateFlatGroups - ldap search error: '.$r->error."for DN: $dn";
      return undef;
    }

    my $count = $r->count;
    if ($count == 1) {
      # found 1. Check grouptype == 0x2 and create errorchange if not
      my $entry = $r->entry(0);
      my $dn = decode('utf-8', $entry->dn);
      my $grouptype = $entry->get_value('grouptype');
      #say "found grouptype: $grouptype";
      if (!defined $grouptype || $grouptype != 2) {
	# create errorchange
	my $c = Adup::Ural::ChangeError->new($next->{name}, $dn, $args{user});
	$c->set_error('Группа корпоративной почты. В AD найдена группа неправильного типа (смотри имя объекта).');
	$c->todb(db => $args{db});
      } else {
        my $description = decode('utf-8', $entry->get_value('description'));
        # compare with $gname and create change to modify group
	if ($description ne $gname) {
	  my $c = Adup::Ural::ChangeFlatGroupModify->new($next->{name}, $dn, $args{user});
	  $c->set_dept_names($description, $gname);
	  $c->todb(db => $args{db});
	  $changes_count++;
	}
      }

    } elsif ($count > 1) {
      # more than 1. This is VERY strange situation... just create error change
      my $entry = $r->entry(0);
      my $dn = decode('utf-8', $entry->dn);
      # create errorchange
      my $c = Adup::Ural::ChangeError->new($next->{name}, $dn, $args{user});
      $c->set_error('Группа корпоративной почты. В AD найдено более одной группы с одинаковым CN (смотри имя объекта).');
      $c->todb(db => $args{db});

    } else {
      # not found
      my $c = Adup::Ural::ChangeFlatGroupCreate->new($next->{name}, $dn, $args{user});
      $c->set_dept_name($gname);
      $c->todb(db => $args{db});
      $changes_count++;
    }

    # update progress
    $line_count++;
    if ($line_count % $mod == 0) {
      my $percent = ceil($line_count / $lines_total * 100);
      $args{job}->note(
	progress => $percent,
        # mysql minion backend bug workaround
	info => encode_utf8("$percent% Синхронизация групп почтового справочника"),
      );
    }
  }
  #
  ### end of flat depts main loop ###
  #

  $res->finish;

  $args{log}->l(info => "Синхронизация групп почтового справочника. Рассчитано $changes_count изменений групп корпоративной почты по $line_count подразделениям.");

  return $changes_count;
}


1;
