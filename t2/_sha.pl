#!/usr/bin/perl

use strict;
use warnings;
use v5.12;
use utf8;

use Encode qw(encode_utf8);;
use Digest::SHA qw(sha256_hex);

my $d = "Отдел телекоммуникаций";
my $digest = sha256_hex(encode_utf8($d));
say $digest;

