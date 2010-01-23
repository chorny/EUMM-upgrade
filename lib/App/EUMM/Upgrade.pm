package App::EUMM::Upgrade;

use strict;
use warnings;

=head1 NAME

App::EUMM::Upgrade - Perl tool to upgrade ExtUtils::MakeMaker-based Makefile.PL

=head1 VERSION

Version 0.22

=cut

our $VERSION = '0.22_01';


=head1 SYNOPSIS

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

=head1 new EUMM features

LICENSE - shows license on search.cpan.org

META_MERGE - add something (like repository URL or bugtracker UTL) to META.yml. Repository and
bugtracker URL are used on search.cpan.org.

MIN_PERL_VERSION - minimum version of Perl required for module work. Not used currently, but will
be in the future.

CONFIGURE_REQUIRES - modules that are used in Makefile.PL and should be installed before running it.

BUILD_REQUIRES - modules that are used in installation and testing, but are not required by module
itself. Useful for ppm/OS package generaton and metadata parsing tools.

=head1 AUTHOR

Alexandr Ciornii, C<< <alexchorny at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-app-eumm-upgrade at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=App-EUMM-Upgrade>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc App::EUMM::Upgrade


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=App-EUMM-Upgrade>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/App-EUMM-Upgrade>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/App-EUMM-Upgrade>

=item * Search CPAN

L<http://search.cpan.org/dist/App-EUMM-Upgrade/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 COPYRIGHT & LICENSE

Copyright 2009 Alexandr Ciornii.

GPL v3

=cut
use Exporter 'import';
our @EXPORT=qw/remove_conditional_code/;
sub _indent_space_number {
  my $str=shift;
  $str=~/^(\s+)/ or return 0;
  my $ind=$1; 
  $ind=~s/\t/        /gs;
  return length($ind);
}

sub _unindent_t {
#  my $replace
#  die unless
}
sub _unindent {
  my $space_string_to_set=shift;
  my $text=shift;
  print "#'$space_string_to_set','$text'\n";
  my @lines=split /(?<=[\x0A\x0D])/s,$text;
  use List::Util qw/min/;
  my $minspace=min(map {_indent_space_number($_)} @lines);
  my $s1=_indent_space_number($space_string_to_set);
  die "$s1 > $minspace" if $s1 > $minspace;
  return $text if $s1==$minspace;
  #if (grep { $_ !~ /^$space_string_to_set/ } @lines) {
    
  #}
  #my $space_str
  my $line;
  foreach my $l (@lines) {
    next unless $l;
    unless ($l=~s/^$space_string_to_set//) {
      die "Text (line '$l') does not start with removal line ($space_string_to_set)";
    }
    next unless $l;
    if ($l=~m/^(\s+)/) {
      my $space=$1;
      if (!defined $line) {
        $line=$space;
        next;
      } else {
        if ($space=~/^$line/) {
          next;
        } elsif ($line=~/^$space/) {
          $line=$space;
          if ($line eq '') {
            #warn("line set to '' on line '$l'");
          }
        } else {
          die "Cannot find common start, on line '$l'";
        }
      }
    } else {
      return $text;
    }
  }
  if (!$line) {
    die "Cannot find common start";
  }
  foreach my $l (@lines) {
    next unless $l;
    unless ($l=~s/^$line//) {
      die "Text (line '$l') does not start with calculated removal line ($space_string_to_set)";
    }
    $l="$space_string_to_set$l";
  }
  return (join("",@lines)."");

  #foreach
  #$text=~s/^(\s+)(\S)/_unindent_t(qq{$1},qq{$space_string_to_set}).qq{$2}/egm;
  
  #my $style=shift;
}

sub remove_conditional_code {
  my $content=shift;
  my $space=shift;
  $content=~s/(WriteMakefile\()(\S)/$1\n$space$2/;

  $content=~s/
  \(\s*\$\]\s*>=\s*5\.005\s*\?\s*(?:\#\#\s*\QAdd these new keywords supported since 5.005\E\s*)?
  \s+\(\s*ABSTRACT(?:_FROM)?\s*=>\s*'([^'\n]+)',\s*(?:\#\s*\Qretrieve abstract from module\E\s*)?
  \s+AUTHOR\s*=>\s*'([^'\n]+)'
  \s*\)\s*\Q: ()\E\s*\),\s+
  /ABSTRACT_FROM => '$1',\n${space}AUTHOR => '$2',\n/sx;

  $content=~s/
          ^(\s*)\(\s*\$ ExtUtils::MakeMaker::VERSION\s+
          (?:ge\s+' [\d\._]+ ' \s* | >=?\s*[\d\._]+\s+)\?\s+\(\E\s*[\n\r]
          ( [ \t]*[^()]+? ) #main text, should not contain ()
           \s*
          \)\s*\:\s*\(\)\s*\),
  /_unindent($1,$2)/msxge;

  $content=~s/
          \(\s*\$\]\s* \Q>=\E \s* 5[\d\._]+ \s* \Q? (\E \s+
          ( [^()]+? ) \s+
          \)\s*\:\s*\(\)\s*\),
  /$1/sxg;
  return $content;
}

1; # End of App::EUMM::Upgrade
