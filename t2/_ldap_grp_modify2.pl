#!/usr/bin/perl

use strict;
use warnings;
use v5.12;
use utf8;
use Carp;
use Net::LDAP;
use Net::LDAP::Util qw(canonical_dn);
use Data::Dumper;
use Mojo::File 'path';

#binmode(STDOUT, ':utf8');

my $cfg = eval path('../test.conf')->slurp;

my $ldap = Net::LDAP->new($cfg->{ldap_servers}, port => 389, timeout => 10, version => 3);

my $mesg = $ldap->bind($cfg->{ldap_user}, password => $cfg->{ldap_pass});

my $groupdn = "CN=Тест,OU=T,$cfg->{ldap_base}";
my $res = $ldap->search(base=>$groupdn, scope=>'base', filter=>'(objectClass=Group)', attrs=>['member']);
if ($res->count > 0) {
  say "Found group: ".$res->count;
  my $entry = $res->entry(0);
  my @v = $entry->get_value('member');
  say "Member: ".canonical_dn($_) for (@v);
} else {
  say "Group not found!";
}


my $userdn = "CN=Пользователь 4,OU=testou,OU=T,$cfg->{ldap_base}";
$mesg = $ldap->modify($groupdn,
  add => { member => [ $userdn ] }
);

if ($mesg->code) {
  die "modify error ".$mesg->error;
}

$ldap->unbind;

