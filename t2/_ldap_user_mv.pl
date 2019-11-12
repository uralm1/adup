#!/usr/bin/perl

use strict;
use warnings;
use v5.12;
use utf8;
use Carp;
use Net::LDAP qw(LDAP_SUCCESS LDAP_INSUFFICIENT_ACCESS LDAP_ALREADY_EXISTS);
use Net::LDAP::Util qw(canonical_dn escape_filter_value escape_dn_value);
use Data::Dumper;

use lib "../lib";

#binmode(STDOUT, ':utf8');

my $ldapservers = ['ldap://dcsrv'];
my $ldapuser = 'user';
my $ldappass = 'pass';
my $ldapbase = 'DC=contoso,DC=local';

my $ldap = Net::LDAP->new($ldapservers, port => 389, timeout => 10, version => 3);

my $mesg = $ldap->bind($ldapuser, password => $ldappass);

my $cn = "Пользователь 4";
my $cn_new = "Польз4";
my $ecn = escape_dn_value $cn;
my $ecn_new = escape_dn_value $cn_new;

my $dn = "CN=$ecn,OU=testou,OU=T,$ldapbase";
my $dn_sup = "OU=Тест 1,OU=T,$ldapbase";

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


