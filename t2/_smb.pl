#!/usr/bin/perl

use strict;
use warnings;
use v5.12;
use utf8;

say "start smbclient";
my $r = system("smbclient //smbserver/dbf -U user%pass -W DOMAIN -c 'get persons.dbf'");
say "result is: $r";
say "smbclient finished, resultcode is: $?";
