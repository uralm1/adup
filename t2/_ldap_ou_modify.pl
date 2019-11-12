#!/usr/bin/perl

use strict;
use warnings;
use v5.12;
use utf8;
use Carp;
use Net::LDAP;
use Data::Dumper;

#binmode(STDOUT, ':utf8');

my $remote_user = 'ural';
my $ldapservers = ['ldap://dcsrv'];
my $ldapuser = 'user';
my $ldappass = 'pass';
my $ldapbase = 'DC=contoso,DC=local';

my $ldap = Net::LDAP->new($ldapservers, port => 389, timeout => 10, version => 3, onerror => 'die');

my $mesg = $ldap->bind($ldapuser, password => $ldappass);

my $n = "Тест 1";
my $dn = "OU=$n,OU=T,$ldapbase";
$mesg = $ldap->modify($dn,
  replace => { description => 'New description' }
);

if ($mesg->code) {
  die "modify error ".$mesg->error;
}

$ldap->unbind;

