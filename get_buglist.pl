#!/usr/bin/perl

# Comments:
#   Queries bugzilla to get a list of problem reports, outputs a comma
#   seperated list of problem report numbers.

# (C) Copyright ParaSoft Corporation 2003.  All rights reserved.
# THIS IS UNPUBLISHED PROPRIETARY SOURCE CODE OF ParaSoft
# The copyright notice above does not evidence any
# actual or intended publication of such source code.

# $Author: jhearn $          $Locker:  $
# $Date: 2006/08/09 20:06:33 $
# Revision 1.1.1.1  2006/07/26 18:23:16  temp
# batzilla
#
# Revision 1.3  2006/08/01 23:05:52  jwilkes
# Removed unnecessary reference to DBI.
#
# Revision 1.2  2006/07/05 19:59:45  jhearn
# Normalized variable names and heading comments for all batzilla files.
#

use strict;
use warnings;
use LWP::Simple;
use URI;

my $host = "camel.parasoft.com";

my %search_form = (
                   "query_format" => "advanced",
                   "short_desc_type" => "allwordssubstr",
                   "short_desc" => "",
                   "product" => ["EDG C\x2B\x2B Front End",
                                 "Insure\x2B\x2B"],
                   "long_desc_type" => "allwordssubstr",
                   "long_desc" => "",
                   "bug_file_loc_type" => "allwordssubstr",
                   "bug_file_loc" => "",
                   "status_whiteboard_type" => "allwordssubstr",
                   "status_whiteboard" => "",
                   "keywords_type" => "allwords",
                   "keywords" => "",
                   "bug_status" => ["NEW", "ASSIGNED", "REOPENED", 
                                    "RESOLVED", "VERIFIED"],
                   "resolution" => ["FIXED", "---"],
                   "emailtype1" => "substring",
                   "email1" => "",
                   "emailtype2" => "substring",
                   "email2" => "",
                   "bugidtype" => "include",
                   "bug_id" => "",
                   "votes" => "",
                   "chfieldfrom" => "",
                   "chfieldto" => "Now",
                   "chfieldvalue" => "",
                   "cmdtype" => "doit",
                   "order" => "Bug Number",
                   "field0-0-0" => "noop",
                   "type0-0-0" => "noop",
                   "value0-0-0" => "",
                  );


my $search_url = URI->new(qq{http://$host/bugzilla/buglist.cgi});
$search_url->query_form(%search_form);

my $response = get $search_url;

my @search_result = split(/\n/, $response);
my @prs;

foreach my $line (@search_result) {
    if ($line =~ /cgi\?id=(\d{1,10})/) {
        push (@prs, $1);
    }
}

print join ",", @prs;
