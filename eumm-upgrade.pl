#!/usr/bin/perl

use 5.006;
use strict;
use warnings;

#License: GPL (may change in the future)

#use Perl6::Say;
use File::Slurp;
#require Module::Install::Repository;
#require Module::Install::Metadata;
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
sub WriteMakefile1 {  #Written by Alexandr Ciornii, version 0.21. Added by eumm-upgrade.
    my %params=@_;
    my $eumm_version=$ExtUtils::MakeMaker::VERSION;
    $eumm_version=eval $eumm_version;
    die "EXTRA_META is deprecated" if exists $params{EXTRA_META};
    die "License not specified" if not exists $params{LICENSE};
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
  $content=~s/
  \(\s*\$\]\s*>=\s*5\.005\s*\?\s*(?:\#\#\s*\QAdd these new keywords supported since 5.005\E\s*)?
  \s+\(\s*ABSTRACT(?:_FROM)?\s*=>\s*'([^'\n]+)',\s*(?:\#\s*\Qretrieve abstract from module\E\s*)?
  \s+AUTHOR\s*=>\s*'([^'\n]+)'
  \s*\)\s*\Q: ()\E\s*\),\s+
  /ABSTRACT_FROM => '$1',\n${space}AUTHOR => '$2',\n/sx;

  $content=~s/
          \(\s*\$ ExtUtils::MakeMaker::VERSION\s+
          (?:ge\s+' [\d\._]+ ' \s* | >=?\s*[\d\._]+\s+)\?\s+\(\E \s*
          ( [^()]+? ) \s*
          \)\s*\:\s*\(\)\s*\),
  /$space$1/sxg;

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
      require Github::Fork::Parent;
      $repo=Github::Fork::Parent::github_parent($repo);

    };
    push @resourses,"${space}${space}${space}repository => '$repo',";
  }

  if ($content=~/\bVERSION_FROM['"]?\s*=>\s*['"]([^'"\n]+)['"]/) {
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

package Module::Install::Metadata;
#by Adam Kennedy and Alexandr Ciornii
#See Module::Install for copyright

sub _extract_perl_version {
	if (
		$_[0] =~ m/
		^\s*
		(?:use|require) \s*
		v?
		([\d_\.]+)
		\s* ;
		/ixms
	) {
		my $perl_version = $1;
		$perl_version =~ s{_}{}g;
		return $perl_version;
	} else {
		return;
	}
}

sub _extract_license {
	if (
		$_[0] =~ m/
		(
			=head \d \s+
			(?:licen[cs]e|licensing|copyrights?|legal)\b
			.*?
		)
		(=head\\d.*|=cut.*|)
		\z
	/ixms ) {
		my $license_text = $1;
		my @phrases      = (
			'under the same (?:terms|license) as (?:perl|the perl programming language)' => 'perl', 1,
			'GNU general public license'         => 'gpl',         1,
			'GNU public license'                 => 'gpl',         1,
			'GNU lesser general public license'  => 'lgpl',        1,
			'GNU lesser public license'          => 'lgpl',        1,
			'GNU library general public license' => 'lgpl',        1,
			'GNU library public license'         => 'lgpl',        1,
			'BSD license'                        => 'bsd',         1,
			'Artistic license'                   => 'artistic',    1,
			'GPL'                                => 'gpl',         1,
			'LGPL'                               => 'lgpl',        1,
			'BSD'                                => 'bsd',         1,
			'Artistic'                           => 'artistic',    1,
			'MIT'                                => 'mit',         1,
			'proprietary'                        => 'proprietary', 0,
		);
		while ( my ($pattern, $license, $osi) = splice(@phrases, 0, 3) ) {
			$pattern =~ s#\s+#\\s+#g;
			if ( $license_text =~ /\b$pattern\b/i ) {
			        return $license;
			}
		}
	} else {
	        return;
	}
}

sub _extract_bugtracker {
	my @links   = $_[0] =~ m#L<(
	 \Qhttp://rt.cpan.org/\E[^>]+|
	 \Qhttp://github.com/\E[\w_]+/[\w_]+/issues|
	 \Qhttp://code.google.com/p/\E[\w_\-]+/issues/list
	 )>#gx;
	my %links;
	@links{@links}=();
	@links=keys %links;
	return @links;
}

1;

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
