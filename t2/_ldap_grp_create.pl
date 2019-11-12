#!/usr/bin/perl

use strict;
use warnings;
use v5.12;
use utf8;
use Carp;
use Net::LDAP;
use Data::Dumper;

#binmode(STDOUT, ':utf8');

my $ldapservers = ['ldap://dcsrv'];
my $ldapuser = 'user';
my $ldappass = 'pass';
my $ldapbase = 'DC=contoso,DC=local';

my $ldap = Net::LDAP->new($ldapservers, port => 389, timeout => 10, version => 3, onerror => 'die');

my $mesg = $ldap->bind($ldapuser, password => $ldappass);

for (1..10) {
my $n = "Тест $_";
my $dn = "CN=$n,OU=T,$ldapbase";
$mesg = $ldap->add($dn,
  attrs => [
    objectClass => [ qw/top group/ ],
    cn => $n,
    sAMAccountName => $n,
    groupType => 0x2,
  ]
);

if ($mesg->code) {
  die "create error ".$mesg->error;
}

}

$ldap->unbind;

