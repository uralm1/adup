#!/usr/bin/perl

use strict;
use warnings;
use v5.12;
use utf8;
use Carp;
use Net::LDAP qw(LDAP_SUCCESS LDAP_INSUFFICIENT_ACCESS LDAP_ALREADY_EXISTS);
use Net::LDAP::Util qw(canonical_dn escape_filter_value escape_dn_value);
use Data::Dumper;
use Mojo::File 'path';

use lib "../lib";

#binmode(STDOUT, ':utf8');

my $cfg = eval path('../test.conf')->slurp;

my $ldap = Net::LDAP->new($cfg->{ldap_servers}, port => 389, timeout => 10, version => 3);

my $mesg = $ldap->bind($cfg->{ldap_user}, password => $cfg->{ldap_pass});

my $cn = "Пользователь 4";
my $cn_new = "Польз4";
my $ecn = escape_dn_value $cn;
my $ecn_new = escape_dn_value $cn_new;

my $dn = "CN=$ecn,OU=testou,OU=T,$cfg->{ldap_base}";
my $dn_sup = "OU=Тест 1,OU=T,$cfg->{ldap_base}";

$mesg = $ldap->moddn($dn,
  newrdn => "CN=$ecn",
  deleteoldrdn => 1,
  newsuperior => $dn_sup,
);

if ($mesg->code) {
  die "moddn error ".$mesg->error;
}

$ldap->unbind;

exit 0;


