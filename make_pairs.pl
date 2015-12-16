#!/usr/bin/perl

# Comments:
#  Takes as input (via command line) a CVSSnapshot.pl and outputs
#  a comma-newline delimitted list of file/revision pairs in INSREL 
#  at the time the snapshot was taken.

# (C) Copyright ParaSoft Corporation 2003.  All rights reserved.
# THIS IS UNPUBLISHED PROPRIETARY SOURCE CODE OF ParaSoft
# The copyright notice above does not evidence any
# actual or intended publication of such source code.

# $Author: jhearn $          $Locker:  $
# $Date: 2006/08/09 20:06:33 $
# $Log: make_pairs.pl,v $
# Revision 1.4  2006/08/09 20:06:33  jhearn
# *** empty log message ***
#
# Revision 1.3  2006/08/08 20:58:25  jhearn
# Stylistic code changes based on feedback given by jwilkes during code review.
#
# Revision 1.1.1.1  2006/07/26 18:23:16  temp
# batzilla
#
# Revision 1.2  2006/07/05 20:00:01  jhearn
# Normalized variable names and heading comments for all batzilla files.
#

use strict;
use warnings;
use IO::File;

my $fh = new IO::File;                      # Filehandle
my $path;
my $file;
my $revision;

foreach (@ARGV) {
    # Open a snapshot
    $fh->open("< $_") or die "Unable to open $_: $!\n";
    
    while (<$fh>) {
        if ($_ =~ /^#\s=+\s(\S+)\s=+/) {
            $path = $1;
        } elsif ($_ =~ m{^/(\S+)/([\d\.]+)/.*/.*/T\d+(.\d+)+}) {
            $file = $1;
            $revision = $2;
            print qq{$path/$file,$revision\n};
        }
    }
}
