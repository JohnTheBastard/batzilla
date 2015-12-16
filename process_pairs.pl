#!/usr/bin/perl

# Comments:
#  Reads comma-newline delimited input files containing file/revision
#  pairs and updates the INSREL status of matching files found in the
#  database with equal or lesser revision to "ON".

# (C) Copyright ParaSoft Corporation 2003.  All rights reserved.
# THIS IS UNPUBLISHED PROPRIETARY SOURCE CODE OF ParaSoft
# The copyright notice above does not evidence any
# actual or intended publication of such source code.

# $Author: jhearn $          $Locker:  $
# $Date: 2006/08/09 20:06:33 $
# $Log: process_pairs.pl,v $
# Revision 1.7  2006/08/09 20:06:33  jhearn
# *** empty log message ***
#
# Revision 1.6  2006/08/08 22:06:30  jhearn
# sylistic changes.
#
# Revision 1.5  2006/08/08 22:01:52  jhearn
# fixed some scoping problems introduced by style changes.
#
# Revision 1.4  2006/08/08 21:09:16  jhearn
# Stylistic changes to code based on feedback from jwilkes during code review.
#
# Revision 1.3  2006/08/08 20:58:25  jhearn
# Stylistic code changes based on feedback given by jwilkes during code review.
#
# Revision 1.1.1.1  2006/07/26 18:23:16  temp
# batzilla
#
# Revision 1.2  2006/07/05 20:00:31  jhearn
# Normalized variable names and heading comments for all batzilla files.
#

use strict;
use warnings;
use IO::File;
use DBI;
use LWP::Simple;

#my $db_host = "dev3";
my $db_host = "camel";
my $sql_user = "bats";
my $sql_password = "batmantis00";
my $sql_db = "DBI:mysql:database=fixes";
my $db_table = "fixes.fixes";
my $dbh;

sub file_in_db {
    my $sql = qq{SELECT COUNT(*) FROM $db_table WHERE file=?}; 
    my $sth = $dbh->prepare($sql) 
      or die "Couldn't prepare statement: " . $dbh->errstr;
    $sth->execute($_[0])
      or die "Couldn't execute statement on $_[0]: " . $dbh->errstr;
    my $record_count = $sth->fetch();
    $sth->finish();
    
    return $record_count->[0];
}


sub update_insrel {
    my $cv_file = $_[0];
    my $cv_revision = $_[1];
    my $cv_major;
    my $cv_minor;
    my @db_revisions;
    
    if ($cv_revision =~ /^(\d+)\.(\d+)(\.\d+)*$/) {
        $cv_major = $1;
        $cv_minor = $2;
    } else {
        die "ERROR: Bad file revision: $cv_file $cv_revision";
    }
    
    my $sql = qq{SELECT revision FROM $db_table WHERE file = ?};
    my $sth = $dbh->prepare($sql);
    
    $sth->execute($cv_file) or die "Couldn't execute statement. $!";
    # Put revisions found in database in an array
    while (my $db_rev = $sth->fetchrow()) {
        push @db_revisions, $db_rev;
    }
    
    $sql = qq{UPDATE $db_table SET insrel = 1 WHERE file = ? AND revision = ?};
    $sth = $dbh->prepare_cached($sql);
    
    foreach my $db_rev (@db_revisions) {
        if ($db_rev =~ /^(\d+)\.(\d+)(\.\d+)*/) {
            my $db_major = $1;
            my $db_minor = $2;
            #my $db_extra = $3;
            if (($cv_major > $db_major) ||
                (($cv_major = $db_major) && ($cv_minor >= $db_minor))) {
                $sth->execute($cv_file, $db_rev);
            }
        } elsif ($cv_revision =~ /none/i) {
            # This should never happen, but just in case.
            warn "WARNING: File $cv_file has been destroyed and should not be in CVS.";
        }
    }
}

### MAIN ###

my $fh = new IO::File;

# Note that AutoCommit settings are ignored by the MyISAM database engine.
# All MyISAM tables behave as though AutoCommit is enabled.
$dbh = DBI->connect("$sql_db;host=$db_host",
                    "$sql_user", "$sql_password", 
                    {'RaiseError' => 1, AutoCommit => 1});
foreach my $fr_file (@ARGV) {
    my %fr_hash;
    # Open a file containing (file,revision) pairs
    $fh->open("< $fr_file") or die "Unable to open $fr_file: $!\n";
    # Create hash of (file,revision) pairs
    foreach (<$fh>) {
        if ($_ =~ /^(\S+)\s*,\s*(\S+)/) {
            $fr_hash{$1} = $2;
        }
    }
    foreach (sort keys %fr_hash) {
        update_insrel($_, $fr_hash{$_}) if file_in_db($_);
    }
    $fh->close();
}
# Disconnect from the database.
$dbh->disconnect;
exit;
