package Adup::Ural::SyncCreateOUs;
use Mojo::Base -base;

use Carp;
use POSIX qw(ceil);
use Mojo::mysql;
use Net::LDAP qw(LDAP_SUCCESS LDAP_INSUFFICIENT_ACCESS LDAP_NO_SUCH_OBJECT);
use Net::LDAP::Util qw(canonical_dn escape_filter_value escape_dn_value);
use Encode qw(encode_utf8 decode_utf8);
#use Data::Dumper;
use Adup::Ural::ChangeOUCreate;
use Adup::Ural::ChangeOUModify;
use Adup::Ural::ChangeError;
use Adup::Ural::Dblog;
use Adup::Ural::DeptsHash;


# changes_count/undef = Adup::Ural::SyncCreateOUs::do_sync(
#   db => $db_adup,
#   ldap => $ldap,
#   log => $log,
#   job => $job,
#   user => $remote_user,
#   pos => 0
# );
sub do_sync {
  my (%args) = @_;
  for (qw/db ldap log job user pos/) { croak 'Required parameters missing' unless defined $args{$_}};
  say "in SyncCreateOUs subtask";

  # first extract all dept records into one hash cache
  my $depts_hash = Adup::Ural::DeptsHash->new($args{db}) or return undef;
  my $lines_total = scalar keys %$depts_hash;

  my $pers_ldapbase = $args{job}->app->config->{personnel_ldap_base};
  my $changes_count = 0;
  my $line_count = 0;
  my $mod = int($lines_total / 20) || 1;
  my $max_level = 0;

  #
  ### we support 20 levels hierarhy
  #
  for my $level (0..19) {
    #
    ### begin of one level departments loop ###
    #
    my $res;
    my $e = eval {
      $res = $args{db}->query("SELECT name, parent \
	FROM depts \
	WHERE level = ? \
	ORDER BY id ASC", $level);
    };
    unless (defined $e) {
      carp 'SyncCreateOUs - database fatal error';
      return undef;
    }

    my $level_lines_total = $res->rows;

    # exit hierarhy level loop when nothing left
    $max_level = $level;
    last if $level_lines_total == 0;

    while (my $next = $res->hash) {
      #say $next->{name};

      my $ouname = substr($next->{name}, 0, 64);
      my $fullname = substr($next->{name}, 0, 1024);
      # build hierarhy dn
      my $dn = $depts_hash->build_ou_dn($ouname, $level, $next->{parent}, $pers_ldapbase);
      #say $dn;
      #say $fullname;

      #my $fdn = escape_filter_value $dn; #(distinguishedName=$fdn) #my $filter = "(&(objectCategory=organizationalunit)(objectClass=organizationalunit))";
      my $r = $args{ldap}->search(base => $dn, scope => 'base',
	filter => '(&(objectCategory=organizationalunit)(objectClass=organizationalunit))',
	attrs => ['name', 'description']
      );
      if ($r->code && $r->code != LDAP_NO_SUCH_OBJECT) {
        $args{log}->l(state => 11, info => "Синхронизация подразделений. Произошла ошибка поиска в AD.");
	carp 'SyncCreateOUs - ldap search error: '.$r->error." for DN: $dn";
        return undef;
      }

      my $count = $r->count;
      if ($count == 1) {
	# found 1.
	my $entry = $r->entry(0);
	my $dn = decode_utf8($entry->dn);
	my $description = decode_utf8($entry->get_value('description'));
	#say "found description: $description";
	# compare with $gname and create change to modify ou
	# compare only first 64 chars to solve problem with departments with the same names
	if (substr($description, 0, 64) ne $ouname) {
	  my $c = Adup::Ural::ChangeOUModify->new($fullname, $dn, $args{user});
	  $c->set_level_dept_names($level, $description, $fullname);
	  $c->todb(db => $args{db}, metadata => $level);
	  $changes_count++;
	}

      } elsif ($count > 1) {
	# more than 1. This is VERY strange situation... just create error change
	my $entry = $r->entry(0);
	my $dn = decode_utf8($entry->dn);
	# create errorchange
	my $c = Adup::Ural::ChangeError->new($next->{name}, $dn, $args{user});
	$c->set_error("Подразделение, уровень $level. В AD найдено более одного подразделения с одинаковым именем OU (смотри имя объекта).");
	$c->todb(db => $args{db});

      } else {
	# not found
	my $c = Adup::Ural::ChangeOUCreate->new($fullname, $dn, $args{user});
	$c->set_level_dept_name($level, $fullname);
	$c->todb(db => $args{db}, metadata => $level);
	$changes_count++;
      }

      # update progress
      $line_count++;
      if ($line_count % $mod == 0) {
	my $percent = ceil(($args{pos} + $line_count / $lines_total) * $args{job}->app->percent_sync_task);
        $args{job}->note(
	  progress => $percent,
          # mysql minion backend bug workaround
	  info => encode_utf8("$percent% Синхронизация подразделений"),
	);
      }
    }
    #
    ### end of one level departments loop ###
    #
    $res->finish;

  }
  #
  # end of levels loop
  #

  $args{log}->l(info => "*ЗАПУСК СИНХРОНИЗАЦИИ* Синхронизация подразделений. Рассчитано $changes_count изменений подразделений по $line_count подразделениям на $max_level уровнях иерархии.");

  return $changes_count;
}


1;
