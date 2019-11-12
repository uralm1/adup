#!/usr/bin/perl

use strict;
use warnings;
use v5.12;
use utf8;

#my $fio = "Хас-нов Ур-л флю-рович Оглы";
#my $fio = "Байрамов Фарит Фазилович ";
my $fio = "Хас-нов";

my $cn;
if ($fio =~ m/^\s*(\S+)\s*(\S*)\s*\b(.*)\b\s*$/) { # we have do do it to reset all $N variables

  say "**\u\L$1**";
  say "**\u\L$2**";
  say "**\u$3**";

  $cn = join(' ', grep $_, "\u\L$1", "\u\L$2", "\u$3", undef, '', "asd");
}
say "**$cn**";
