package Adup::Ural::SyncDeleteOUs;
use Mojo::Base -base;

use Carp;
use POSIX qw(ceil);
use Mojo::mysql;
use Net::LDAP qw(LDAP_SUCCESS LDAP_INSUFFICIENT_ACCESS LDAP_NO_SUCH_OBJECT LDAP_SIZELIMIT_EXCEEDED);
use Net::LDAP::Util qw(canonical_dn ldap_explode_dn escape_filter_value escape_dn_value);
use Encode qw(encode_utf8 decode);
#use Data::Dumper;
use Adup::Ural::ChangeOUDelete;
use Adup::Ural::ChangeError;
use Adup::Ural::Dblog;
use Adup::Ural::DeptsHash;

# changes_count/undef = Adup::Ural::SyncDeleteOUs::do_sync(
#   db => $db_adup,
#   ldap => $ldap,
#   log => $log,
#   job => $job,
#   user => $remote_user
# );
sub do_sync {
  my (%args) = @_;
  for (qw/db ldap log job user/) { croak 'Required parameters missing' unless defined $args{$_}};
  say "in SyncDeleteOUs subtask";

  # load depts table from database into memory hash
  my $depts_hash = Adup::Ural::DeptsHash->new($args{db}) or return undef;

  my %depts_paths; # ou (name cut to 64) is a key
  my $e = eval {
    my $r = $args{db}->query("SELECT id, name, level, parent \
      FROM depts \
      ORDER BY id ASC");
    while (my $next = $r->hash) {
      my $ou = substr($next->{name}, 0, 64);
      my @oulist;
      my $parent = $next->{parent};
      while ($parent != 0) {
	push @oulist, substr($depts_hash->{$parent}{name}, 0, 64);
	$parent = $depts_hash->{$parent}{parent};
      }
      push @{$depts_paths{$ou}}, [@oulist];
    }
    $r->finish;
  };
  unless (defined $e) {
    carp 'SyncDeleteOUs - database fatal error';
    return undef;
  }
  $depts_hash = undef; # free mem


  my $persldapbase = $args{job}->app->config->{personnel_ldap_base};
  # load exclusions array
  my $skip_dn = [ @{$args{job}->app->config->{ou_cleanup_skip_dn}} ];
  croak 'ou_cleanup_skip_dn is missing!' unless defined $skip_dn;
  # add base object DN to $skip_dn
  push @$skip_dn, $persldapbase;
  # canonicalize exclusions dn-s
  map {$_ = canonical_dn($_) } @$skip_dn;

  #
  ### begin of OU loop ###
  #
  my $res = $args{ldap}->search(base => $persldapbase, scope => 'sub',
    filter => '(&(objectCategory=organizationalunit)(objectClass=organizationalunit))',
    attrs => ['ou', 'description']
  );
  if ($res->code && $res->code != LDAP_NO_SUCH_OBJECT) {
    $args{log}->l(state => 11, info => "Удаление подразделений. Произошла ошибка поиска в AD.");
    carp 'SyncDeleteOUs - ldap search error: '.$res->error;
    return undef;
  }

  my $entries_total = $res->count;
  #say "Found entries: $entries_total";
  my $mod = int($entries_total / 20) || 1;
  my $entry_count = 0;
  my $delete_changes_count = 0;

  # WARNING: results include base OU object
ENTRYLOOP:
  while (my $entry = $res->shift_entry) {
    # filter by DN
    my $canon_dn = canonical_dn($entry->dn);
    for (@$skip_dn) {
      next ENTRYLOOP if ($canon_dn =~ /^$_$/);
    }

    ## consume results
    my $dn = decode('utf-8', $entry->dn);
    my $ou = decode('utf-8', $entry->get_value('ou'));
    my $name = decode('utf-8', $entry->get_value('description')) || $ou;

    my $dn_aofh = ldap_explode_dn($dn);
    my $base_aofh = ldap_explode_dn($persldapbase);
    unless (defined $base_aofh and defined $dn_aofh) {
      $args{log}->l(state => 11, info => "Удаление подразделений. Произошла ошибка разбора DN (1).");
      carp "SyncDeleteOUs - ldap explode error for DN: $dn";
      return undef;
    }
    # remove "OU=1,DC=uwc,DC=local" part
    while (my $h = pop @$base_aofh) {
      my ($h_k, $h_v) = each %$h;
      my $h1 = pop @$dn_aofh;
      unless ($h1) {
        $args{log}->l(state => 11, info => "Удаление подразделений. Произошла ошибка разбора DN (2).");
	carp "SyncDeleteOUs - bad base in DN: $dn";
	return undef;
      }
      my ($h1_k, $h1_v) = each %$h1;
      if ($h_k ne $h1_k or $h_v ne $h1_v) {
        $args{log}->l(state => 11, info => "Удаление подразделений. Произошла ошибка разбора DN (3).");
	carp "SyncDeleteOUs - bad base (2) in DN: $dn";
	return undef;
      }
    }

    my $success = undef;
    my $level = $#$dn_aofh;

    # get first ou name
    my $h = shift @$dn_aofh;
    unless (defined $h) {
      $args{log}->l(state => 11, info => "Удаление подразделений. Произошла ошибка разбора DN (4).");
      carp "SyncDeleteOUs - first element is empty in DN: $dn";
      return undef;
    }
    my ($k, $ouname_first) = each %$h;

    # check next in sequence
    if (my $arr = $depts_paths{$ouname_first}) {
      # make a sample list
      my @samp_list;
      while (my $h = shift @$dn_aofh) {
	my ($k, $ouname) = each %$h;
	push @samp_list, $ouname;
      }

      VARIANTSLOOP:
      for my $variant (@$arr) {
	# first compare lists lengths
	if (scalar(@samp_list) == scalar(@$variant)) {
	  # then compare lists
	  #say 'Comparing: ['.join(',',@samp_list).'] and ['.join(',',@$variant).'].';
	  my $lists_is_equal = 1;
	  LISTCOMP:
	  for (my $i = 0; $i <= $#samp_list; $i++) {
            if ($samp_list[$i] ne $variant->[$i]) {
	      $lists_is_equal = undef;
	      last LISTCOMP;
	    }
	  }
          if ($lists_is_equal) {
	    $success = 1;
	    last VARIANTSLOOP;
	  }
	}
	# else - try next variant
      }
      # no more variants - unsuccessful match
    }
    # else - unsuccessful match

    unless ($success) {
      #say $dn;
      my $c = Adup::Ural::ChangeOUDelete->new($name, $dn, $args{user});
      $c->level($level);
      $c->todb(db => $args{db}, metadata => $level);

      $delete_changes_count++;
    }

    # update progress
    $entry_count++;
    if ($entry_count % $mod == 0) {
      my $percent = ceil($entry_count / $entries_total * 100);
      $args{job}->note(
	progress => $percent,
	info => "$percent% Завершающая синхронизация подразделений",
      );
    }

  } # entries loop

  $args{log}->l(info => "Завершающая синхронизация подразделений. Создано $delete_changes_count изменений удаления подразделений, по $entry_count подразделениям.");

  return $delete_changes_count;
}


1;
