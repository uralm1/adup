#!/usr/bin/perl

use strict;
use warnings;
use v5.12;
use utf8;
use Carp;
use Net::LDAP;
use Net::LDAP::Util qw(canonical_dn);
use Data::Dumper;

#binmode(STDOUT, ':utf8');

my $ldapservers = ['ldap://dcsrv'];
my $ldapuser = 'user';
my $ldappass = 'pass';
my $ldapbase = 'DC=contoso,DC=local';

my $ldap = Net::LDAP->new($ldapservers, port => 389, timeout => 10, version => 3);

my $mesg = $ldap->bind($ldapuser, password => $ldappass);

my $groupdn = "CN=Тест,OU=T,$ldapbase";
my $res = $ldap->search(base=>$groupdn, scope=>'base', filter=>'(objectClass=Group)', attrs=>['member']);
if ($res->count > 0) {
  say "Found group: ".$res->count;
  my $entry = $res->entry(0);
  my @v = $entry->get_value('member');
  say "Member: ".canonical_dn($_) for (@v);
} else {
  say "Group not found!";
}


my $userdn = "CN=Пользователь 4,OU=testou,OU=T,$ldapbase";
$mesg = $ldap->modify($groupdn,
  add => { member => [ $userdn ] }
);

if ($mesg->code) {
  die "modify error ".$mesg->error;
}

$ldap->unbind;

