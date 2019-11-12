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

my $dn = "CN=Хасанов Урал Флюрович,OU=Группа сетевого администрирования,OU=Служба Автоматизированных систем управления,OU=1,$cfg->{ldap_base}";
open(my $fh, '<', 'ural.jpg') or die 'open failure';
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

