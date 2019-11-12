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

#for (1..10) {
my $cn = "Пользователь 4";
my $ecn = escape_dn_value $cn;
my $dn = "CN=$ecn,OU=testou,OU=T,$ldapbase";
$mesg = $ldap->add($dn,
  attrs => [
    objectClass => [ qw/top user/ ],
    cn => $cn, #64
    sn => 'Фамилия', #64
    givenName => 'Имя', #64
    middleName => 'Отчество', #64
    displayName => 'Фамилия Имя Отчество', #256
    initials => 'ФИО', #6
    userAccountControl => 514, #disabled
    sAMAccountName => 'login739',
    userPrincipalName => 'login739@uwc.local',
    title => 'Должность', #128
    company => 'МУП "Уфаводоканал"', #64
    department => 'Подразделение', #64
    description => 'Полное подразделение', #1024
    employeeID => '54321', #16
  ]
);

if ($mesg->code) {
  if ($mesg->code == LDAP_ALREADY_EXISTS) { say 'Login duplicate!'; }
  die "create error ".$mesg->error;
}
#}

$ldap->unbind;

exit 0;


