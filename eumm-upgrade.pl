#!/usr/bin/perl

use strict;
use warnings;

#License: GPL (may change in the future)

#use Perl6::Say;
use File::Slurp;
require Module::Install::Repository;
require Module::Install::Metadata;
use Text::FindIndent;

my $content=read_file('Makefile.PL') or die "Cannot find 'Makefile.PL'";
if ($content =~ /use inc::Module::Install/) {
  die "Module::Install is used, no need to upgrade";
}
if ($content =~ /WriteMakefile1\s*\(/) {
  print "Upgrade is already applied\n";
  exit;
}
if ($content !~ /use ExtUtils::MakeMaker/ or $content !~ /WriteMakefile\s*\(/) {
  die "ExtUtils::MakeMaker is not used";
}

sub process_file {
  my $content=shift;
  my $indentation_type = Text::FindIndent->parse($content);
  my $space_to_use;
  if ($indentation_type =~ /^[sm](\d+)/) {
    print "Indentation with $1 spaces\n";
    $space_to_use=$1;
  } elsif ($indentation_type =~ /^t(\d+)/) {
    print "Indentation with tabs, a tab should indent by $1 characters\n";
    $space_to_use=0;
  } else {
    print "Indentation unknown, will use 4 spaces\n";
    $space_to_use=4;
  }

  sub apply_indent {
    my $content=shift;
    my $i_from=shift || die;
    my $i_to=shift;
    sub _do_replace {
      my $spaces=shift;
      my $i_from=shift;
      my $i_to=shift;
      my $len=length($spaces);
      my $l1=int($len/$i_from);
      if ($i_to==0) {
        return "\t"x$l1;
      } else {
        return " " x ($l1*$i_to);
      }
    }
    $content=~s/^((?:[ ]{$i_from})+)/_do_replace($1,$i_from,$i_to)/emg;
    return $content;
  }

  my $compat_layer=<<'EOT';
sub WriteMakefile1 {  #Written by Alexandr Ciornii, version 0.20. Added by eumm-upgrade.
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

  $content=~s/
          \(\s*\$ ExtUtils::MakeMaker::VERSION\s+
          (?:ge\s+'\E [\d\._]+ ' | >=?\s*[\d\._]+)\s+\Q? (\E \s*
          ( [^()]+? ) \s*
          \)\s*\:\s*\(\)\s*\),
  /$1/sxg;
    #($ExtUtils::MakeMaker::VERSION >= 6.3002
    #    ? ('LICENSE' => 'perl')
    #    : ()),

  $content=~s/
          \(\s*\$\]\s* \Q>=\E \s* 5[\d\._]+ \s* \Q? (\E \s+
          ( [^()]+? ) \s+
          \)\s*\:\s*\(\)\s*\),
  /$1/sxg;

  my @param;

  my @resourses;
  my $repo = Module::Install::Repository::_find_repo(\&Module::Install::Repository::_execute);
  if ($repo and $repo=~m#://#) {
    print "Repository found: $repo\n";
    eval {
      require NGP;
      $repo=NGP::github_parent($repo);

    };
    push @resourses,"${space}${space}${space}repository => '$repo',";
  }

  if ($content=~/\bVERSION_FROM['"]?\s*=>\s*'([^'\n]+)'/) {
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
      if ($content !~ /\bLICENSE\s*=>\s*['"]/ and $content !~ /'LICENSE'\s*=>\s*['"]/) {
        my $l=Module::Install::Metadata::_extract_license($main_file_content);
        if ($l) {
          push @param,"    LICENSE => '$l',\n";
        }
      }
      if ($content !~ /\bMIN_PERL_VERSION\s*=>\s*['"]/) {
        my $version=Module::Install::Metadata::_extract_perl_version($main_file_content) ||
          Module::Install::Metadata::_extract_perl_version($content);
        if ($version) {
          push @param,"    MIN_PERL_VERSION => '$version',\n";
        }
      }
    }
  } else {
    print "VERSION_FROM not found\n";
    if ($content !~ /\bMIN_PERL_VERSION\s*=>\s*['"\d]/) {
      my $version=Module::Install::Metadata::_extract_perl_version($content);
      if ($version) {
        push @param,"    MIN_PERL_VERSION => '$version',\n";
      }
    }
  }

  if (@resourses and $content !~ /\bMETA_MERGE\s*=>\s*\{/) {
    my $res=join("\n",@resourses);
    push @param,<<EOT;
    META_MERGE => {
        resources => {
$res
        },
    },
EOT
  }

  if ($content !~ /\bBUILD_REQUIRES\s*=>\s*\{/) {
    push @param,"    #BUILD_REQUIRES => {\n"."    #},\n";
  }
  
  my $param='';
  if (@param) {
    $param="\n".join('',@param);
    $param=apply_indent($param,4,$space_to_use);
    $param=~s/\s+$//s;
  }
  $content=~s/WriteMakefile\s*\(/WriteMakefile1($param/s;

  #$content=~s/[\r\n]+$//s;
  $compat_layer="\n\n".apply_indent($compat_layer,4,$space_to_use);
  $content=~s/(__DATA__ | $ )/$compat_layer$1/sx;
  # |
  #
  return $content;
}

rename('Makefile.PL','Makefile.PL.bak');
write_file('Makefile.PL',process_file($content));

=pod

If you need to delare number spaces in indent in Makefile.PL, use following string at start of it
(set 'c-basic-offset' to your value):

# -*- mode: perl; c-basic-offset: 4; indent-tabs-mode: nil; -*-

=cut
