#!/usr/local/bin/perl

# Comments:
#  Reads comma delimited input files containing PR numbers and grabs
#  relevant data from the associated Bugzilla page and enters it 
#  into the database.

# (C) Copyright ParaSoft Corporation 2003.  All rights reserved.
# THIS IS UNPUBLISHED PROPRIETARY SOURCE CODE OF ParaSoft
# The copyright notice above does not evidence any
# actual or intended publication of such source code.

# $Author: jwilkes $          $Locker:  $
# $Date: 2006/08/04 23:23:33 $
# $Log: populate_db.pl,v $
# Revision 1.6  2006/08/04 23:23:33  jwilkes
# Tabs -> spaces
#
# Revision 1.5  2006/08/04 23:21:06  jwilkes
# Code Review:
#   Moved a lot of code around.
#   Added debug printing (-d).
#   Added echo_only option (-n).
#   Do not die partway through processing bugs.
#
# Revision 1.4  2006/08/02 17:38:22  jwilkes
# Doh.  LWP::Simple is used!
#
# Revision 1.3  2006/08/01 23:10:45  jwilkes
# Removed extraneous reference to LWP.
# Also, nuked contractions that confuse my emacs syntax highlighter.
#
# Revision 1.2  2006/07/05 20:00:13  jhearn
# Normalized variable names and heading comments for all batzilla files.
#


use strict;
use warnings;
use IO::File;
use DBI;
use LWP::Simple;

my $bugzilla_host = "camel.parasoft.com";
#my $sql_db_host = "dev3";
my $sql_db_host = "camel.parasoft.com";
my $sql_db = "DBI:mysql:database=fixes";
my $sql_db_table = "fixes.fixes";
my $sql_dbh = ();
my $sql_user = "bats";
my $sql_password = "batmantis00";
my $fh = new IO::File;

my @bugs = ();
my $debug_level = 0;
my $echo_only = 0;


sub debug_print {
    my $level = shift @_;
    if ($level <= $debug_level) {
        print "@_\n";
    }
}

# Get PR information from webpage and enter in database
sub process_bug {
    my $bug_id = shift @_;
    debug_print(1, "\n\n---Processing $bug_id---");

    # URL of Bugzilla Problem Report page.
    my $bug_url = "http://$bugzilla_host/bugzilla/show_bug.cgi?id=$bug_id";
    
    # Get Bugzilla HTML
    my $bug_html = LWP::Simple::get $bug_url;

    # quick check to see if there are any 'ci ' lines in the pr
    my $quick_ci_pattern = "\\bci\\s";
    unless ($bug_html =~ /$quick_ci_pattern/) {
        debug_print(1, "$bug_id does not contain 'ci '");
        return;
    }
    debug_print(4, "bug_html is $bug_html");

    # Parse bug html, line by line
    my $default_committer;
    my $comment_seen_and_mailto_not_yet_processed = 0;
    foreach my $line (split(/\n/, $bug_html)) {
        # Get Committer from email link in comment headers.
        # Hack! Hack! Hack! - this depends on bugzilla formatting comments
        # exactly so
        if ($line =~ /------- <i>Comment/) {
            $comment_seen_and_mailto_not_yet_processed = 1;
        }
        if ($comment_seen_and_mailto_not_yet_processed &&
            $line =~ /mailto:(\w+)&#64;parasoft\.com/) {
            $default_committer = $1;
            $comment_seen_and_mailto_not_yet_processed = 0;
            debug_print(3, "default_committer is $default_committer");
        }

        unless ($line =~ /$quick_ci_pattern/) {
            debug_print(5, "$line does not contain 'ci '");
            next;
        }

        # This line contains "ci "

        # Ignore files in "/tests" directory.
        if ($line =~ /tests/) {
            debug_print(3, "line contains tests; skipping: $line");
            next;
        }

        # Parse "ci " line.
        my $slow_ci_pattern = "((\\w+)\\s|-)?ci\\s(\\S+)\\s((?i)NONE|(?:\\d*\\.)*\\d+)\\s(.+(?:19|20)\\d\\d)";
        if ($line =~ /^$slow_ci_pattern$/) {
            # Look for anchored expression first; this is the common case
            debug_print(1, " Found ci line: $line");
        } else {
            # hmm... the expected line did not match, try harder
            if ($line =~ /$slow_ci_pattern/) {
                # some ci lines are prefixed by html tag
                debug_print(1, " Found hard to find ci line: $line");
            } else {
                # perhaps this line was truncated / wrapped?  nyi
                debug_print(1, " Giving up on supposed ci line: $line");
                next;
            }
        }
        # little, nyi: handle
        # -ci edg/src/statements.c 1.16 Thu Jan 27 14:07:51 2005
        # to mean "delete edg/src/statements.c from the fixes for this pr"
        #my $remove = 1 if ($1 =~ /-/); # <-- nyi
        my $committer = $default_committer;
        $committer = $2 if defined($2) && $2;
        my $file = $3;
        my $revision = $4;
        my $date = $5;
        my $devtest = 0;
        my $insrel = 0;
        
        # Using IGNORE with "primary key(pr, file, revision)" ensures 
        # no duplication, but error handling is not yet implemented.
        next if ($echo_only);
        debug_print(2, " Adding to batzilla db: $bug_id, $file, $revision," .
                    " $committer, $date, $devtest, $insrel");
        my $sth = $sql_dbh->prepare_cached("INSERT IGNORE INTO $sql_db_table" . 
                                           " (pr, file, revision, committer," .
                                           " date, devtest, insrel)" .
                                           " VALUES (?, ?, ?, ?, ?, ?, ?)")
            or die "Could not prepare statement: " . $sql_dbh->errstr;
        $sth->execute($bug_id, $file, $revision, $committer,
                      $date, $devtest, $insrel)
            or die "Could not execute statement using $committer: " .
            $sql_dbh->errstr;
        $sth->finish;
    }
}

### main

foreach my $bugs_file (@ARGV) {
    if ($bugs_file =~ /-d/) {
        $debug_level += 1;
        next;
    } elsif ($bugs_file =~ /-n/) {
        $echo_only += 1;
        debug_print(0, "\n ** Will not really update the database **\n");
        next;
    }
    # Open a file containing PR numbers
    $fh->open("< $bugs_file") or die "Unable to open $bugs_file: $!\n";
    
    # Read PR numbers into a list
    # my @bug_list = split (/\s*(?:,\s)\s*/, <$fh>);
    my @bug_list = split (/(?:[,\s]+)/, <$fh>);
    debug_print(1, "PRs: @bug_list");
    foreach my $pr (@bug_list) {
        $pr =~ /^\d+$/ or 
            die "Improper problem report number found in $bugs_file: $pr $!\n";
    }
    push(@bugs, @bug_list);

    # Close file containing PR numbers
    $fh->close();
}

if (!@bugs) {
    print "No bugs to update\n";
    exit 0;
}

# Note that AutoCommit settings are ignored by the MyISAM database engine.
# All MyISAM tables behave as though AutoCommit is enabled.
$sql_dbh = DBI->connect("$sql_db;host=$sql_db_host",
                        "$sql_user", "$sql_password", 
                        {'RaiseError' => 1, AutoCommit => 1});

# Get PR information from webpage and enter in database
process_bug($_) foreach (@bugs);

# Disconnect from the database.
$sql_dbh->disconnect;

