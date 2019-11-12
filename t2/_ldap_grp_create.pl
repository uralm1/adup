#!/usr/bin/perl

use strict;
use warnings;
use v5.12;
use utf8;
use Carp;
use Net::LDAP;
use Data::Dumper;
use Mojo::File 'path';

#binmode(STDOUT, ':utf8');

my $cfg = eval path('../test.conf')->slurp;

my $ldap = Net::LDAP->new($cfg->{ldap_servers}, port => 389, timeout => 10, version => 3, onerror => 'die');

my $mesg = $ldap->bind($cfg->{ldap_user}, password => $cfg->{ldap_pass});

for (1..10) {
my $n = "Тест $_";
my $dn = "CN=$n,OU=T,$cfg->{ldap_base}";
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

