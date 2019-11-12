#!/usr/bin/perl

use strict;
use warnings;
use v5.12;
use utf8;
use Carp;
use Net::LDAP qw(LDAP_SUCCESS LDAP_NO_SUCH_OBJECT LDAP_SIZELIMIT_EXCEEDED); 
use Net::LDAP::Util qw(canonical_dn escape_filter_value escape_dn_value);
use Data::Dumper;
use Mojo::File 'path';

#binmode(STDOUT, ':utf8');

my $cfg = eval path('../test.conf')->slurp;

my $ldap = Net::LDAP->new($cfg->{ldap_servers}, port => 389, timeout => 10, version => 3);

my $mesg = $ldap->bind($cfg->{ldap_user}, password => $cfg->{ldap_pass});

my $dn = "OU=2,$cfg->{ldap_base}";
my $filter = "(&(objectCategory=group)(objectClass=group))";
my $res = $ldap->search(base => $dn, scope => 'sub', 
  filter => $filter, 
  attrs => ['name','description','grouptype']);
if ($res->code == LDAP_NO_SUCH_OBJECT) {
  say 'Nothing found as error.';

} elsif ($res->code) {
  die "search error ".$res->error;
}

my $count = $res->count;
say "Found entries: $count";
if ($count > 0) {
  #my $entry = $res->entry(0);
  #say Dumper $entry;
  #say $entry->get_value('cn');

} else {
  say 'Nothing found.';
}

$ldap->unbind;

