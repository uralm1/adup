#!/usr/bin/perl

use strict;
use warnings;
use v5.12;
use utf8;
use Carp;
use Net::LDAP qw(LDAP_SUCCESS LDAP_INSUFFICIENT_ACCESS);
use Net::LDAP::Util qw(canonical_dn);
use Data::Dumper;

#binmode(STDOUT, ':utf8');

my $ldapservers = ['ldap://dcsrv'];
my $ldapuser = 'user';
my $ldappass = 'pass';
my $ldapbase = 'DC=contoso,DC=local';

my $ldap = Net::LDAP->new($ldapservers, port => 389, timeout => 10, version => 3);
die "LDAP creation error $@" unless($ldap);

my $mesg = $ldap->bind($ldapuser, password => $ldappass);
if ($mesg->code) {
  die "bind error ".$mesg->error;
}

my $dn = "CN=Техподдержка АСУ (OTRS),OU=11CONTACTS,OU=1,$ldapbase";
open(my $fh, '<', 'otrs.jpg') or die 'open failure';
local $/ = undef;
my $jpeg = <$fh>;
$mesg = $ldap->modify($dn,
  replace => { thumbnailPhoto => [ $jpeg ] }
);

if ($mesg->code) {
  die "modify error ".$mesg->error;
}

close $fh;
$ldap->unbind;

