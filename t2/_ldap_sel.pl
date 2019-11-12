#!/usr/bin/perl

use strict;
use warnings;
use v5.12;
use utf8;
use Carp;
use Net::LDAP qw(LDAP_SUCCESS LDAP_NO_SUCH_OBJECT); 
use Data::Dumper;
use Mojo::File 'path';

#binmode(STDOUT, ':utf8');

my $cfg = eval path('../test.conf')->slurp;

my $ldap = Net::LDAP->new($cfg->{ldap_servers}, port => 389, timeout => 10, version => 3, onerror => 'die');

my $mesg = $ldap->bind($cfg->{ldap_user}, password => $cfg->{ldap_pass});

# class=user, contact
my $filter = "(&(objectCategory=person)(objectClass=user)(cn=Тест ADUP))";
#my $res = $ldap->search(base => $cfg->{ldap_base}, filter => $filter, attrs => ['cn','name','info','description']);
my $res = $ldap->search(base => $cfg->{ldap_base}, filter => $filter);
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

