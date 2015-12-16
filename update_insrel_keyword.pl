#!/usr/bin/perl

# Comments:
#  Checks to see what PRs have all associated files in INSREL and
#  adds the keyword "insrel" to the PR pages where appropriate.

# (C) Copyright ParaSoft Corporation 2003.  All rights reserved.
# THIS IS UNPUBLISHED PROPRIETARY SOURCE CODE OF ParaSoft
# The copyright notice above does not evidence any
# actual or intended publication of such source code.

# $Author: jhearn $          $Locker:  $
# $Date: 2006/08/09 20:06:33 $
# $Log: update_insrel_keyword.pl,v $
# Revision 1.7  2006/08/09 20:06:33  jhearn
# *** empty log message ***
#
# Revision 1.6  2006/08/08 21:56:12  jhearn
# Fixed problem where PRs with no fix submitted were getting inrel keyword
# added.
#
# Revision 1.5  2006/08/08 20:58:25  jhearn
# Stylistic code changes based on feedback given by jwilkes during code review.
#
# Revision 1.1.1.1  2006/07/26 18:23:16  temp
# batzilla
#
# Revision 1.4  2006/07/05 20:01:17  jhearn
# Normalized variable names and heading comments for all batzilla files.
#


use strict;
use warnings;
use IO::File;
use DBI;
use LWP::UserAgent;
use URI;
use Getopt::Std;

my $db_host = "camel";
my $bugzilla_host = "camel";
my $domain = "parasoft.com";
my $bug_user = "batzilla";
my $bug_password = "batsbugs";
my $sql_user = "bats";
my $sql_password = "batmantis00";
my $sql_db = "DBI:mysql:database=fixes";
my $sql_db_table = "fixes.fixes";
my $dbh;

# Flags need to be scoped "our" ... Not sure why.
our $opt_n;

sub fix_verified {
  my $sql = qq{SELECT COUNT(*) FROM $sql_db_table WHERE pr=?}; 
  my $sth = $dbh->prepare($sql) 
    or die "Couldn't prepare statement: " . $dbh->errstr;
  $sth->execute($_[0])
    or die "Couldn't execute statement on $_[0]: " . $dbh->errstr;
  my $record_count = $sth->fetch();
  $sth->finish();
  return $record_count->[0];
}

sub get_merged {
    my %form = (query_format => "advanced",
                short_desc_type => "allwordssubstr",
                product => ["EDG C\x2B\x2B Front End", "Insure\x2B\x2B"],
                bug_file_loc_type => "allwordssubstr",
                keywords_type => "nowords",
                keywords => "insship insrel",
                bug_status => "RESOLVED",
                resolution => "FIXED",
                bugidtype => "include",
                chfieldto => "Now",
                cmdtype => "doit"
               );
    my $search_url = URI->new(qq{http://$bugzilla_host.$domain/bugzilla/buglist.cgi});
    $search_url->query_form(%form);

    my $browser = LWP::UserAgent->new();
    my $response = $browser->get($search_url);
    my @search_result = split(/\n/, $response->content());
    my @pr_list = process_html(@search_result);
    my @merged = check_db(@pr_list);
  
    return @merged;
}

sub process_html {
    my @bugs;
    foreach my $line (@_) {
        if ($line =~ /bug\.cgi\?id=(\d{1,10})/) {
            push(@bugs, $1) if fix_verified($1);
        }
    }
    @bugs = sort {int($a) <=> int($b)} @bugs;
    return @bugs;
}

sub check_db {
    my @fully_merged;
    my $sql = qq{SELECT insrel FROM $sql_db_table WHERE pr = ?};
    my $sth = $dbh->prepare_cached($sql);
    foreach my $pr (@_) {
        my $all_merged = 1;
        $sth->execute($pr);
        # The condition for the while loop is a little odd.  If insrel values
        # are grabbed using fetch and with no parenthesis around $insrel, the
        # condition fails when $insrel is set to 0.  A Bad Thing.(TM)
        while (my ($insrel) =$sth->fetchrow_array()) {
            $all_merged = 0 unless $insrel;
        }
        push(@fully_merged, $pr) if $all_merged;
    }
    return @fully_merged;
}

sub update_bugzilla_keywords {
    my %buglist_form 
      = (dontchange => "--do_not_change--",
         product => "--do_not_change--",
         version => "--do_not_change--",
         component => "--do_not_change--",
         priority => "--do_not_change--",
         rep_platform => "--do_not_change--",
         bug_severity => "--do_not_change--",
         op_sys => "--do_not_change--",
         ccaction => "add",
         keywords => "insrel",
         keywordaction => "add",
         knob => "none",
         assigned_to => "$bug_user\x40$domain");
    my %login_form
      = (Bugzilla_login => "$bug_user\x40$domain",
         Bugzilla_password => "$bug_password",
         GoAheadAndLogIn => "Log in");
    my $login_url = URI->new(qq{http://$bugzilla_host.$domain/bugzilla/index.cgi});
    my $buglist_url = URI->new(qq{http://$bugzilla_host.$domain/bugzilla/process_bug.cgi});
    my $browser = LWP::UserAgent->new();
  
    $browser->cookie_jar({});
  
    my $response = $browser->post($login_url, \%login_form);
  
    foreach my $id (@_) {
        my $form_id = "id_" . $id;
        $buglist_form{$form_id} = "on";
    }
  
    unless ($opt_n) {
        $response = $browser->post($buglist_url, \%buglist_form);
        die "Error: ", $response->status_line() unless $response->is_success();
    } elsif (@_) {
        print qq{The keyword "insrel" would have been added to },
          qq{the bugzilla pages\nof the following PRs:\n\n};
        foreach my $id (@_) {
            print "$id.\n";
        }
        print "\n";
    }
}

### MAIN ###

getopts("n");

# Note that AutoCommit settings are ignored by the MyISAM database engine.
# All MyISAM tables behave as though AutoCommit is enabled.
$dbh = DBI->connect("$sql_db;host=$db_host.$domain",
                    "$sql_user", "$sql_password", 
                    {
                     'RaiseError' => 1, AutoCommit => 1});
my @bugs_to_update = get_merged();

update_bugzilla_keywords(@bugs_to_update);

# Disconnect from the database.
$dbh->disconnect;
exit;
