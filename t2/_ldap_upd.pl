#!/usr/bin/perl

use strict;
use warnings;
use v5.12;
use utf8;
use Carp;
use Net::LDAP qw(LDAP_SUCCESS LDAP_INSUFFICIENT_ACCESS);
use Net::LDAP::Util qw(canonical_dn);
use Data::Dumper;
use Mojo::File 'path';

#binmode(STDOUT, ':utf8');

my $cfg = eval path('../test.conf')->slurp;

my $ldap = Net::LDAP->new($cfg->{ldap_servers}, port => 389, timeout => 10, version => 3);
die "LDAP creation error $@" unless($ldap);

my $mesg = $ldap->bind($cfg->{ldap_user}, password => $cfg->{ldap_pass});
if ($mesg->code) {
  die "bind error ".$mesg->error;
}

my $dn = "CN=Тест ADUP,OU=TEMPORARY,OU=UWC Users,$cfg->{ldap_base}";
$mesg = $ldap->modify($dn,
  #replace => { info => 'Новое Значение' }
  add => { description => 'new val111' }
);

if ($mesg->code) {
  die "modify error ".$mesg->error;
}

$ldap->unbind;

