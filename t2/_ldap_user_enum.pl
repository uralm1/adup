#!/usr/bin/perl

use strict;
use warnings;
use v5.12;
use utf8;
use Carp;
use Net::LDAP qw(LDAP_SUCCESS LDAP_NO_SUCH_OBJECT LDAP_SIZELIMIT_EXCEEDED LDAP_CONTROL_PAGED); 
use Net::LDAP::Util qw(canonical_dn escape_filter_value escape_dn_value);
use Net::LDAP::Control::Paged;
use Data::Dumper;
use Mojo::File 'path';

#binmode(STDOUT, ':utf8');

my $cfg = eval path('../test.conf')->slurp;
my $skip_dn = [
  "OU=11CONTACTS,OU=1,$cfg->{ldap_base}",
  "OU=4SYSTEM,$cfg->{ldap_base}",
  "OU=5DISMISSED,$cfg->{ldap_base}",
  "OU=6TEMPORARY,$cfg->{ldap_base}",
  "OU=Admins,$cfg->{ldap_base}",
  "CN=Users,$cfg->{ldap_base}",
  "OU=SYSTEM,OU=UWC Users,$cfg->{ldap_base}",
];

my $ldap = Net::LDAP->new($cfg->{ldap_servers}, port => 389, timeout => 10, version => 3);

my $mesg = $ldap->bind($cfg->{ldap_user}, password => $cfg->{ldap_pass});

my $pagedctl = Net::LDAP::Control::Paged->new(size => 100);

my $filter = "(&(objectCategory=person)(objectClass=user))";
my @searchargs = ( base => $cfg->{ldap_base}, scope => 'sub',
  filter => $filter, 
  attrs => ['name','cn'],
  control => [ $pagedctl ]
);

my $page_num = 1;
my $entry_count = 0;
open(my $fd, '>', 'userentries') or die "Can't create file: $!";

# canonicalize $skip_dn-s
map {$_ = canonical_dn($_) } @$skip_dn;

my $cookie;
my $res;
while (1) {
  say "# page $page_num start ###########################";
  $res = $ldap->search(@searchargs);

  # break loop on error
  $res->code and last;

  ## consume results
  my $count = $res->count;
  say "Found entries: $count";
  if ($count > 0) {
    ENTRYLOOP:
    for my $entry ($res->entries) {
      # filter by DN
      my $canon_dn = canonical_dn($entry->dn);
      for (@$skip_dn) {
        next ENTRYLOOP if ($canon_dn =~ /$_$/);
      }
      ###
      say $fd $entry->dn;
      #my $entry = $res->entry(0);
      #say Dumper $entry;
      #say $entry->get_value('name');
      $entry_count ++;
    }

  } else {
    say 'Nothing found.';
  }

  my ($resp) = $res->control(LDAP_CONTROL_PAGED) or last;
  $cookie = $resp->cookie;

  # continue if cookie is nonempty
  last if (!defined($cookie) || !length($cookie));

  # set cookie in paged control
  $pagedctl->cookie($cookie);

  $page_num++;
}

if (defined($cookie) && length($cookie)) {
  # abnormal exit, so let the server know we dont want any more
  $pagedctl->cookie($cookie);
  $pagedctl->size(0);
  $ldap->search(@searchargs);
}

if ($res->code) {
  die "search error ".$res->error;
}

say "Total Found: $entry_count entries.";
close($fd);

$ldap->unbind;

