#!/usr/bin/perl

use strict;
use warnings;
use v5.12;
use utf8;
use Carp;
use Net::LDAP qw(LDAP_SUCCESS LDAP_NO_SUCH_OBJECT LDAP_SIZELIMIT_EXCEEDED); 
use Net::LDAP::Util qw(canonical_dn escape_filter_value escape_dn_value);
use Data::Dumper;

#binmode(STDOUT, ':utf8');

my $ldapservers = ['ldap://dcsrv'];
my $ldapuser = 'user';
my $ldappass = 'pass';
my $ldapbase = 'DC=contoso,DC=local';
my $skip_dn = [
  'OU=11CONTACTS,OU=1,DC=contoso,DC=local',
];

my $ldap = Net::LDAP->new($ldapservers, port => 389, timeout => 10, version => 3);

my $mesg = $ldap->bind($ldapuser, password => $ldappass);

my $dn = "OU=1,$ldapbase";

# add base object DN to $skip_dn
push @$skip_dn, $dn;
# canonicalize $skip_dn-s
map {$_ = canonical_dn($_) } @$skip_dn;

my $filter = "(&(objectCategory=organizationalunit)(objectClass=organizationalunit))";
my $res = $ldap->search(base => $dn, scope => 'sub', 
  filter => $filter, 
  attrs => ['name','description']);
if ($res->code == LDAP_NO_SUCH_OBJECT) {
  say 'Nothing found as error.';

} elsif ($res->code) {
  die "search error ".$res->error;
}

my $count = $res->count;
say "Found entries: $count";
open(my $fh, '>', 'ouentries') or die 'open error';

# WARNING: results include base OU object
ENTRYLOOP:
while (my $entry = $res->shift_entry) {
  # filter by DN
  my $canon_dn = canonical_dn($entry->dn);
  for (@$skip_dn) {
    next ENTRYLOOP if ($canon_dn =~ /^$_$/);
  }
  ###
  say $fh $entry->dn;
}

close $fh;
$ldap->unbind;

