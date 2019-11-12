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
$mesg = $ldap->search(base => $dn, scope => 'base',
  filter => '(&(objectCategory=person)(objectClass=user))',
  attrs => [ 'cn','thumbnailPhoto' ],
);

if ($mesg->code) {
  die "search error ".$mesg->error;
}

if ($mesg->count == 1) {
  my $e = $mesg->entry(0);
  my $j = $e->get_value('thumbnailPhoto');

  open(my $fh, '>', '_tt.jpg') or die 'open failure';
  print $fh $j;
  close $fh;
}
$ldap->unbind;

