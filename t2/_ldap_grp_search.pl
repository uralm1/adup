#!/usr/bin/perl

use strict;
use warnings;
use v5.12;
use utf8;
use Carp;
use Net::LDAP qw(LDAP_SUCCESS LDAP_NO_SUCH_OBJECT); 
use Net::LDAP::Util qw(canonical_dn escape_filter_value escape_dn_value);
use Data::Dumper;

#binmode(STDOUT, ':utf8');

my $ldapservers = ['ldap://dcsrv'];
my $ldapuser = 'user';
my $ldappass = 'pass';
my $ldapbase = 'DC=contoso,DC=local';

my $ldap = Net::LDAP->new($ldapservers, port => 389, timeout => 10, version => 3);

my $mesg = $ldap->bind($ldapuser, password => $ldappass);

my $dn = "CN=testgroup1,OU=T,$ldapbase";
my $fdn = escape_filter_value $dn;
#my $filter = "(&(objectCategory=group)(objectClass=group)(distinguishedName=$fdn)(groupType=0x2))";
my $filter = "(&(objectCategory=group)(objectClass=group)(distinguishedName=$fdn))";
#my $res = $ldap->search(base => $ldapbase, filter => $filter, attrs => ['cn','name','info','description']);
my $res = $ldap->search(base => $dn, scope => 'base', filter => $filter, attrs => ['name','description','grouptype']);
if ($res->code == LDAP_NO_SUCH_OBJECT) {
  say 'Nothing found as error.';

} elsif ($res->code) {
  die "search error ".$res->error;
}

my $count = $res->count;
say "Found entries: $count";
if ($count > 0) {
  my $entry = $res->entry(0);
  say Dumper $entry;
  say $entry->get_value('cn');

} else {
  say 'Nothing found.';
}

$ldap->unbind;

