#!/usr/bin/perl

use strict;
use warnings;

use Perl6::Say;
use File::Slurp;
require Module::Install::Repository;
my $content=read_file('Makefile.PL') or die "Cannot find 'Makefile.PL'";
if ($content =~ /use inc::Module::Install/) {
  die "Module::Install is used, no need to upgrade";
}
if ($content !~ /use ExtUtils::MakeMaker/ or $content !~ /WriteMakefile\s+\(/) {
  die "ExtUtils::MakeMaker is not used";
}
