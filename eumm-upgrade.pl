#!/usr/bin/perl

use 5.006;
use strict;
use warnings;

#License: GPL (may change in the future)

#use Perl6::Say;
use File::Slurp;
#require Module::Install::Repository;
#require Module::Install::Metadata;
use Text::FindIndent 0.08;
use Perl::Meta;

my $content=read_file('Makefile.PL') or die "Cannot find 'Makefile.PL'";
if ($content =~ /use inc::Module::Install/) {
  die "Module::Install is used, no need to upgrade";
}
if ($content =~ /WriteMakefile1\s*\(/) {
  print "Upgrade is already applied\n";
  exit;
}
if ($content !~ /\b(?:use|require) ExtUtils::MakeMaker/ or $content !~ /WriteMakefile\s*\(/) {
  die "ExtUtils::MakeMaker is not used";
}

sub process_file {
  my $content=shift;
  my $indentation_type = Text::FindIndent->parse($content,first_level_indent_only=>1);
  my $space_to_use;
  my $indent_str;
  if ($indentation_type =~ /^[sm](\d+)/) {
    print "Indentation with $1 spaces\n";
    $space_to_use=$1;
    $indent_str=' 'x$space_to_use;
  } elsif ($indentation_type =~ /^t(\d+)/) {
    print "Indentation with tabs, a tab should indent by $1 characters\n";
    $space_to_use=0;
    $indent_str="\t";
  } else {
    print "Indentation unknown, will use 4 spaces\n";
    $space_to_use=4;
    $indent_str=' 'x4;
  }

  sub apply_indent {
    my $content=shift;
    my $i_from=shift || die;
    my $i_to=shift;
    sub _do_replace {
      my $spaces=shift;
      my $i_from=shift;
      my $indent_str=shift;
      my $len=length($spaces);
      my $l1=int($len/$i_from);
      return $indent_str x $l1;
    }
    $content=~s/^((?:[ ]{$i_from})+)/_do_replace($1,$i_from,$indent_str)/emg;
    return $content;
  }

  my $compat_layer=<<'EOT';
sub WriteMakefile1 {  #Compatibility code for old versions of EU::MM. Written by Alexandr Ciornii, version 0.23. Added by eumm-upgrade.
    my %params=@_;
    my $eumm_version=$ExtUtils::MakeMaker::VERSION;
    $eumm_version=eval $eumm_version;
    die "EXTRA_META is deprecated" if exists $params{EXTRA_META};
    die "License not specified" if not exists $params{LICENSE};
    if ($params{AUTHOR} and ref($params{AUTHOR}) eq 'ARRAY' and $eumm_version < 6.5705) {
        $params{META_ADD}->{author}=$params{AUTHOR};
        $params{AUTHOR}=join(', ',@{$params{AUTHOR}});
    }
    if ($params{TEST_REQUIRES} and $eumm_version < 6.64) {
        $params{BUILD_REQUIRES}={ %{$params{BUILD_REQUIRES} || {}},
            %{$params{TEST_REQUIRES}} };
        delete $params{TEST_REQUIRES};
    }
    if ($params{BUILD_REQUIRES} and $eumm_version < 6.5503) {
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
  $content=~s/(WriteMakefile\()(\S)/$1\n$indent_str$2/;
  use App::EUMM::Upgrade;
  $content=remove_conditional_code($content,$indent_str);
  my @param;

  my @resourses;
  my $repo = Module::Install::Repository::_find_repo(\&Module::Install::Repository::_execute);
  if ($repo and $repo=~m#://#) {
    print "Repository found: $repo\n";
    eval {
      require Github::Fork::Parent;
      $repo=Github::Fork::Parent::github_parent($repo);

    };
    push @resourses,"${space}${space}${space}repository => '$repo',";
  } else {
    push @resourses,"${space}${space}${space}#repository => 'URL to repository here',";
  }

  if ($content=~/\bVERSION_FROM['"]?\s*=>\s*['"]([^'"\n]+)['"]/) {
    my $main_file=$1;
    my $main_file_content=eval { read_file($1) };
    if (!$main_file_content) {
      print "Cannot open $main_file\n";
    } else {
      my @links=Perl::Meta::extract_bugtracker($main_file_content);
      if (@links==1) {
        my $bt=$links[0];
        print "Bugtracker found: $bt\n";
        push @resourses,"${space}${space}${space}bugtracker => '$bt',";
      } elsif (@links>1) {
        print "Too many links to bugtrackers found in $main_file\n";
      }
      if ($content !~ /\bLICENSE\s*=>\s*['"]/ and $content !~ /'LICENSE'\s*=>\s*['"]/) {
        my $l=Perl::Meta::_extract_license($main_file_content);
        if ($l) {
          push @param,"    LICENSE => '$l',\n";
        } else {
          print "license not found\n";
        }
      }
      if ($content !~ /\bMIN_PERL_VERSION['"]?\s*=>\s*['"]?\d/) {
        my $version=Perl::Meta::_extract_perl_version($main_file_content) ||
          Perl::Meta::_extract_perl_version($content);
        if ($version) {
          push @param,"    MIN_PERL_VERSION => '$version',\n";
        }
      }
    }
  } else {
    print "VERSION_FROM not found\n";
    if ($content !~ /\bMIN_PERL_VERSION\s*=>\s*['"\d]/) {
      my $version=Perl::Meta::_extract_perl_version($content);
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

  if ($content !~ /\bCONFIGURE_REQUIRES['"]?\s*=>\s*\{/) {
    push @param,"    #CONFIGURE_REQUIRES => {\n"."    #},\n";
  }
 
  if ($content !~ /\bBUILD_REQUIRES['"]?\s*=>\s*\{/) {
    push @param,"    #BUILD_REQUIRES => {\n"."    #},\n";
  }

  if ($content !~ /\bTEST_REQUIRES['"]?\s*=>\s*\{/) {
    push @param,"    #TEST_REQUIRES => {\n"."    #},\n";
  }
  
  my $param='';
  if (@param) {
    $param="\n".join('',@param);
    $param=apply_indent($param,4,$space_to_use);
    $param=~s/\s+$/\n/s;
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

eumm-upgrade is a tool to allow using new features of ExtUtils::MakeMaker without losing
compatibility with older versions. It adds compatibility code to Makefile.PL and
tries to automatically detect some properties like license, minimum Perl version required and
repository used.

Just run eumm-upgrade.pl in directory with Makefile.PL. Old file will be copied to Makefile.PL.bak.
If you use Github, Internet connection is required.

You need to check resulting Makefile.PL manually as transformation is done
with regular expressions.

If you need to declare number of spaces in indent in Makefile.PL, use following string at start of
it (set 'c-basic-offset' to your value):

# -*- mode: perl; c-basic-offset: 4; indent-tabs-mode: nil; -*-

(c) Alexandr Ciornii
=cut

package Module::Install::Repository;
#by Tatsuhiko Miyagawa
#See Module::Install::Repository for copyright


sub _execute {
    my ($command) = @_;
    `$command`;
}

sub _find_repo {
    my ($execute) = @_;

    if (-e ".git") {
        # TODO support remote besides 'origin'?
        if ($execute->('git remote show -n origin') =~ /URL: (.*)$/m) {
            # XXX Make it public clone URL, but this only works with github
            my $git_url = $1;
            $git_url =~ s![\w\-]+\@([^:]+):!git://$1/!;
            return $git_url;
        } elsif ($execute->('git svn info') =~ /URL: (.*)$/m) {
            return $1;
        }
    } elsif (-e ".svn") {
        if (`svn info` =~ /URL: (.*)$/m) {
            return $1;
        }
    } elsif (-e "_darcs") {
        # defaultrepo is better, but that is more likely to be ssh, not http
        if (my $query_repo = `darcs query repo`) {
            if ($query_repo =~ m!Default Remote: (http://.+)!) {
                return $1;
            }
        }

        open my $handle, '<', '_darcs/prefs/repos' or return;
        while (<$handle>) {
            chomp;
            return $_ if m!^http://!;
        }
    } elsif (-e ".hg") {
        if ($execute->('hg paths') =~ /default = (.*)$/m) {
            my $mercurial_url = $1;
            $mercurial_url =~ s!^ssh://hg\@(bitbucket\.org/)!https://$1!;
            return $mercurial_url;
        }
    } elsif (-e "$ENV{HOME}/.svk") {
        # Is there an explicit way to check if it's an svk checkout?
        my $svk_info = `svk info` or return;
        SVK_INFO: {
            if ($svk_info =~ /Mirrored From: (.*), Rev\./) {
                return $1;
            }

            if ($svk_info =~ m!Merged From: (/mirror/.*), Rev\.!) {
                $svk_info = `svk info /$1` or return;
                redo SVK_INFO;
            }
        }

        return;
    }
}

1;
