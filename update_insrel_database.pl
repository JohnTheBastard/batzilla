#!/usr/bin/perl

# Comments:
#  Performs a CVS snapshot, updates the INSREL status of appropriate 
#  file/revision pairs in the database.

# (C) Copyright ParaSoft Corporation 2003.  All rights reserved.
# THIS IS UNPUBLISHED PROPRIETARY SOURCE CODE OF ParaSoft
# The copyright notice above does not evidence any
# actual or intended publication of such source code.

# $Author: jhearn $          $Locker:  $
# $Date: 2006/08/09 20:06:33 $
# $Log: update_insrel_database.pl,v $
# Revision 1.6  2006/08/09 20:06:33  jhearn
# *** empty log message ***
#
# Revision 1.5  2006/08/08 23:11:50  jhearn
# Branch revisions can no longer be marked as insrel.
#
# Revision 1.4  2006/08/08 22:01:52  jhearn
# fixed some scoping problems introduced by style changes.
#
# Revision 1.3  2006/08/08 20:58:25  jhearn
# Stylistic code changes based on feedback given by jwilkes during code review.
#
# Revision 1.1.1.1  2006/07/26 18:23:16  temp
# batzilla
#
# Revision 1.2  2006/07/05 20:01:03  jhearn
# Normalized variable names and heading comments for all batzilla files.
#


use strict;
use warnings;
use IO::File;
use DBI;
use Getopt::Std;

#my $db_host = "dev3";
my $db_host = "camel.parasoft.com";
my $sql_user = "bats";
my $sql_password = "batmantis00";
my $sql_db = "DBI:mysql:database=fixes";
my $sql_db_table = "fixes.fixes";
my $dbh;

# Flags need to be scoped "our" ... Not sure why.
our $opt_n;

sub process_snapshot {
    my $path;
    my $file_path;
    my $revision;
    my @updated_revisions;
    my %fake_update;
    my %fr_hash;
  
    foreach my $line (@_) {
        if ($line =~ m{^#\s=+\s(\S+)CVS/Entries\s=+}) {
            $path = $1;
        } elsif ($line =~ m{^/(\S+)/(\d+(\.\d+)+)/.*/.*/T\d+(.\d+)+}) {
            $file_path = $path . $1;
            $revision = $2;
            if (file_in_db($file_path)) {
                $fr_hash{$file_path} = $revision;
            }
        }
    }

    foreach my $file (sort keys %fr_hash) { 
        @updated_revisions = update_insrel($file, $fr_hash{$file});

        if ($opt_n && @updated_revisions) {
            $fake_update{$file} = [@updated_revisions];      
        }
    }
    if ($opt_n && %fake_update) {
        print "\nIf run without flag -n, the following file-revision pairs would ",
          "have had\ntheir INSREL status changed in the database:\n\n";
        foreach my $file (sort keys %fake_update) {
            foreach my $i (0 .. $#{$fake_update{$file}}) {
                # I hate using indices, but cound't figure out 
                # the syntax to dereference the hash key.
                print "$file $fake_update{$file}[$i]\n";
            }
        }
        print "\n\n";      
    }
}


sub file_in_db {
    my $sql = qq{SELECT COUNT(*) FROM $sql_db_table WHERE file=?}; 
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
    my @update;

    if ($cv_revision =~ /^(\d+)\.(\d+)$/) {
        $cv_major = $1;
        $cv_minor = $2;
    } else {
        die "ERROR: Bad file revision: $cv_file $cv_revision";
    }
  
    my $sql = qq{SELECT revision FROM $sql_db_table WHERE file = ? and insrel = '0'};
    my $sth = $dbh->prepare($sql);
  
    $sth->execute($cv_file) or die "Couldn't execute statement. $!";
    # Put revisions of file found in database in an array
    while (my $rev = $sth->fetchrow()) {
        # Don't want any branch revisions marked insrel.
        push (@db_revisions, $rev) unless ($rev =~/\d+\.\d+\.\d+/);
    }
    $sth->finish();
  
    $sql = qq{UPDATE $sql_db_table SET insrel = 1 
            WHERE file = ? AND revision = ?};
    $sth = $dbh->prepare_cached($sql);
  
    foreach my $db_rev (@db_revisions) {
        if ($db_rev =~ /^(\d+)\.(\d+)$/) {
            my $db_major = $1;
            my $db_minor = $2;      
            if (($cv_major > $db_major) ||
                (($cv_major == $db_major) && ($cv_minor >= $db_minor))) {       
                push(@update, $db_rev);
                $sth->execute($cv_file, $db_rev) unless ($opt_n);
            }
        } elsif ($cv_revision =~ /none/i) {      
            # This should never happen, but just in case.
            warn "WARNING:\nFile $cv_file has been destroyed and should not be in CVS.\n";
        } else {
            # This should never happen either.
            die "WARNING:\nUnexpected file revision found: $cv_file $db_rev\nPlease inspect database.\n";
        }
    }
    $sth->finish();
    return @update;
}

### MAIN ###

getopts("n");
# Note that AutoCommit settings are ignored by the MyISAM database engine.
# All MyISAM tables behave as though AutoCommit is enabled.
$dbh = DBI->connect("$sql_db;host=$db_host",
                    "$sql_user", "$sql_password", 
                    {
                     'RaiseError' => 1, AutoCommit => 1});
# Backticks `` execute delimited command in shell.
my @snapshot = `cvs co -rinsrel -p insight/CVSSnapshot.pl 2>/dev/null`;

process_snapshot(@snapshot);

# Disconnect from the database.
$dbh->disconnect;

exit;
