package Adup::Ural::SyncDeleteUsers;
use Mojo::Base -base;

use Carp;
use POSIX qw(ceil);
use Mojo::mysql;
use Net::LDAP qw(LDAP_SUCCESS LDAP_INSUFFICIENT_ACCESS LDAP_NO_SUCH_OBJECT LDAP_SIZELIMIT_EXCEEDED LDAP_CONTROL_PAGED);
use Net::LDAP::Util qw(canonical_dn escape_filter_value escape_dn_value);
use Net::LDAP::Control::Paged;
use Encode qw(decode);
#use Data::Dumper;
use Adup::Ural::ChangeUserDelete;
use Adup::Ural::ChangeError;
use Adup::Ural::Dblog;

# changes_count/undef = Adup::Ural::SyncDeleteUsers::do_sync(
#   db => $db_adup,
#   ldap => $ldap,
#   log => $log,
#   job => $job,
#   user => $remote_user
# );
sub do_sync {
  my (%args) = @_;
  for (qw/db ldap log job user/) { croak 'Required parameters missing' unless defined $args{$_}};
  say "in SyncDeleteUsers subtask";

  # upload persons table from database into memory
  my %persons_hash; # cn is a key
  my $entries_total;
  my $e = eval {
    my $r = $args{db}->query("SELECT fio, dup, tabn \
      FROM persons \
      ORDER BY id ASC");
    $entries_total = $r->rows;
    while (my $next = $r->hash) {
      $persons_hash{substr($next->{fio}, 0, 64)} = $next->{tabn} if ($next->{dup} == 0);
    }
    $r->finish;
  };
  unless (defined $e) {
    carp 'SyncDeleteUsers - database fatal error';
    return undef;
  }

  my $ldapbase = $args{job}->app->config->{ldap_base};
  # load exclusions array
  my $skip_dn = $args{job}->app->config->{user_cleanup_skip_dn};
  croak 'user_cleanup_skip_dn is missing!' unless defined $skip_dn;
  # canonicalize exclusions dn-s
  map {$_ = canonical_dn($_) } @$skip_dn;

  #
  ### begin of persons main loop ###
  #
  my $pagedctl = Net::LDAP::Control::Paged->new(size => 100);

  my @searchargs = ( base => $ldapbase, scope => 'sub',
    filter => '(&(objectCategory=person)(objectClass=user))', 
    attrs => ['cn', 'sAMAccountName', 'mail', 'userAccountControl'],
    control => [ $pagedctl ]
  );


  my $mod = int($entries_total / 20) || 1;
  my $entry_count = 0;
  my $delete_changes_count = 0;
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
      ENTRYLOOP:
      for my $entry ($res->entries) {
	# filter by DN
	my $canon_dn = canonical_dn($entry->dn);
	for (@$skip_dn) {
	  next ENTRYLOOP if ($canon_dn =~ /$_$/);
	}

	# check if cn exists in persons hash
	my $cn = decode('utf-8', $entry->get_value('cn'));
	unless (exists $persons_hash{$cn}) {
	  #say $entry->get_value('cn').' '.$entry->dn;
	  my $c = Adup::Ural::ChangeUserDelete->new($cn, decode('utf-8', $entry->dn), $args{user});
	  $c->cn($cn);
	  $c->login(decode('utf-8', $entry->get_value('sAMAccountName'))) if ($entry->get_value('sAMAccountName'));
	  $c->email(decode('utf-8', $entry->get_value('mail'))) if ($entry->get_value('mail'));
	  my $uac = $entry->get_value('userAccountControl') || 0x200;
	  $c->disabled(($uac & 2) == 2);
	  $c->todb(db => $args{db});

	  $delete_changes_count++;
	}

        # update progress
	$entry_count ++;
        if ($entry_count % $mod == 0) {
          my $percent = ceil($entry_count / $entries_total * 100);
          $args{job}->note(
	    progress => $percent,
	    info => "$percent% Завершающая синхронизация уволенных пользователей",
          );
        }
      }

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
    $args{log}->l(state => 11, info => "Блокирование пользователей. Произошла ошибка поиска в AD.");
    carp 'SyncDeleteUsers - ldap paged search error: '.$res->error;
    return undef;
  }

  $args{log}->l(info => "Завершающая синхронизация уволенных пользователей. $delete_changes_count изменений блокирования пользователей, по $entry_count учётным записям.");

  return $delete_changes_count;
}


1;