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
if ($content =~ /WriteMakefile1\s+\(/) {
  say "Upgrade is already applied";
  exit;
}
if ($content !~ /use ExtUtils::MakeMaker/ or $content !~ /WriteMakefile\s*\(/) {
  die "ExtUtils::MakeMaker is not used";
}

my $compat_layer=<<'EOT';
sub WriteMakefile1 {  #Written by Alexandr Ciornii, version 0.20
    my %params=@_;
    my $eumm_version=$ExtUtils::MakeMaker::VERSION;
    $eumm_version=eval $eumm_version;
    die "EXTRA_META is deprecated" if exists $params{EXTRA_META};
    die "License not specified" if not exists $params{LICENSE};
    if ($params{BUILD_REQUIRES}) { #and $eumm_version < 6.5503
        #Should be modified in future when EUMM will
        #correctly support BUILD_REQUIRES.
        #EUMM 6.5502 has problems with BUILD_REQUIRES
        $params{PREREQ_PM}={ %{$params{PREREQ_PM} || {}} , %{$params{BUILD_REQUIRES}} };
        delete $params{BUILD_REQUIRES};
    }
    delete $params{CONFIGURE_REQUIRES} if $eumm_version < 6.52;
    delete $params{MIN_PERL_VERSION} if $eumm_version < 6.48;
    delete $params{META_MERGE} if $eumm_version < 6.46;
    delete $params{META_ADD} if $eumm_version < 6.46;
    delete $params{LICENSE} if $eumm_version < 6.31;
    delete $params{AUTHOR} if $] < 5.005;
    delete $params{ABSTRACT_FROM} if $] < 5.005;
    delete $params{BINARY_LOCATION} if $] < 5.005;
    
    WriteMakefile(%params);
}
EOT

$content=~s/[\r\n]+//s;
$content.="\n\n$compat_layer";


rename('Makefile.PL','Makefile.PL.bak');
write_file('Makefile.PL',$content);
