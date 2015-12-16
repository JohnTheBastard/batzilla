#!/usr/local/bin/perl -w
#bat_fix.pl

use strict;
use warnings;
use Getopt::Std;
use Term::ANSIColor qw(:constants);

my $host = "camel";
my $user = $ENV{'USER'};
my $root = $ENV{'CVSROOT'};
my $issue;
my $file;
my $revision;
my $date;
my $cvs_date;

# Flags need to be scoped "our" ... Not sure why.
our($opt_p, $opt_r, $opt_f, $opt_h);

sub usage {
    print BOLD, "\nNAME\n", RESET, "\tbatfix - a text based client for adding ",
      "records to a Batzilla fix\n\n", BOLD, "USAGE\n\tbatfix", RESET, " [", BOLD, 
      "-h ", RESET, "] [[", BOLD, "-r ", RESET, UNDERLINE, "revision", RESET, "] ",
      BOLD, "-p ", RESET, UNDERLINE, "bug id", RESET, BOLD, " -f ", RESET, UNDERLINE,
      "file", RESET, "]\n\n";
    print BOLD, "DESCRIPTION\n", RESET, "\tThe ", UNDERLINE, "batfix", RESET, 
      " program  provides a command-line interface to Batzilla,\n\tallowing the", 
      " user to add files to a fix associated with a particular\n\tbug id (aka", 
      " Bugzilla Problem Report). The CVS submittal data is fetched\n\tand committed",
      " to Batzilla using the user's login name as the committer.\n\tNote that ",
      UNDERLINE, "batfix", RESET," must be run from the CVS working directory.\n\n";
    print BOLD, "FLAGS\n\t-h\n\t\t", RESET, "Display this help message.  All other ",
      "flags will be ignored.\n\n\t", BOLD, "-r ", RESET, UNDERLINE, "revision", RESET, 
      "\n\t\tOptional.  Specify a particular revision of the file to commit\n\t\t",
      "to Batzilla.  If no revision is specified, the last revision\n\t\tsumbitted ",
      "to CVS by the user will be committed.\n\n\t", BOLD, "-p ", RESET, UNDERLINE, 
      "bug id", RESET, "\n\t\tRequired (except with -h).  Specify the Problem Report ",
      "with\n\t\twhich to associate the file being committed.\n\n\t", BOLD, "-f ", 
      RESET, UNDERLINE, "file", RESET, "\n\t\tRequired (except with -h).  Specify ",
      "the file to be committed.\n\n";
}

### MAIN ###

getopts("p:r:f:h");

if ($opt_h || !($opt_p && $opt_f)) {
    usage();
    exit;
}

$issue = $opt_p;

if ($opt_r) {
    # Backticks `` execute delimited command in shell.
    my @cvs_log = `cvs log -N -S -r$opt_r $opt_f`;
    
    my $line = 0;
    until ($cvs_date) {
        if ($cvs_log[$line] =~ /^RCS file:\s$root\/([\w\/.]+$opt_f),v$/) {
            $file = $1;
        } elsif ($cvs_log[$line] =~ /^date:\s([\d\s:-]+);/) {
            $cvs_date = $1;
        }
        $line++;
    }
    $revision = $opt_r;
} else {
    # Backticks `` execute delimited command in shell.
    my @cvs_log = `cvs log -N -S $opt_f`;
    my $line = 0;
    my $temp_rev;    
    
    until ($revision) {
        if ($cvs_log[$line] =~ /^RCS file:\s$root\/([\w\/.]+$opt_f),v$/) {
            $file = $1;
        } elsif ($cvs_log[$line] =~ /^revision\s([\d.]+)/) {
            $temp_rev = $1;
        } elsif ($cvs_log[$line] =~ /^date:\s([\d\s:-]+);\s+author:\s(\w+);/){
            if ($user eq $2) {
                $revision = $temp_rev;
                $cvs_date = $1;
            }
        }
        $line++;
    }
}

# Backticks `` execute delimited command in shell.
$date = `date -d "$cvs_date" +"\%a \%b \%e \%H:\%M:\%S \%Y"`;
# Using the following line instead for debugging on dogcow.
#$date = qq{Wed Sep  4 10:07:08 2002};

my $ci_line = qq{$user ci $file $revision $date};
my $post_data = qq{--post-data='id=$issue&form_action=Add&bugs_to_add=$ci_line'};
my $url = qq{$host/bugzilla/show_fix.cgi};
my $options = qq{-q --delete-after};

# Backticks `` execute delimited command in shell.
my $request = `wget $options $post_data $url`;
