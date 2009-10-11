#!/usr/bin/perl

use strict;
use warnings;

use Perl6::Say;
use File::Slurp;
require Module::Install::Repository;
require Module::Install::Metadata;
my $content=read_file('Makefile.PL') or die "Cannot find 'Makefile.PL'";
if ($content =~ /use inc::Module::Install/) {
  die "Module::Install is used, no need to upgrade";
}
if ($content =~ /WriteMakefile1\s*\(/) {
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
my $space=' 'x4;
$content=~s/
\(\$\]\s*>=\s*5\.005\s*\?\s*\#\#\s*\QAdd these new keywords supported since 5.005\E\s*
\s+\Q(ABSTRACT_FROM  => '\E([^'\n]+)',\s*\#\s*\Qretrieve abstract from module\E\s*
\s+AUTHOR\s*=>\s*'([^'\n]+)\Q') : ()),\E\s+
/ABSTRACT_FROM => '$1',\n${space}AUTHOR => '$2',\n/sx;

my @param;

my @resourses;
my $repo = Module::Install::Repository::_find_repo(\&Module::Install::Repository::_execute);
if ($repo and $repo=~m#://#) {
  print "Repository found: $repo\n";
  push @resourses,"${space}${space}${space}repository => '$repo',";
}

if ($content=~/VERSION_FROM\s*=>\s*'([^'\n]+)'/) {
  my $main_file=$1;
  my $main_file_content=eval { read_file($1) };
  if (!$main_file_content) {
    print "Cannot open $main_file\n";
  } else {
    my @links=Module::Install::Metadata::_extract_bugtracker($main_file_content);
    if (@links==1) {
      my $bt=$links[0];
      print "Bugtracker found: $bt\n";
      push @resourses,"${space}${space}${space}bugtracker => '$bt',";
    } elsif (@links>1) {
      print "Too many links to bugtrackers found in $main_file\n";
    }
  }
}
if (@resourses) {
  my $res=join("\n",@resourses);
  push @param,<<EOT;
    META_MERGE => {
        resources => {
$res
        },
    },
EOT
}
my $param='';
if (@param) {
  $param="\n".join('',@param);
  $param=~s/\s+$//s;
}
$content=~s/WriteMakefile\s*\(/WriteMakefile1($param/s;

$content=~s/[\r\n]+$//s;
$content.="\n\n$compat_layer";


rename('Makefile.PL','Makefile.PL.bak');
write_file('Makefile.PL',$content);
