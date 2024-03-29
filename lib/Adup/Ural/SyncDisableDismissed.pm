package Adup::Ural::SyncDisableDismissed;
use Mojo::Base -base;

use Carp;
use POSIX qw(ceil);
use Net::LDAP qw(LDAP_SUCCESS LDAP_INSUFFICIENT_ACCESS LDAP_NO_SUCH_OBJECT LDAP_SIZELIMIT_EXCEEDED LDAP_CONTROL_PAGED);
use Net::LDAP::Util qw(canonical_dn escape_filter_value escape_dn_value);
use Net::LDAP::Control::Paged;
use Encode qw(encode_utf8 decode_utf8);
#use Data::Dumper;
use Adup::Ural::ChangeUserDisableDismissed;
use Adup::Ural::ChangeError;
use Adup::Ural::Dblog;

# changes_count/undef = Adup::Ural::SyncDisableDismissed::do_sync(
#   db => $db_adup,
#   ldap => $ldap,
#   log => $log,
#   job => $job,
#   user => $remote_user,
#   pos => 6
# );
sub do_sync {
  my (%args) = @_;
  for (qw/db ldap log job user pos/) { croak 'Required parameters missing' unless defined $args{$_}};
  say "in SyncDisableDismissed subtask";

  my $dismissed_ldapbase = $args{job}->app->config->{dismissed_ou_dn};
  my $pmsg = 'Проверка, все ли архивные учетные записи отключены';
  my $percent = ceil($args{pos} * $args{job}->app->percent_sync_task);
  $args{job}->note(
    progress => $percent,
    # mysql minion backend bug workaround
    info => encode_utf8("$percent% $pmsg"),
  );

  #
  ### begin persons in DISMISSED OU loop ###
  #
  my $pagedctl = Net::LDAP::Control::Paged->new(size => 100);

  my @searchargs = ( base => $dismissed_ldapbase, scope => 'sub',
    filter => '(&(objectCategory=person)(objectClass=user)(!(userAccountControl:1.2.840.113556.1.4.803:=2)))',
    attrs => ['cn', 'sAMAccountName', 'mail'],
    control => [ $pagedctl ]
  );

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
        my $cn = decode_utf8($entry->get_value('cn'));
        #say decode_utf8($entry->get_value('cn').' '.$entry->dn);
        my $c = Adup::Ural::ChangeUserDisableDismissed->new($cn, decode_utf8($entry->dn), $args{user});
        $c->cn($cn);
        $c->login(decode_utf8($entry->get_value('sAMAccountName'))) if ($entry->get_value('sAMAccountName'));
        $c->email(decode_utf8($entry->get_value('mail'))) if ($entry->get_value('mail'));
        $c->todb(db => $args{db});

        $delete_changes_count++;
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
    $args{log}->l(state => 11, info => "Проверка блокирования архивных учётных записей. Произошла ошибка поиска в AD.");
    carp 'SyncDisableDismissed - ldap paged search error: '.$res->error;
    return undef;
  }

  $percent = int(($args{pos} + 1) * $args{job}->app->percent_sync_task);
  $args{job}->note(
    progress => $percent,
    # mysql minion backend bug workaround
    info => encode_utf8("$percent% $pmsg"),
  );

  $args{log}->l(info => "Проверка блокирования архивных учётных записей. Создано $delete_changes_count изменений блокирования архивных учётных записей.");

  return $delete_changes_count;
}


1;
