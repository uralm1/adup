package Adup::Ural::SyncAttributesCreateMoveUsers;
use Mojo::Base -base;

use Carp;
use POSIX qw(ceil);
use Mojo::mysql;
use Net::LDAP qw(LDAP_SUCCESS LDAP_INSUFFICIENT_ACCESS LDAP_NO_SUCH_OBJECT);
use Net::LDAP::Util qw(canonical_dn escape_filter_value escape_dn_value);
use Encode qw(encode_utf8 decode_utf8);
#use Data::Dumper;
use Adup::Ural::ChangeUserCreate;
use Adup::Ural::ChangeUserMove;
use Adup::Ural::ChangeAttr;
use Adup::Ural::ChangeError;
use Adup::Ural::Dblog;
use Adup::Ural::DeptsHash;

# 1/undef = Adup::Ural::SyncAttributesCreateMoveUsers::do_sync(
#   db => $db_adup,
#   ldap => $ldap,
#   log => $log,
#   job => $job,
#   user => $remote_user
# );
sub do_sync {
  my (%args) = @_;
  for (qw/db ldap log job user/) { croak 'Required parameters missing' unless defined $args{$_}};
  say "in SyncAttributesCreateMoveUsers subtask";

  # first extract all dept records into one hash cache
  my $depts_hash = Adup::Ural::DeptsHash->new($args{db}) or return undef;

  #
  ### begin of persons main loop ###
  #
  my $res;
  my $e = eval {
    $res = $args{db}->query("SELECT fio, dup, f, i, o, dolj, otdel, tabn, dept_id, \
      depts.name AS dept, \
      flatdepts.cn AS flatdept_cn, flatdepts.name AS flatdept_name  \
      FROM persons \
      LEFT OUTER JOIN depts ON dept_id = depts.id \
      LEFT OUTER JOIN flatdepts ON flatdept_id = flatdepts.id \
      ORDER BY persons.id ASC");
  };
  unless (defined $e) {
    carp 'SyncAttributesCreateMoveUsers - database fatal error';
    return undef;
  }

  my $line_count = 0;
  my $lines_total = $res->rows;
  my $attr_changes_count = 0;
  my $create_changes_count = 0;
  my $move_changes_count = 0;
  my $mod = int($lines_total / 20) || 1;
  my $ldapbase = $args{job}->app->config->{ldap_base};
  my $pers_ldapbase = $args{job}->app->config->{personnel_ldap_base};
  my $fg_ldapbase = $args{job}->app->config->{flatgroups_ldap_base};
  my @attributes = qw/givenName sn middleName displayName initials title company department description employeeID/;

  while (my $next = $res->hash) {
    #say "Обрабатываем ФИО: $next->{fio}";
    my $cn = substr($next->{fio}, 0, 64);

    # build hierarhical user dn
    my $dn_built = $depts_hash->build_user_dn($cn, $next->{dept_id}, $pers_ldapbase);
    #say $dn_built;

    # build hash of reference attributes (from database)
    my $refhash = {};
    $refhash->{givenName} = substr($next->{i}, 0, 64) if $next->{i};
    $refhash->{sn} = substr($next->{f}, 0, 64) if $next->{f};
    $refhash->{middleName} = substr($next->{o}, 0, 64) if $next->{o};
    $refhash->{displayName} = substr($next->{fio}, 0, 256);
    $refhash->{initials} = _abbr($next->{fio});
    $refhash->{title} = substr($next->{dolj}, 0, 128) if $next->{dolj};
    $refhash->{company} = 'МУП "Уфаводоканал"';
    $refhash->{department} = substr($next->{dept}, 0, 64) if $next->{dept};
    $refhash->{description} = substr($next->{otdel}, 0, 1024) if $next->{otdel};
    $refhash->{employeeID} = substr($next->{tabn}, 0, 16) if $next->{tabn};


    my $dup = $next->{dup};
    if ($dup == 0 || $dup == 1) {
      my $r;
      if ($dup == 0) {
        # ** unique fio-s **
        # search ldap globally
        my $filter_fio = escape_filter_value $cn;
        my $filter = "(&(objectCategory=person)(objectClass=user)(cn=$filter_fio))";
        $r = $args{ldap}->search(base => $ldapbase, scope => 'sub',
  	  filter => $filter, 
	  attrs => [ 'cn','name', @attributes ]
        );
      } elsif ($dup == 1) {
	# ** duplicates in different departments **
	# search ldap inside only department
	$r = $args{ldap}->search(base => $dn_built, scope => 'base',
	  filter => '(&(objectCategory=person)(objectClass=user))', 
	  attrs => [ 'cn','name', @attributes ]
	);
      } else { die 'FIXME'; }

      if ($r->code && $r->code != LDAP_NO_SUCH_OBJECT) {
        $args{log}->l(state => 11, info => "Синхронизация пользователей. Произошла ошибка поиска в AD.");
	carp 'SyncAttributesCreateMoveUsers - ldap search error: '.$r->error."for CN: $cn";
        return undef;
      }

      my $count = $r->count;
      #say "Найдено: $count";
      
      if ($count == 1) {
	# found 1. check and sync attributes
	my $entry = $r->entry(0);
	#say Dumper $entry;
	my $dn = decode_utf8($entry->dn);
	my $canon_dn = canonical_dn($dn);
	#say 'dn: '.$dn;
       
	# hash of existing attributes (from AD)
	my $exhash = {};
	my $get_val_func = sub { $exhash->{$_[0]} = decode_utf8($entry->get_value($_[0])) if defined $entry->get_value($_[0]); };
	$get_val_func->($_) for (@attributes);
	#for (keys %$refhash) { say $_.' => '.$refhash->{$_}; }
	#for (keys %$exhash) { say $_.' => '.$exhash->{$_}; }

	my $c = Adup::Ural::ChangeAttr->new($next->{fio}, $dn, $args{user});
	# apply for attributes change
	for (@attributes) {
          if (exists $refhash->{$_}) {
	    if (!defined $exhash->{$_}) {
	      $c->set_attr($_, $refhash->{$_});
	    } elsif ($exhash->{$_} ne $refhash->{$_}) {
	      $c->set_attr($_, $exhash->{$_}, $refhash->{$_});
	    }
	  }
	}
	# apply for flat group change
	if (my $fg_cn = $next->{flatdept_cn}) {
          $fg_cn = escape_dn_value $fg_cn;
	  my $fg_dn = "CN=$fg_cn,$fg_ldapbase";
          my $fg_name = substr($next->{flatdept_name}, 0, 1024) if $next->{flatdept_name};
	  # get members of this flat group
          $r = $args{ldap}->search(base => $fg_dn, scope => 'base',
	    filter => '(objectClass=Group)', 
	    attrs => [ 'member' ]);
	  if ($r->code && $r->code != LDAP_NO_SUCH_OBJECT) {
	    $args{log}->l(state => 11, info => "Синхронизация пользователей. Произошла ошибка поиска групп в AD.");
	    carp 'SyncAttributesCreateMoveUsers - ldap group search error: '.$r->error."for DN: $fg_dn";
	    return undef;
	  }

	  if ($r->count > 0) {
	    # found flat group, look up for user in it
	    my $entry = $r->entry(0);
	    my @v = $entry->get_value('member');
	    my $groupmember;
	    GROUPMEMBER:
	    foreach my $m (@v) {
              utf8::decode($m);
	      #say "Member: ".canonical_dn($m);
              if (canonical_dn($m) eq $canon_dn) {
                $groupmember = 1;
		last GROUPMEMBER;
	      }
	    }
	    $c->set_flatgroup($fg_dn, $fg_name) unless $groupmember;

	  } else {
	    # flat group not found, create error change
	    my $c_err = Adup::Ural::ChangeError->new($next->{fio}, $dn, $args{user});
	    $c_err->set_error('В AD отсутствует почтовая группа для объекта пользователя (смотри имя объекта), возможно не все изменения создания почтовых групп были применены.');
	    $c_err->todb(db => $args{db});
	  }
        } #if (flatdept_cn)
	
        unless ($c->empty) {
	  $c->todb(db => $args{db});
	  $attr_changes_count++;
        }

	# moving user (only for unique persons)
	if ($dup == 0 and $canon_dn ne canonical_dn($dn_built)) {
	  # user has to be moved to $dn_built
	  #say $dn."\n".$dn_built."\n";
	  my $c = Adup::Ural::ChangeUserMove->new($next->{fio}, $dn, $args{user});
	  $c->new_dn($dn_built); #new_dn is mandatory
	  $c->todb(db => $args{db});

	  $move_changes_count++;
	}

      } elsif ($count > 1) {
	# found more than 1.
	my $entry = $r->entry(0);
	my $dn = decode_utf8($entry->dn);
	my $c = Adup::Ural::ChangeError->new($next->{fio}, $dn, $args{user});
	$c->set_error('Требуется ручное вмешательство. В AD найдено более одной учётной записи с одинаковым CN (смотри имя объекта).');
	$c->todb(db => $args{db});

      } else {
	# user not found.
	my $c = Adup::Ural::ChangeUserCreate->new($next->{fio}, $dn_built, $args{user});
	$c->set_cn($cn); #cn is mandatory
	for (@attributes) {
	  $c->set_attr($_, $refhash->{$_}) if (exists $refhash->{$_});
	}
	if (my $fg_cn = $next->{flatdept_cn}) {
          $fg_cn = escape_dn_value $fg_cn;
          my $fg_name = substr($next->{flatdept_name}, 0, 1024) if $next->{flatdept_name};
	  $c->set_flatgroup("CN=$fg_cn,$fg_ldapbase", $fg_name);
        }

	$c->todb(db => $args{db});
	$create_changes_count++;
      }

    } else {
      # **duplicates in one department**
      $args{log}->l(state=>11, info => "Дублирующееся ФИО: $next->{fio} пропущено. Внимание! Имеются сотрудники с одинаковыми ФИО в одном подразделении.");
      #say "Дублирующееся ФИО: $next->{fio} пропущено";
    }

    # update progress
    $line_count++;
    if ($line_count % $mod == 0) {
      my $percent = ceil($line_count / $lines_total * 100);
      $args{job}->note(
	progress => $percent,
        # mysql minion backend bug workaround
	info => encode_utf8("$percent% Синхронизация пользователей, изменений аттрибутов"),
      );
    }
  }
  #
  ### end of persons main loop ###
  #

  $res->finish;

  $args{log}->l(info => "Синхронизация пользователей. $create_changes_count изменений создания пользователей, $attr_changes_count изменений аттрибутов, $move_changes_count изменений перемещения пользователей, по $line_count сотрудникам.");

  return 1;
}


# internal
sub _abbr {
  my $name = shift; #fio
  my @abbr;
  for my $w (split(/[ _-]/, $name)) {
    push @abbr, substr($w, 0, 1);
  }
  return uc join('', @abbr);
}


1;
