#!/usr/bin/perl -wT

# Comments:
#  This CGI script takes a PR number as a GET request and displays
#  associated files and relevant data.  The user can use the script to 
#  add or delete files.  The user can edit INSREL and DEVTEST status.
#  Optionally, the "format" parameter can be set to "text" in the GET
#  request and the script will display the file/revision pairs in 
#  plaintext or it can be set to "diff" or "difflog" and the script
#  will display the difflog style ci lines in plaintext.  
#  
#  (E.G. "http://.../bugzilla/show_fix.cgi?id=9&format=text" would 
#  display the file/revision pairs for PR #9 in plaintext).

# (C) Copyright ParaSoft Corporation 2003.  All rights reserved.
# THIS IS UNPUBLISHED PROPRIETARY SOURCE CODE OF ParaSoft
# The copyright notice above does not evidence any
# actual or intended publication of such source code.

# $Author: jhearn $          $Locker:  $
# $Date: 2006/08/11 00:30:06 $
# $Log: show_fix.cgi,v $
# Revision 1.8  2006/08/11 00:30:06  jhearn
# .../show_fix.cgi?id=#&format=diff now displays ci lines for fix.
#
# Revision 1.7  2006/08/09 20:06:34  jhearn
# more style changes
#
# Revision 1.6  2006/08/09 17:06:38  jhearn
# Killed lots of white space, and some other style changes.
#
# Revision 1.5  2006/08/08 23:40:32  jhearn
# Style changes based on feedback from jwilkes during code review.
#
# Revision 1.4  2006/08/02 18:15:07  jhearn
# show_fix.cgi now uses the Bugzilla modules instead of the CGI module (thus
# fixing PR5), and is now compatible with batfix.pl.  Additionally, PR6 (problems
# with text output) and PR7 (Needs Bugzilla Footer) are fixed.
#
# Revision 1.3  2006/07/21 17:17:49  jwilkes
# Revision comment for 1.1 seems to have been accidentally nuked;
# brought it back.  Also, db_host is camel, not dev3.  I wonder if
# localhost would work...
#
# Revision 1.2  2006/07/20 15:48:21  jhearn
# Custom banner for Batzilla.
# Should be located at:
# /var/www/html/bugzilla/skins/custom/global/bat_header.png.
#
# Revision 1.1  2006/07/19 21:52:03  jhearn
# Moved into directory bugzilla.
# Added default user functionality for adding files to fix.
#
# Revision 1.6  2006/07/05 22:30:31  jhearn
# Minor appearance tweaks.
#
# Revision 1.4  2006/07/05 20:00:45  jhearn
# Normalized variable names and heading comments for all batzilla files.
#

use strict;
use warnings;
use DBI;
use LWP::Simple;

# Include the Bugzilla CGI and general utility library.
use lib qw(.);
require "globals.pl";
use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::User;
use Bugzilla::Bug;

### MAIN ###

# Check whether or not the user is logged in
Bugzilla->login(LOGIN_OPTIONAL);

my $cgi = Bugzilla->cgi;
# Force to use HTTPS unless Param('ssl') equals 'never'.
# This is required because the user may want to log in from here.
if (Param('sslbase') ne '' and Param('ssl') ne 'never') {
    $cgi->require_https(Param('sslbase'));
}

my $template = Bugzilla->template;
my $vars = {};
my @bugs = ();

# Before anything else, make sure we have a valid Problem Report ID
#bad_id() unless ($id =~ /^\d+$/);
# If we don't have an ID, then prompt
unless ($cgi->param('id')) {
    print Bugzilla->cgi->header();
    $template->process("bug/choose.html.tmpl", $vars) ||
      ThrowTemplateError($template->error());
    exit;
}

my $id = $cgi->param('id');

ValidateBugID($id);

push @bugs, new Bugzilla::Bug($id, Bugzilla->user->id);
$vars->{'bugs'} = \@bugs;

my $db_host = "dev3";
#my $db_host = "camel";
my $domain = "parasoft.com";
my $user = "bats";
my $password = "batmantis00";
my $sql_db;
my $db_table;

Bugzilla->user->login =~ /^(\w+)\W$domain$/i;
my $default_committer = $1;

if ($db_host eq "dev3") {
    $sql_db = "DBI:mysql:database=test";
    $db_table = "test.cttest";
} elsif ($db_host eq "camel") {
    $sql_db = "DBI:mysql:database=fixes";
    $db_table = "fixes.fixes";
}

my $action = $cgi->param('form_action');
my $alt_format; 
if ($cgi->param('format') =~ /^text$/i) {
    $alt_format = 2;
} elsif ($cgi->param('format') =~ /^diff(log)?$/i) {
    $alt_format = 1;
} else {
    $alt_format = 0;
}

# Note that AutoCommit settings are ignored by the MyISAM database engine.
# All MyISAM tables behave as though AutoCommit is enabled.
my $dbh = 
  DBI->connect("$sql_db;host=$db_host.$domain", "$user", "$password", 
               {'RaiseError' => 1, AutoCommit => 1});

my  $show_devtest = show_devtest();
my  $show_insrel = show_insrel();
my $sql = 
  qq{SELECT file, revision, committer, date, devtest, insrel }
  . qq{FROM $db_table WHERE pr = $id ORDER BY file, revision};
my $sth = $dbh->prepare_cached($sql);

unless ($alt_format) {
    print_header_and_stuff();
} else {
    #We need a newline before printing anything else.
    print "\n";
}

$sth->execute() or die "Couldn't execute statement. $!";

# keep fetching until there's nothing left
while (my $record = $sth->fetchrow_hashref()) { 
    unless ($alt_format) { 
	print_html_data($record);
    } elsif ($alt_format == 1) {
	print_diff_data($record);
    } elsif ($alt_format == 2) {
	print_text_data($record);
    }
}  
unless ($alt_format) {
    print_buttons_and_stuff();
    $template->process("global/bat_footer.html.tmpl")
      || ThrowTemplateError($template->error());
}
$dbh->disconnect();
exit;

       ################### 
      ###               ###
########   SUBROUTINES   ########
      ###               ###
       ################### 


sub show_devtest {
    if ($action eq "Edit States") {
	return 1;
    } else {
	# For now, we don't show devtest status, so return 0;
	return 0;
    }
}

sub show_insrel {
    if ($action eq "Edit States") {
	return 1;
    } else {
	my $local_sql = qq{SELECT COUNT(*) FROM $db_table WHERE insrel = '1' AND pr = $id};
	my $local_sth = $dbh->prepare($local_sql);
	$local_sth->execute();
	my $record_count = $local_sth->fetch();
	$local_sth->finish();
	return $record_count->[0];
    }
}

sub print_header_and_stuff {
    print $cgi->header, $cgi->start_html("Show Fix"); 
    print $cgi->start_form;
    # Generate and return the UI (HTML page) from the appropriate template.
    $template->process("global/bat_banner.html.tmpl", { 'id' => $id })
      || ThrowTemplateError($template->error());
    if ($action eq "Add") {
	add_id();
    } elsif ($action eq "Delete") {
	delete_id();
    } elsif ($action eq "Commit Changes") {
	update_states(); 
    }
    print qq{<form action="show_fix.cgi" method="post">
             <input type="hidden" name="id" value="$id">
             <table width="100%" border = "1" cellpadding = "5">
         <tr>};
    print qq{<th></th>} if ($action eq "Make Deletions");
    print qq{    
             <th>Committer</th>
             <th>File</th>
             <th>Revision</th>
             <th>Date</th>};
    print qq{             <th>Devtest</th>} if $show_devtest;
    print qq{             <th>Insrel</th>} if $show_insrel;
    print qq{         </tr>};
}
  
sub print_html_data {
    print qq!<tr>!;
    print qq!<td>
           <input name="stuff_to_delete" value="$_[0]->{file} $_[0]->{revision}" type="checkbox">
           </td>! if ($action eq "Make Deletions");
    print qq!
             <td>$_[0]->{committer}</td>
             <td>$_[0]->{file}</td>
             <td>$_[0]->{revision}</td>
             <td>$_[0]->{date}</td>
            !;
    if ($action eq "Edit States") {
	print qq!<td><input name="devtest_checked" 
                  value="$_[0]->{file} $_[0]->{revision}" 
                  type="checkbox"!;
	print qq! checked! if ($_[0]->{devtest});
	print qq!></td>!;
	print qq!<td><input name="insrel_checked" 
                  value="$_[0]->{file} $_[0]->{revision}" 
                  type="checkbox"!;
	print qq! checked! if ($_[0]->{insrel});
	print qq!></td>!;
    } else {
	print qq!               <td>$_[0]->{devtest}</td>! if $show_devtest;
	print qq!               <td>$_[0]->{insrel}</td>! if $show_insrel;
    }
    print qq!         </tr>!;
}

sub print_text_data {
    print "$_[0]->{file} $_[0]->{revision}\n";    
}

sub print_diff_data {
  print "$_[0]->{committer} ci $_[0]->{file} $_[0]->{revision} $_[0]->{date}\n";    
}

sub print_buttons_and_stuff {
    print qq{       </table><p />};
    print qq{<input type="submit" name="form_action" value="Delete">} 
      if  ($action eq "Make Deletions");
    unless ($action =~ /^(Make|Edit)/ ) {
	print qq{ <input type="submit" name="form_action" value="Make Deletions"> 
              <input type="submit" name="form_action" value="Make Additions">
              <input type="submit" name="form_action" value="Edit States"><p />};
    } elsif ($action eq "Make Additions") {
	print qq{<p /> Committer: <input type="text" name="default_committer" value="$default_committer" >
          <p />
         <textarea name="bugs_to_add" rows="6" cols="120" wrap="physical"></textarea>
         <p />
         <input type="submit" name="form_action" value="Add">};
    } elsif ($action eq "Edit States") {
	print qq{<p /><input type="submit" name="form_action" value="Commit Changes">};
    }
    $sth->finish();  
    print $cgi->end_form;
}  
  
  
sub add_id {
    my $bugs_to_add = $cgi->param('bugs_to_add');
    my @bugs_to_add = split (/\n/, $bugs_to_add);
    my $bad_input = 0;
    my $ci_regexp = '^((\w+)\s)*ci\s(\S+)\s([Nn][Oo][Nn][Ee]|(\d*\.)*\d+)\s(.+(19|20)\d\d)';
    my @good_stuff;  # An array of arrays
    my @bad_stuff;
    
    # Make sure input is valid (good format, no duplicates)
    foreach my $bug (@bugs_to_add) {
	if ($bug =~ /$ci_regexp/) {
	    my $committer = ($2) ? $2 : $default_committer;
	    my $file = $3;
	    my $revision = $4;
	    my $date = $6;
	    
	    unless ($committer =~ /\w+/) {
		# This shouldn't ever execute, since login is required.
		my $err_msg = qq{No committer specified.  Please try again.};
		err_msg_box($err_msg);
		print qq{<p />};
		return 0;
	    }      
	    
	    my @bug_record = ($file, $revision, $committer, $date);
	    
	    unless (already_there($file, $revision)) {
		unless ($bad_input) {
		    # Put record in good stuff
		    push(@good_stuff, [@bug_record]);
		}
	    } else {  
		# Input is already in DB so put in bad stuff
		push(@bad_stuff, qq{<pre>DUPLICATE ENTRY: $bug</pre>});
		$bad_input = 1;
	    }
	} else {
	    # Input didn't match regexp so put in bad stuff
	    push(@bad_stuff, qq{<pre>BAD INPUT: $bug</pre>});
	    $bad_input = 1;
	}
    }
    
    unless ($bad_input) {     
	my $local_sql = 
	  qq{INSERT INTO $db_table(pr, file, revision, committer, date) VALUES (?, ?, ?, ?, ?)};
	my $local_sth = $dbh->prepare_cached($local_sql) 
	  or die "Couldn't prepare statement: " . $dbh->errstr;
	
	foreach (@good_stuff) {
	    $local_sth->execute( $id, @$_)
	      or die "Couldn't execute statement using @$_[1]: " . $dbh->errstr;
	}
	$local_sth->finish();
    }  else {
	my $err_msg = qq{No records have been added.  Please try again.};
	
	err_msg_box($err_msg);
	print qq{<p />}, @bad_stuff;
    }
}

sub delete_id {
    my @stuff_to_delete = $cgi->param('stuff_to_delete');
    foreach my $file_and_revision (@stuff_to_delete) {
	my $file;
	my $revision;
	if ($file_and_revision =~ /^(\S+)\s([Nn][Oo][Nn][Ee]|(\d*\.)*\d+)$/) {
	    $file = $1;
	    $revision =$2;
	}
	
	my $local_sql = qq{DELETE FROM $db_table WHERE pr=? AND file=? AND revision=?};
	my $local_sth = $dbh->prepare_cached($local_sql) 
	  or die "Couldn't prepare statement: " . $dbh->errstr;
	$local_sth->execute($id, $file, $revision) 
	  or die "Couldn't execute statement on $file $revision: " . $dbh->errstr;
	$local_sth->finish();
    }  
    
}

sub update_states {
  # This subroutine is kind of gross.
    my %fr_devtest = ();
    my %fr_insrel = ();
    my $temp_fr;  
    my @devtest_checked = $cgi->param('devtest_checked');
    my @insrel_checked = $cgi->param('insrel_checked');
    
    my $sql = qq{SELECT file, revision  FROM $db_table WHERE pr = $id ORDER BY file, revision};
    my $sth = $dbh->prepare_cached($sql);
    $sth->execute() or die "Couldn't execute statement. $!";
    
    while (my ($db_file, $db_revision) = $sth->fetchrow_array()) {
	$fr_devtest{"$db_file $db_revision"} = 0;
	$fr_insrel{"$db_file $db_revision"} = 0;
    }
    $sth->finish();
    
    foreach my $entry (@devtest_checked) {$fr_devtest{$entry} = 1;}
    foreach my $entry (@insrel_checked) {$fr_insrel{$entry} = 1;}  
    #foreach (sort keys %fr_devtest) {print "$_ = $fr_devtest{$_} <br>\n";}
    #foreach (sort keys %fr_insrel) {print "$_ = $fr_insrel{$_} <br>\n";}
    
    $sql = qq{UPDATE $db_table SET devtest = ? WHERE file = ? AND revision = ?};
    $sth = $dbh->prepare_cached($sql);
    foreach (sort keys %fr_devtest) {
	if ($_ =~ /^(\S+)\s(\S+)$/) {
	    $sth->execute($fr_devtest{$_}, $1, $2) or die "Couldn't execute statement. $!";
	}
    }
    $sth->finish();
    
    $sql = qq{UPDATE $db_table SET insrel = ? WHERE file = ? AND revision = ?};
    $sth = $dbh->prepare_cached($sql);
    foreach (sort keys %fr_insrel) {
	if ($_ =~ /^(\S+)\s(\S+)$/) {
	    $sth->execute($fr_insrel{$_}, $1, $2) or die "Couldn't execute statement. $!";
	}
    }
    $sth->finish();

    check_for_weird_insrel();
}

sub already_there {
    my $this_file = $_[0];
    my $this_revision = $_[1];
    
    my $local_sql = qq{SELECT COUNT(*) FROM $db_table WHERE pr=? AND file=? AND revision=?};
    my $local_sth = $dbh->prepare($local_sql) 
      or die "Couldn't prepare statement: " . $dbh->errstr;
  $local_sth->execute($id, $this_file, $this_revision)
    or die "Couldn't execute statement on $this_file $this_revision: " . $dbh->errstr;
    my $record_count = $local_sth->fetch();
    $local_sth->finish();
    
    return $record_count->[0];
}

sub check_for_weird_insrel {
    my $sql1 = qq{SELECT file FROM $db_table WHERE pr = $id }
      .qq{GROUP BY file HAVING (COUNT(file) > 1 AND COUNT(pr) > 1)};
    my $sql2 = qq{SELECT revision, insrel FROM $db_table WHERE file = ?};
    my $sth1 = $dbh->prepare($sql1);
    my $sth2 = $dbh->prepare_cached($sql2);
    
  $sth1->execute() or die "Couldn't execute statement. $!";
    while (my ($file) = $sth1->fetchrow_array()) {
	my %hash= ();
	my $highest_insrel_rev = undef;
	my @weird_revisions = ();
	
	$sth2->execute($file);
	while (my ($revision, $insrel) = $sth2->fetchrow_array()) {
	    $hash{$revision} = $insrel;
	    # This looks dumb, but I just want $highest_insrel_rev set
	    # to some revision in INSREL status.  It might get set
	    # many times during the while loop.  Don't care.
	    $highest_insrel_rev = $revision if ($insrel);
	}
	$highest_insrel_rev =~ /^(\d+)\.(\d+)(\.\d+)*/;
	my $hir_major = $1;
	my $hir_minor = $2;
	delete $hash{$highest_insrel_rev};
	foreach (keys %hash) {
	    # This loop will find the highest revision with INSREL status
	    # and eliminate some revisions from the hash (to speed up the
	    # next foreach loop), but does not ensure that all the weird
	    # revisions are found.
	    
	    $_ =~ /^(\d+)\.(\d+)(\.\d+)*/;
	    my $temp_major = $1;
	    my $temp_minor = $2;
	    if (($temp_major < $hir_major) ||
		(($temp_major == $hir_major) && ($temp_minor < $hir_minor))) {
		push (@weird_revisions, $_) unless ($hash{$_});
		delete $hash{$_};
	    } else {
		if ($hash{$_}) {
		    $highest_insrel_rev = $_;
		    $hir_major = $temp_major;
		    $hir_minor = $temp_minor;
		    delete $hash{$_};
		}
	    }
	}
	
	foreach (keys %hash) {
	    # We make sure all weird revisions are found.
	    $_ =~ /^(\d+)\.(\d+)(\.\d+)*/;
	    my $temp_major = $1;
	    my $temp_minor = $2;
	    
	    if (($temp_major < $hir_major) ||
		(($temp_major == $hir_major) && ($temp_minor < $hir_minor))) {
		push (@weird_revisions, $_) unless ($hash{$_});
	    } 
	}
	
	if (@weird_revisions) {
	    my $error_message = qq{Revision $highest_insrel_rev of file "$file" is in INSREL }
	      . qq{but the following revision(s) are not: <br>}
		. join (", ", @weird_revisions)
		  . qq{<br><br>Please re-edit if this is incorrect.<br>};
	    err_msg_box($error_message);
	}
    }
}

sub err_msg_box {
    print qq{
             <table cellpadding="8">
              <tr>
               <td bgcolor="#ff0000">
                <font size="+2">
                  $_[0]
                </font>
               </td>
              </tr>
             </table>
            };
}
