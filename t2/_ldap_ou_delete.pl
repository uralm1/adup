#!/usr/bin/perl

use strict;
use warnings;
use v5.12;
use utf8;
use Carp;
use Net::LDAP qw(LDAP_SUCCESS LDAP_NO_SUCH_OBJECT LDAP_INSUFFICIENT_ACCESS LDAP_NOT_ALLOWED_ON_NONLEAF);
use Data::Dumper;

#binmode(STDOUT, ':utf8');

my $remote_user = 'ural';
my $ldapservers = ['ldap://dcsrv'];
my $ldapuser = 'user';
my $ldappass = 'pass';
my $ldapbase = 'DC=contoso,DC=local';

my $ldap = Net::LDAP->new($ldapservers, port => 389, timeout => 10, version => 3);

my $mesg = $ldap->bind($ldapuser, password => $ldappass);

my $dn = "OU=ZZZ,OU=T,$ldapbase";
$mesg = $ldap->delete($dn);

if ($mesg->code == LDAP_INSUFFICIENT_ACCESS) {
  say "Insufficient access";
} elsif ($mesg->code == LDAP_NO_SUCH_OBJECT) {
  say "No such object";
} elsif ($mesg->code == LDAP_NOT_ALLOWED_ON_NONLEAF) {
  say "Has child objects";
} elsif ($mesg->code) {
  die "delete error ".$mesg->error;
}

$ldap->unbind;

