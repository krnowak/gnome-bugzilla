#!/usr/bin/perl -w

use strict;
use lib qw(. lib);

$ENV{'QUERY_STRING'} = join('|', @ARGV);
do 'add-version.cgi' || die $@;
