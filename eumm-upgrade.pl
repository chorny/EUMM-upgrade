#!/usr/bin/perl

use strict;
use warnings;

use Perl6::Say;
use File::Slurp;
require Module::Install::Repository;
my $content=read_file('Makefile.PL') or die "Cannot find 'Makefile.PL'";
