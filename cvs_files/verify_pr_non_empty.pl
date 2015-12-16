#!/usr/local/bin/perl
use strict;
use warnings;
use IO::File;

my $fh = new IO::File;
$fh->open("< $ARGV[0]") 
  or die "Unable to open $ARGV[1]: $!\n";

while (<$fh>) {
    if (/^PRs[:\s]\s*([\s,\d]+)/) {
        die "BAD LOG MESSAGE:\n  \"PRs:\" must be followed by a PR number.  Try removing \"PRs:\" or specifying a PR number.\n" 
          unless (defined($1) && ($1 =~ /^\d+(,*\s+\d+)*/));
    }
}

