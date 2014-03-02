#!/usr/bin/perl -w
use strict;
##########################################################################
##########################################################################
# Most current version can always be found at:
# ftp://ftp.logwatch.org/pub/linux (tarball)
# ftp://ftp.logwatch.org/pub/redhat/RPMS (RPMs)

########################################################
# Specify version and build-date:
my $Version = '7.4.0';
my $VDate = '03/01/11';

#######################################################
# Logwatch was written and is maintained by:
#    Kirk Bauer <kirk@kaybee.org>
#
# Unless otherwise specified, Logwatch and all bundled filter scripts
# are Copyright (c) Kirk Bauer and covered under the included MIT/X
# Consortium license.
#
# Please send all comments, suggestions, bug reports,
#    etc, to logwatch@logwatch.org.
#
########################################################

############################################################################
# ENV SETTINGS:
# About the locale:  some functions use locale information.  In particular,
# Logwatch makes use of strftime, which makes use of LC_TIME variable.  Other
# functions may also use locale information.
#
# Because the parsing must be in the same locale as the logged information,
# and this appears to be "C", "POSIX", or "en_US", we set LC_ALL for
# this and other scripts invoked by this script.  We use "C" because it
# is always (?) available, whereas POSIX or en_US may not.  They all use
# the same time formats and rely on the ASCII character set.
#
# Variables REAL_LANG and REAL_LC_ALL keep the original values for use by
# scripts that need native language.
$ENV{'REAL_LANG'}=$ENV{'LANG'} if $ENV{'LANG'};
$ENV{'REAL_LC_ALL'}=$ENV{'LC_ALL'} if $ENV{'LC_ALL'};

# Setting ENV for scripts invoked by this script.
$ENV{'LC_ALL'} = "C";
# Using setlocale to set locale for this script.
use POSIX qw(locale_h);
setlocale(LC_ALL, "C");

my $BaseDir = "/usr/share/logwatch";
my $ConfigDir = "/etc/logwatch";
my $PerlVersion = "$^X";

#############################################################################

#############################################################################
# SET LIBS, GLOBALS, and DEFAULTS
use Getopt::Long;
use POSIX qw(uname);
use File::Temp qw/ tempdir /;

eval "use lib \"$BaseDir/lib\";";
eval "use Logwatch \':dates\'";

my (%Config, @ServiceList, @LogFileList, %ServiceData, %LogFileData);
my (@AllShared, @AllLogFiles, @FileList);
# These need to not be global variables one day
my (@ReadConfigNames, @ReadConfigValues);

# Default config here...
$Config{'detail'} = 0;
# if MAILTO is set in the environment, grab it, as it may be used by cron
# or anacron
if ($ENV{'MAILTO'}) {
   $Config{'mailto'} = $ENV{'MAILTO'};
} else {
   $Config{'mailto'} = "root";
}
$Config{'mailfrom'} = "Logwatch";
$Config{'subject'} = "";
$Config{'filename'} = "";
$Config{'range'} = "yesterday";
$Config{'debug'} = 0;
$Config{'archives'} = 1;
$Config{'tmpdir'} = "/var/cache/logwatch";
$Config{'numeric'} = 0;
$Config{'pathtocat'} = "cat";
$Config{'pathtozcat'} = "zcat";
$Config{'pathtobzcat'} = "bzcat";
$Config{'output'} = "stdout"; #8.0
$Config{'format'} = "text"; #8.0
$Config{'encode'} = "none"; #8.0
$Config{'hostformat'} = "none"; #8.0
$Config{'html_wrap'} = 80;
$Config{'supress_ignores'} = 0;

if (-e "$ConfigDir/conf/html/header.html") {
   $Config{'html_header'} = "$ConfigDir/conf/html/header.html";
} elsif (-e "$BaseDir/dist.conf/html/header.html") {
   $Config{'html_header'} = "$BaseDir/dist.conf/html/header.html";
} else {
   $Config{'html_header'} = "$BaseDir/default.conf/html/header.html";
}

if (-e "$ConfigDir/conf/html/footer.html") {
   $Config{'html_footer'} = "$ConfigDir/conf/html/footer.html";
} elsif (-e "$BaseDir/dist.conf/html/footer.html") {
   $Config{'html_footer'} = "$BaseDir/dist.conf/html/footer.html";
} else {
   $Config{'html_footer'} = "$BaseDir/default.conf/html/footer.html";
}

# Logwatch now does some basic searching for logs
# So if the log file is not in the log path it will check /var/adm
# and then /var/log -mgt
$Config{'logdir'} = "/var/log";

#Added to create switches for different os options -mgt
#Changed to POSIX to remove calls to uname and hostname
my ($OSname, $hostname, $release, $version, $machine) = POSIX::uname();
$Config{'hostname'} = "$hostname";

my %wordsToInts = (yes  => 1,  no     => 0,
                   true => 1,  false  => 0,
                   on   => 1,  off    => 0,
                   high => 10,
                   med  => 5,  medium => 5,
                   low  => 0);

#############################################################################

#############################################################################
#Load CONFIG, READ OPTIONS, make adjustments

# Load main config file...
if ($Config{'debug'} > 8) {
   print "\nDefault Config:\n";
   &PrintConfig();
}

&CleanVars();

# For each of the configuration sets (logwatch.conf here, and
# logfiles,and services later), we do the following:
#  1. read the different configuration files
#  2. for each parameter, if it is cummulative, check if
#     it the special case empty string
#  3. check to see if duplicate

@ReadConfigNames = ();
@ReadConfigValues = ();

&ReadConfigFile ("$BaseDir/default.conf/logwatch.conf", "");
&ReadConfigFile ("$BaseDir/dist.conf/logwatch.conf", "");
&ReadConfigFile ("$ConfigDir/conf/logwatch.conf", "");
&ReadConfigFile ("$ConfigDir/conf/override.conf", "logwatch");


for (my $i = 0; $i <= $#ReadConfigNames; $i++) {
   if ($ReadConfigNames[$i] eq "logfile") {
      if ($ReadConfigValues[$i] eq "") {
	  @LogFileList = ();
      } elsif (! grep(/^$ReadConfigValues[$i]$/, @LogFileList)) {
         push @LogFileList, $ReadConfigValues[$i];
      }
   } elsif ($ReadConfigNames[$i] eq "service") {
      if ($ReadConfigValues[$i] eq "") {
	  @ServiceList = ();
      } elsif (! grep(/^$ReadConfigValues[$i]$/, @ServiceList)) {
         push @ServiceList, $ReadConfigValues[$i];
      }
   } else {
      $Config{$ReadConfigNames[$i]} = $ReadConfigValues[$i];
   }
}

&CleanVars();

if ($Config{'debug'} > 8) {
   print "\nConfig After Config File:\n";
   &PrintConfig();
}

# Options time...

my @TempLogFileList = ();
my @TempServiceList = ();
my $Help = 0;
my $ShowVersion = 0;
my ($tmp_mailto, $tmp_savefile);

&GetOptions ("d|detail=s"   => \$Config{'detail'},
             "l|logfile=s@" => \@TempLogFileList,
             "logdir=s"     => \$Config{'logdir'},
             "s|service=s@" => \@TempServiceList,
             "m|mailto=s"   => \$tmp_mailto,
             "filename=s"   => \$tmp_savefile,
             "a|archives"   => \$Config{'archives'},
             "debug=s"      => \$Config{'debug'},
             "r|range=s"    => \$Config{'range'},
             "n|numeric"    => \$Config{'numeric'},
             "h|help"       => \$Help,
             "u|usage"      => \$Help,
             "v|version"    => \$ShowVersion,
             "hostname=s"   => \$Config{'hostname'},
             "o|output=s"   => \$Config{'output'},
             "f|format=s"   => \$Config{'format'},
             "e|encode=s"   => \$Config{'encode'},
             "hostformat=s" => \$Config{'hostformat'},
             "hostlimit=s"  => \$Config{'hostlimit'},
             "html_wrap=s"  => \$Config{'html_wrap'},
             "subject=s"    => \$Config{'subject'}
           ) or &Usage();

$Help and &Usage();

#Catch option exceptions and extra logic here -mgt

if ($Config{'range'} =~ /help/i) {
    &RangeHelpDM();
    exit(0);
}

if ($ShowVersion) {
   print "Logwatch $Version (released $VDate)\n";
   exit 0;
}

if ($tmp_mailto) {
   $Config{'mailto'} = $tmp_mailto;
   $Config{'output'} = "mail"; #8.0
}

if ($tmp_savefile) {
   $Config{'filename'} = $tmp_savefile;
   $Config{'output'} = "file"; #8.0
}

if ($Config{'hostformat'} eq "splitmail") {
   $Config{'output'} = "mail"; #8.0
   #split hosts 1 long output stream
   #split hosts multiple output streams -mgt
}

&CleanVars();

#Init Output vars -mgt
my $index_par=0;
my @format = (250);
my %out_body;

my @reports = ();

my $out_head ='';
my $out_mime ='';
my $out_reference ='';
my $out_foot ='';

#Eval wrapper for MIME::Base64. Perl 5.6.1 does not include it.
#So Solaris 9 will break with out this. -mgt
#8.0 Catch encode types here
if ( $Config{'encode'} eq "base64" ) {
   eval "require MIME::Base64";
   if ($@) {
      print STDERR "No MIME::Base64 installed can not use --encode\n";
    } else {
      import MIME::Base64;
   }
}

#Reset save file now if we are going ot use it and it exists -mgt
if (($Config{'filename'} ne "") && (-e "$Config{'filename'}") ) {
   unlink "$Config{'filename'}";
}

#Check fallback to stdout if output is mail and no mailto exists -mgt
if ( ($Config{'output'} eq "mail") && ($Config{'mailto'} eq "") ) {
   $Config{'output'} = "stdout";
}

if ($Config{'debug'} > 8) {
   print "\nCommand Line Parameters:\n   Log File List:\n";
   &PrintStdArray(@TempLogFileList);
   print "\n   Service List:\n";
   &PrintStdArray(@TempServiceList);
   print "\nConfig After Command Line Parsing:\n";
   &PrintConfig();
}

if ($#TempLogFileList > -1) {
   @LogFileList = @TempLogFileList;
   for (my $i = 0; $i <= $#LogFileList; $i++) {
      $LogFileList[$i] = lc($LogFileList[$i]);
   }
   @ServiceList = ();
}

if ($#TempServiceList > -1) {
   @ServiceList = @TempServiceList;
   for (my $i = 0; $i <= $#ServiceList; $i++) {
      $ServiceList[$i] = lc($ServiceList[$i]);
   }
}

if ( ($#ServiceList == -1) and ($#LogFileList == -1) ) {
   push @ServiceList, 'all';
}

if ($Config{'debug'} > 5) {
   print "\nConfig After Everything:\n";
   &PrintConfig();
}

#############################################################################

# Find out what services are defined...
my @TempAllServices = ();
my @services = ();
my (@CmdList, @CmdArgList, @Separators, $ThisFile, $count);


foreach my $ServicesDir ("$BaseDir/default.conf", "$BaseDir/dist.conf", "$ConfigDir/conf") {
   if (-d "$ServicesDir/services") {
      opendir(SERVICESDIR, "$ServicesDir/services") or
         die "$ServicesDir $!";
      while (defined($ThisFile = readdir(SERVICESDIR))) {
	 if ((-f "$ServicesDir/services/$ThisFile") && (!grep (/^$ThisFile$/, @services)) && ($ThisFile =~ /\.conf$/)) {
	     push @services, $ThisFile;
         }
      }
      closedir SERVICESDIR;
   }
}

foreach my $f (@services) {
   my $ThisService = lc $f;
   $ThisService =~ s/\.conf$//;
   push @TempAllServices, $ThisService;

   # @Separators tells us where each of the config files start, and
   # is used only for the commands (entries that start with '*')
   @ReadConfigNames = ();
   @ReadConfigValues = ();
   @Separators = ();
   push (@Separators, scalar(@ReadConfigNames));
   &ReadConfigFile("$BaseDir/default.conf/services/$f", "");
   push (@Separators, scalar(@ReadConfigNames));
   &ReadConfigFile("$BaseDir/dist.conf/services/$f", "");
   push (@Separators, scalar(@ReadConfigNames));
   &ReadConfigFile("$ConfigDir/conf/services/$f","");
   push (@Separators, scalar(@ReadConfigNames));
   &ReadConfigFile("$ConfigDir/conf/override.conf", "services/$ThisService");

   @CmdList = ();
   @CmdArgList = ();

   # set the default for DisplayOrder (0.5), which should be a fraction of any precision between 0 and 1
   $ServiceData{$ThisService}{'displayorder'} = 0.5;

   for (my $i = 0; $i <= $#ReadConfigNames; $i++) {
      if (grep(/^$i$/, @Separators)) {
         $count = 0;
      }

      if ($ReadConfigNames[$i] eq 'logfile') {
         if ($ReadConfigValues[$i] eq "") {
	         @{$ServiceData{$ThisService}{'logfiles'}} = ();
         } elsif (! grep(/^$ReadConfigValues[$i]$/, @{$ServiceData{$ThisService}{'logfiles'}})) {
            push @{$ServiceData{$ThisService}{'logfiles'}}, $ReadConfigValues[$i];
	      }
      } elsif ($ReadConfigNames[$i] =~ /^\*/) {
	      if ($count == 0) {
	         @CmdList = ();
	         @CmdArgList = ();
	      }
         $count++;
         push (@CmdList, $ReadConfigNames[$i]);
         push (@CmdArgList, $ReadConfigValues[$i]);
      } else {
         $ServiceData{$ThisService}{$ReadConfigNames[$i]} = $ReadConfigValues[$i];
      }
   }
   for my $i (0..$#CmdList) {
       $ServiceData{$ThisService}{+sprintf("%03d-%s", $i, $CmdList[$i])} = $CmdArgList[$i];
   }
}
my @AllServices = sort @TempAllServices;

# Find out what logfiles are defined...
my @logfiles = ();
foreach my $LogfilesDir ("$BaseDir/default.conf", "$BaseDir/dist.conf", "$ConfigDir/conf") {
   if (-d "$LogfilesDir/logfiles") {
      opendir(LOGFILEDIR, "$LogfilesDir/logfiles") or
         die "$LogfilesDir $!";
      while (defined($ThisFile = readdir(LOGFILEDIR))) {
	 if ((-f "$LogfilesDir/logfiles/$ThisFile") && (!grep (/^$ThisFile$/, @logfiles))) {
	     push @logfiles, $ThisFile;
         }
      }
      closedir LOGFILEDIR;
   }
}

for $ThisFile (@logfiles) {
      my $ThisLogFile = $ThisFile;
      if ($ThisLogFile =~ s/\.conf$//i) {
         push @AllLogFiles, $ThisLogFile;
         @ReadConfigNames = ();
         @ReadConfigValues = ();
         @Separators = ();
         push (@Separators, scalar(@ReadConfigNames));
         &ReadConfigFile("$BaseDir/default.conf/logfiles/$ThisFile", "");
         push (@Separators, scalar(@ReadConfigNames));
         &ReadConfigFile("$BaseDir/dist.conf/logfiles/$ThisFile", "");
         push (@Separators, scalar(@ReadConfigNames));
         &ReadConfigFile("$ConfigDir/conf/logfiles/$ThisFile", "");
         push (@Separators, scalar(@ReadConfigNames));
         &ReadConfigFile("$ConfigDir/conf/override.conf", "logfiles/$ThisLogFile");

         @CmdList = ();
         @CmdArgList = ();

         @{$LogFileData{$ThisLogFile}{'logfiles'}} = ();
         @{$LogFileData{$ThisLogFile}{'archives'}} = ();
         for (my $i = 0; $i <= $#ReadConfigNames; $i++) {
            if (grep(/^$i$/, @Separators)) {
               $count = 0;
            }
            my @TempLogFileList;
            if ($ReadConfigNames[$i] eq "logfile") {
               #Lets try and find the logs -mgt
               if ($ReadConfigValues[$i] eq "") {
                  @{$LogFileData{$ThisLogFile}{'logfiles'}} = ();
               } else {
                  if ($ReadConfigValues[$i] !~ m=^/=) {
                     foreach my $dir ("$Config{'logdir'}/", "/var/adm/", "/var/log/", "") {
                        # We glob to obtain filenames.  We reverse in case
                        # we use the decimal suffix (.0, .1, etc.) in filenames
                        #@TempLogFileList = reverse(glob($dir . $ReadConfigValues[$i]));
                        @TempLogFileList = sort{
                           ($b =~ /(\d+)$/) <=> ($a =~ /(\d+)$/) || uc($a) cmp  uc($b)
                        }(glob($dir . $ReadConfigValues[$i]));
                        # And we check for existence once again, since glob
                        # may return the search pattern if no files found.
                        last if (@TempLogFileList && (-e $TempLogFileList[0]));
                     }
                  } else {
                     #@TempLogFileList = reverse(glob($ReadConfigValues[$i]));
                     @TempLogFileList = sort{
                        ($b =~ /(\d+)$/) <=> ($a =~ /(\d+)$/) || uc($a) cmp  uc($b)
                     }(glob($ReadConfigValues[$i]));
                  }

                  # We attempt to remove duplicates.
                  # Same applies to archives, in the next block.
                  foreach my $TempLogFileName (@TempLogFileList) {
                     if (grep(/^\Q$TempLogFileName\E$/,
                           @{$LogFileData{$ThisLogFile}{'logfiles'}})) {
                        if ($Config{'debug'} > 2) {
                           print "Removing duplicate LogFile file $TempLogFileName from $ThisFile configuration.\n";
                        }
                     } else {
                        if (-e $TempLogFileName) {
                           push @{$LogFileData{$ThisLogFile}{'logfiles'}},
                              $TempLogFileName;
                        }
                     }
                  }
               }
            } elsif (($ReadConfigNames[$i] eq "archive") && ( $Config{'archives'} == 1)) {
               if ($ReadConfigValues[$i] eq "") {
                  @{$LogFileData{$ThisLogFile}{'archives'}} = ();
               } else {
                  if ($ReadConfigValues[$i] !~ m=^/=) {
                     foreach my $dir ("$Config{'logdir'}/", "/var/adm/", "/var/log/", "") {
                        # We glob to obtain filenames.  We reverse in case
                        # we use the decimal suffix (.0, .1, etc.) in filenames
                        #@TempLogFileList = reverse(glob($dir . $ReadConfigValues[$i]));
                        @TempLogFileList = sort{
                           ($b =~ /(\d+)$/) <=> ($a =~ /(\d+)$/) || uc($a) cmp  uc($b)
                        }(glob($dir . $ReadConfigValues[$i]));
                        # And we check for existence once again, since glob
                        # may return the search pattern if no files found.
                        last if (@TempLogFileList && (-e $TempLogFileList[0]));
                     }
                  } else {
                     #@TempLogFileList = reverse(glob($ReadConfigValues[$i]));
                     @TempLogFileList = sort{
                        ($b =~ /(\d+)$/) <=> ($a =~ /(\d+)$/) || uc($a) cmp  uc($b)
                     }(glob($ReadConfigValues[$i]));
                  }

                  # We attempt to remove duplicates.  This time we also check
                  # against the LogFile declarations.
                  foreach my $TempLogFileName (@TempLogFileList) {
                     if (grep(/^\Q$TempLogFileName\E$/,
                           @{$LogFileData{$ThisLogFile}{'archives'}}) ||
                         grep(/^\Q$TempLogFileName\E$/,
                           @{$LogFileData{$ThisLogFile}{'logfiles'}}) ) {
                        if ($Config{'debug'} > 2) {
                           print "Removing duplicate Archive file $TempLogFileName from $ThisFile configuration.\n";
                        }
                     } else {
                        if (-e $TempLogFileName) {
                           push @{$LogFileData{$ThisLogFile}{'archives'}},
                              $TempLogFileName;
                           }
                     }
                  }
               }

            } elsif ($ReadConfigNames[$i] =~ /^\*/) {
               if ($count == 0) {
                  @CmdList = ();
                  @CmdArgList = ();
               }
               $count++;
               push (@CmdList, $ReadConfigNames[$i]);
               push (@CmdArgList, $ReadConfigValues[$i]);
            } else {
               $LogFileData{$ThisLogFile}{$ReadConfigNames[$i]} = $ReadConfigValues[$i];
            }
            for my $i (0..$#CmdList) {
                $LogFileData{$ThisLogFile}{+sprintf("%03d-%s", $i, $CmdList[$i])} = $CmdArgList[$i];
            }
         }
      }
}

# Find out what shared functions are defined...
opendir(SHAREDDIR, "$BaseDir/scripts/shared") or die "$BaseDir/scripts/shared/, $!\n";
while (defined($ThisFile = readdir(SHAREDDIR))) {
   unless (-d "$BaseDir/scripts/shared/$ThisFile") {
      push @AllShared, lc($ThisFile);
   }
}
closedir(SHAREDDIR);

if ($Config{'debug'} > 5) {
   print "\nAll Services:\n";
   &PrintStdArray(@AllServices);
   print "\nAll Log Files:\n";
   &PrintStdArray(@AllLogFiles);
   print "\nAll Shared:\n";
   &PrintStdArray(@AllShared);
}

#############################################################################

# Time to expand @ServiceList, using @LogFileList if defined...

if ((scalar @ServiceList > 0) && (grep /^all$/i, @ServiceList)) {
    # This means we are doing *all* services ... but excluding some
    my %tmphash;
    foreach my $item (@AllServices) {
      $tmphash{lc $item} = "";
    }
    foreach my $service (@ServiceList) {
      next if $service =~ /^all$/i;
      if ($service =~ /^\-(.+)$/) {
          my $offservice = lc $1;
          if (! grep (/^$offservice$/, @AllServices)) {
             die "Nonexistent service to disable: $offservice\n";
          }
          if (exists $tmphash{$offservice}) {
             delete $tmphash{$offservice};
          }

      } else {
          die "Wrong configuration entry for \"Service\", if \"All\" selected, only \"-\" items are allowed\n";
      }
    }
    @ServiceList = ();
    foreach my $keys (keys %tmphash) {
      push @ServiceList, $keys;
    }
    @LogFileList = ();
} else {
   my $ThisOne;
   while (defined($ThisOne = pop @LogFileList)) {
      unless ($LogFileData{$ThisOne}) {
         die "Logwatch is not configured to use logfile: $ThisOne\n";
      }
      foreach my $ThisService (keys %ServiceData) {
         for (my $i = 0; $i <= $#{$ServiceData{$ThisService}{'logfiles'}}; $i++) {
            if ( $ServiceData{$ThisService}{'logfiles'}[$i] eq $ThisOne ) {
               push @ServiceList,$ThisService;
            }
         }
      }
   }
   @TempServiceList = sort @ServiceList;
   @ServiceList = ();
   my $LastOne = "";
   while (defined($ThisOne = pop @TempServiceList)) {
      unless ( ($ThisOne eq $LastOne) or ($ThisOne eq 'all') or ($ThisOne =~ /^-/)) {
         unless ($ServiceData{$ThisOne}) {
            die "Logwatch does not know how to process service: $ThisOne\n";
         }
         push @ServiceList, $ThisOne;
      }
      $LastOne = $ThisOne;
   }
}

# Now lets fill up @LogFileList again...
foreach my $ServiceName (@ServiceList) {
   foreach my $LogName ( @{$ServiceData{$ServiceName}{'logfiles'} } ) {
      unless ( grep m/^$LogName$/, @LogFileList ) {
         push @LogFileList, $LogName;
      }
   }
}

if ($Config{'debug'} > 7) {
   print "\n\nAll Service Data:\n";
   &PrintServiceData();
   print "\nServices that will be processed:\n";
   &PrintStdArray(@ServiceList);
   print "\n\n";
   print "\n\nAll LogFile Data:\n";
   &PrintLogFileData();
   print "\nLogFiles that will be processed:\n";
   &PrintStdArray(@LogFileList);
   print "\n\n";
}

#############################################################################

# check for existence of previous logwatch directories

opendir(TMPDIR, $Config{'tmpdir'}) or die "$Config{'tmpdir'} $!";
my @old_dirs = grep { /^logwatch\.\w{8}$/ && -d "$Config{'tmpdir'}/$_" }
   readdir(TMPDIR);
if (@old_dirs) {
   print "You have old files in your logwatch tmpdir ($Config{'tmpdir'}):\n\t";
   print join("\n\t", @old_dirs);
   print "\nThe directories listed above were most likely created by a\n";
   print "logwatch run that failed to complete successfully.  If so, you\n";
   print "may delete these directories.\n\n";
}
closedir(TMPDIR);

if (!-w $Config{'tmpdir'}) {
   my $err_str = "You do not have permission to create a temporary directory";
   $err_str .= " under $Config{'tmpdir'}.";
   if ($> !=0) {
      $err_str .= "  You are not running as superuser.";
   }
   $err_str .= "\n";
   die $err_str;
}

#Set very strict permissions because we deal with security logs
umask 0177;
#Making temp dir with File::Temp  -mgt
my $cleanup = 0;
if ($Config{'debug'} < 100) {
   $cleanup = 1;
}

my $TempDir = tempdir( 'logwatch.XXXXXXXX', DIR => $Config{tmpdir},
      CLEANUP => $cleanup );

if ($Config{'debug'}>7) {
      print "\nMade Temp Dir: " . $TempDir . " with tempdir\n";
}

unless ($TempDir =~ m=/$=) {
    $TempDir .= "/";
}

#############################################################################

# Set up the environment...

$ENV{'LOGWATCH_DATE_RANGE'} = $Config{'range'};
$ENV{'LOGWATCH_GLOBAL_DETAIL'} = $Config{'detail'};
$ENV{'LOGWATCH_OUTPUT_TYPE'} = $Config{'output'}; #8.0
$ENV{'LOGWATCH_FORMAT_TYPE'} = $Config{'format'}; #8.0
$ENV{'LOGWATCH_DEBUG'} = $Config{'debug'};
$ENV{'LOGWATCH_TEMP_DIR'} = $TempDir;
$ENV{'LOGWATCH_NUMERIC'} = $Config{'numeric'};
$ENV{'HOSTNAME'} = $Config{'hostname'};
$ENV{'OSname'} = $OSname;

#split and splitmail also play with LOGWATCH_ONLY_HOSTNAME which is not shown by debug
if ($Config{'hostlimit'}) {
   #Pass the list to ENV with out touching it
   $ENV{'LOGWATCH_ONLY_HOSTNAME'} = $Config{'hostlimit'};
}

if ($Config{'debug'}>4) {
   foreach ('LOGWATCH_DATE_RANGE', 'LOGWATCH_GLOBAL_DETAIL', 'LOGWATCH_OUTPUT_TYPE',
            'LOGWATCH_FORMAT_TYPE', 'LOGWATCH_TEMP_DIR', 'LOGWATCH_DEBUG', 'LOGWATCH_ONLY_HOSTNAME') {
      if ($ENV{$_}) {
         print "export $_='$ENV{$_}'\n";
      }
   }
}

my $LibDir = "$BaseDir/lib";
if ($ENV{PERL5LIB}) {
    # User dirs should be able to override this setting
    $ENV{PERL5LIB} = "$ENV{PERL5LIB}:$LibDir";
} else {
    $ENV{PERL5LIB} = $LibDir;
}

#############################################################################

unless ($Config{'logdir'} =~ m=/$=) {
   $Config{'logdir'} .= "/";
}

# Okay, now it is time to do pre-processing on all the logfiles...

my @EnvList = ();
my $LogFile;
foreach $LogFile (@LogFileList) {
   next if ($LogFile eq 'none');
	if (!defined($LogFileData{$LogFile}{'logfiles'})) {
		print "*** Error: There is no logfile defined. Do you have a $ConfigDir/conf/logfiles/" . $LogFile . ".conf file ?\n";
		next;
	}

   @FileList = $TempDir . $LogFile . "-archive";
   push @FileList, @{$LogFileData{$LogFile}{'logfiles'}};
   my $DestFile =  $TempDir . $LogFile . "-archive";
   my $Archive;
   foreach $Archive (@{$LogFileData{$LogFile}{'archives'}}) {
      if ($Archive =~ /'/) {
         print "File $Archive has invalid embedded quotes.  File ignored.\n";
	 next;
      }
      my $CheckTime;
      # We need to find out what's the earliest log we need
      my @time_t = TimeBuild();
      if ($Config{'range'} eq 'all') {
         if ($Config{'archives'} == 0) {
            # range is 'all', but we don't get archive files
   	      $CheckTime = time;
         } else {
            # range is 'all', and we get all archive files
   	      $CheckTime = 0;
         }
      } elsif ($time_t[0]) {
         # range is something else, and we need to get one
       # day ahead. A day has 86400 seconds.  (We double
       # that to deal with different timezones.)
       $CheckTime = $time_t[0] - 86400*2;
      } else {
         # range is wrong
         print STDERR "ERROR: Range \'$Config{'range'}\' not understood\n";
         RangeHelpDM();
         exit 1;
      }

      #Archives are cat'd without any filters then cat'd along with the normal log file
      my @FileStat = stat($Archive);
      if ($CheckTime <= ($FileStat[9])) {
         if (($Archive =~ m/gz$/) && (-f "$Archive") && (-s "$Archive")) {
            my $arguments = "'${Archive}' >> $DestFile";
            system("$Config{'pathtozcat'} $arguments") == 0
               or die "system '$Config{'pathtozcat'} $arguments' failed: $?"
         } elsif (($Archive =~ m/bz2$/) && (-f "$Archive") && (-s "$Archive")) {
            my $arguments = "'${Archive}' 2>/dev/null >> $DestFile";
            system("$Config{'pathtobzcat'} $arguments") == 0
               or die "system '$Config{'pathtobzcat'} $arguments' failed: $?"
         } elsif ((-f "$Archive") && (-s "$Archive")) {
            my $arguments = "'${Archive}'  >> $DestFile";
            system("$Config{'pathtocat'} $arguments") == 0
               or die "system '$Config{'pathtocat'} $arguments' failed: $?"
         } #End if/elsif existence
      } #End if $CheckTime

   } #End Archive
   my $FileText = "";

   foreach my $ThisFile (@FileList) {
      #Existence check for files -mgt
      next unless (-f $ThisFile);
      if ($ThisFile =~ /'/) {
         print "File $ThisFile has invalid embedded quotes.  File ignored.\n";
	 next;
      }
      if (! -r $ThisFile) {
         print "File $ThisFile is not readable.  Check permissions.";
         if ($> != 0) {
            print "  You are not running as superuser.";
            }
         print "\n";
         next;
      }
      #FIXME - We have a bug report for filenames with spaces, can be caught here needs test -mgt
      $FileText .= ("'" . $ThisFile . "' ");
   } #End foreach ThisFile

   # remove the ENV entries set by previous service
   foreach my $Parm (@EnvList) {
      delete $ENV{$Parm};
   }
   @EnvList = ();

   my $FilterText = " ";
   foreach (sort keys %{$LogFileData{$LogFile}}) {
      my $cmd = $_;
      if ($cmd =~ s/^\d+-\*//) {
         if (-f "$ConfigDir/scripts/shared/$cmd") {
            $FilterText .= ("| $PerlVersion $ConfigDir/scripts/shared/$cmd '$LogFileData{$LogFile}{$_}'" );
         } elsif (-f "$BaseDir/scripts/shared/$cmd") {
            $FilterText .= ("| $PerlVersion $BaseDir/scripts/shared/$cmd '$LogFileData{$LogFile}{$_}'" );
         } else {
	     die "Cannot find shared script $cmd\n";
         }
      } elsif ($cmd =~ s/^\$//) {
         push @EnvList, $cmd;
         $ENV{$cmd} = $LogFileData{$LogFile}{$_};
         if ($Config{'debug'}>4) {
            print "export $cmd='$LogFileData{$LogFile}{$_}'\n";
         }
      }
   }

   #Hostlimit filter need to add ability to negate this use "NoHostFilter = Yes" in logfile like samba -mgt
   if ( ($Config{'hostlimit'}) && (!$LogFileData{$LogFile}{'nohostfilter'}) ) {
      #Pass the list to ENV with out touching it
      $ENV{'LOGWATCH_ONLY_HOSTNAME'} = $Config{'hostlimit'};
      $FilterText .= ("| $PerlVersion $BaseDir/scripts/shared/onlyhost");
   }

   if (opendir (LOGDIR, "$ConfigDir/scripts/logfiles/" . $LogFile)) {
      foreach (sort readdir(LOGDIR)) {
         unless ( -d "$ConfigDir/scripts/logfiles/$LogFile/$_") {
            $FilterText .= ("| $PerlVersion $ConfigDir/scripts/logfiles/$LogFile/$_");
         }
      }
      closedir (LOGDIR);
   }
   if (opendir (LOGDIR, "$BaseDir/scripts/logfiles/" . $LogFile)) {
      foreach (sort readdir(LOGDIR)) {
         unless (( -d "$BaseDir/scripts/logfiles/$LogFile/$_") or
                 # if in ConfigDir, then the ConfigDir version is used
                 ( -f "$ConfigDir/scripts/logfiles/$LogFile/$_")) {
            $FilterText .= ("| $PerlVersion $BaseDir/scripts/logfiles/$LogFile/$_");
         }
      }
      closedir (LOGDIR);
   }

   #Instead of trying to cat non-existent logs we test for it above -mgt
   if ($FileText) {
      my $Command = $FileText . $FilterText . ">" . $TempDir . $LogFile;
      if ($Config{'debug'}>4) {
         print "\nPreprocessing LogFile: " . $LogFile . "\n" . $Command . "\n";
      }
      if ($LogFile !~ /^[-_\w\d]+$/) {
         print STDERR "Unexpected filename: [[$LogFile]]. Not used\n"
      } else {
         #System call does the log processing
         system("$Config{'pathtocat'} $Command") == 0
            or die "system '$Config{'pathtocat'} $Command' failed: $?"
      }
   }
}

#populate the host lists if we're splitting hosts
#It seems this is run after the file is parsed so it is done 2 times?
#Can it be put inline with the above filters?
my @hosts;
if ($Config{'hostformat'} ne "none") { #8.0
   my $newlogfile;
   my @logarray;
   opendir (LOGDIR,$TempDir) || die "Cannot open dir";
   @logarray = readdir(LOGDIR);
   closedir (LOGDIR);
   my $ecpcmd = ("| $PerlVersion $BaseDir/scripts/shared/hostlist");
   #Note hostlist and hosthash [which is never used] exist to build list of host names seen
   foreach $newlogfile (@logarray) {
     my $eeefile = ("$TempDir" . "$newlogfile");
     if ((!(-d $eeefile)) && (!($eeefile =~ m/-archive/))) {
         system("$Config{'pathtocat'} $eeefile $ecpcmd") == 0
            or die "system '$Config{'pathtocat'} $eeefile $ecpcmd' failed: $?"
     }
   }
   #read in the final host list
   open (HOSTFILE,"$TempDir/hostfile") || die $!;
   @hosts = <HOSTFILE>;
   close (HOSTFILE);
   chomp @hosts;
   #fixme check the sort?
   #@hosts = sort(@hosts);
}

#############################################################################

my $report_finish = "\n ###################### Logwatch End ######################### \n\n";
my $printing = '';
my $emailopen = '';

####################################################################

#Call Parse logs
if ($Config{'hostformat'} ne "none") {
   my $Host;
   foreach $Host (@hosts) {
      $printing = '';
      $ENV{'LOGWATCH_ONLY_HOSTNAME'} = $Host;
      $Config{'hostname'} = $Host; #resetting hostname here makes it appear in output header -mgt
      parselogs();
   } # ECP
} else {
   parselogs();
}

#Close Filehandle is needed -mgt
close(OUTFILE) unless ($Config{'output'} eq "stdout");
#############################################################################

exit(0);

#############################################################################
#END MAIN
#############################################################################

######################################################################
#sub getInt
#Notes: Called by CleanVars
######################################################################
sub getInt {
   my $word = shift;
   unless (defined($word)) { return $word; }
   my $tmpWord = lc $word;
   $tmpWord =~ s/\W//g;
   return $wordsToInts{$tmpWord} if (defined $wordsToInts{$tmpWord});
   unless ($word =~ s/^"(.*)"$/$1/) {
      return lc $word;
   }
   return $word;
}

######################################################################
#sub CleanVars
#Notes: Called during #Load CONFIG, READ OPTIONS, make adjustments
######################################################################
sub CleanVars {
   foreach (keys %Config) {
      unless (defined $Config{$_} and $_ eq "hostname") {
         $Config{$_} = getInt($Config{$_});
      }
   }
}

######################################################################
#sub PrintStdArray
#
######################################################################
sub PrintStdArray (@) {
   my @ThisArray = @_;
   my $i;
   for ($i=0;$i<=$#ThisArray;$i++) {
      print "[" . $i . "] = " . $ThisArray[$i] . "\n";
   }
}

######################################################################
#sub PrintConfig
#
######################################################################
sub PrintConfig () {
   # for debugging, print out config...
   foreach (keys %Config) {
      print $_ . ' -> ' . $Config{$_} . "\n";
   }
   print "Service List:\n";
   &PrintStdArray(@ServiceList);
   print "\n";
   print "LogFile List:\n";
   &PrintStdArray(@LogFileList);
   print "\n\n";
}

######################################################################
#sub PrintServiceData
#
######################################################################
# for debugging...
sub PrintServiceData () {
   my ($ThisKey1,$ThisKey2,$i);
   foreach $ThisKey1 (keys %ServiceData) {
      print "\nService Name: " . $ThisKey1 . "\n";
      foreach $ThisKey2 (keys %{$ServiceData{$ThisKey1}}) {
         next unless ($ThisKey2 =~ /^\d+-/);
         print "   $ThisKey2 = $ServiceData{$ThisKey1}{$ThisKey2}\n";
      }
      for ($i=0;$i<=$#{$ServiceData{$ThisKey1}{'logfiles'}};$i++) {
         print "   Logfile = " . $ServiceData{$ThisKey1}{'logfiles'}[$i] . "\n";
      }
   }
}

######################################################################
#sub PrintLogFileData
#
######################################################################
# for debugging...
sub PrintLogFileData () {
   my ($ThisKey1,$ThisKey2,$i);
   foreach $ThisKey1 (keys %LogFileData) {
      print "\nLogfile Name: " . $ThisKey1 . "\n";
      foreach $ThisKey2 (keys %{$LogFileData{$ThisKey1}}) {
         next unless ($ThisKey2 =~ /^\d+-/);
         print "   $ThisKey2 = $LogFileData{$ThisKey1}{$ThisKey2}\n";
      }
      for ($i=0;$i<=$#{$LogFileData{$ThisKey1}{'logfiles'}};$i++) {
         print "   Logfile = " . $LogFileData{$ThisKey1}{'logfiles'}[$i] . "\n";
      }
      for ($i=0;$i<=$#{$LogFileData{$ThisKey1}{'archives'}};$i++) {
         print "   Archive = " . $LogFileData{$ThisKey1}{'archives'}[$i] . "\n";
      }
      if ($LogFileData{$ThisKey1}{'nohostfilter'}) {
         print "   NoHostFilter = " . $LogFileData{$ThisKey1}{'nohostfilter'} . "\n";
      }
   }
}

######################################################################
#sub ReadConfigFile
#
######################################################################
sub ReadConfigFile {
   my $FileName = $_[0];
   my $Prefix = $_[1];

   if ( ! -f $FileName ) {
      return(0);
   }

   if ($Config{'debug'} > 5) {
      print "ReadConfigFile: Opening " . $FileName . "\n";
   }
   open (READCONFFILE, $FileName) or die "Cannot open file $FileName: $!\n";
   my $line;
   while ($line = <READCONFFILE>) {
      if ($Config{'debug'} > 9) {
         print "ReadConfigFile: Read Line: " . $line;
      }
      $line =~ s/\#.*\\\s*$/\\/;
      $line =~ s/\#.*$//;
      next if ($line =~ /^\s*$/);

      if ($Prefix) {
         next if ($line !~ m/\Q$Prefix:\E/);
         $line =~ s/\Q$Prefix:\E//;
      }

      if ($line =~ s/\\\s*$//) {
	  $line .= <READCONFFILE>;
          redo unless eof(READCONFFILE);
      }

      my ($name, $value) = split /=/, $line, 2;
      $name =~ s/^\s+//; $name =~ s/\s+$//;
      if ($value) { $value =~ s/^\s+//; $value =~ s/\s+$//; }
      else { $value = ''; }

      push @ReadConfigNames, lc $name;
      push @ReadConfigValues, getInt $value;
      if ($Config{'debug'} > 7) {
         print "ReadConfigFile: Name=" . $name . ", Value=" . $value . "\n";
      }
   }
   close READCONFFILE;
}

#########################################################################
#sub Usage
#
#########################################################################
sub Usage () {
   # Show usage for this program
   print "\nUsage: $0 [--detail <level>] [--logfile <name>] [--output <output_type>]\n" .
      "   [--format <format_type>] [--encode <enconding>] [--numeric]\n" .
      "   [--mailto <addr>] [--archives] [--range <range>] [--debug <level>]\n" .
      "   [--filename <filename>] [--help|--usage] [--version] [--service <name>]\n" .
      "   [--hostformat <host_format type>] [--hostlimit <host1,host2>] [--html_wrap <num_characters>]\n\n";
   print "--detail <level>: Report Detail Level - High, Med, Low or any #.\n";
   print "--logfile <name>: *Name of a logfile definition to report on.\n";
   print "--logdir <name>: Name of default directory where logs are stored.\n";
   print "--service <name>: *Name of a service definition to report on.\n";
   print "--output <output type>: Report Output - stdout [default], mail, file.\n"; #8.0
   print "--format <formatting>: Report Format - text [default], html.\n"; #8.0
   print "--encode <encoding>: Enconding to use - none [default], base64.\n"; #8.0
   print "--mailto <addr>: Mail report to <addr>.\n";
   print "--archives: Use archived log files too.\n";
   print "--filename <filename>: Used to specify they filename to save to. --filename <filename> [Forces output to file].\n";
   print "--range <range>: Date range: Yesterday, Today, All, Help\n";
   print "                             where help will describe additional options\n";
   print "--numeric: Display addresses numerically rather than symbolically and numerically\n";
   print "           (saves  a  nameserver address-to-name lookup).\n";
   print "--debug <level>: Debug Level - High, Med, Low or any #.\n";
   print "--hostformat: Host Based Report Options - none [default], split, splitmail.\n"; #8.0
   print "--hostlimit: Limit report to hostname - host1,host2.\n"; #8.0
   print "--html_wrap <num_characters>: Default is 80.\n";
   print "--version: Displays current version.\n";
   print "--help: This message.\n";
   print "--usage: Same as --help.\n";
   print "* = Switch can be specified multiple times...\n\n";
   exit (99);
}
############################################################################
#END sub Usage
#############################################################################

#############################################################################
#sub initprint
#
#############################################################################
sub initprint {
   return if $printing;

   my $OStitle;
   $OStitle = $OSname;
   $OStitle = "Solaris" if ($OSname eq "SunOS" && $release >= 2);

   if ($Config{'output'} eq "stdout") { #8.0 start with others?
      *OUTFILE = *STDOUT;
   } elsif ($Config{'output'} eq "file") {
      open(OUTFILE,">>" . $Config{'filename'}) or die "Can't open output file: $Config{'filename'} $!\n";
   } else {
   #fixme mailto
      if (($Config{'hostformat'} eq "splitmail") || ($emailopen eq "")) {
         #Use mailer = in logwatch.conf to set options. Default should be "sendmail -t"
         #In theory this should be able to handle many different mailers. I might need to add
         #some filter code on $Config{'mailer'} to make it more robust. -mgt
         open(OUTFILE,"|$Config{'mailer'}") or die "Can't execute $Config{'mailer'}: $!\n";
         my $mailto = $Config{"mailto_$Config{'hostname'}"};
         $mailto = $Config{'mailto'} unless $mailto;
         for my $to (split(/ /, $mailto)) {
            print OUTFILE "To: $to\n";
         }
         print OUTFILE "From: $Config{'mailfrom'}\n";
         #If $Config{'subject'} exists lets use it.
         #This does not allow for variable expansion as the default below does -mgt
         if ($Config{'subject'}) {
            print OUTFILE "Subject: $Config{'subject'}\n";
         } else {
            print OUTFILE "Subject: Logwatch for $Config{'hostname'} (${OStitle})\n";
         }
         #Add MIME
         $out_mime = "MIME-Version: 1.0\n";
         #Config{encode} switch
         if ( $Config{'encode'} eq "base64" ) {
            $out_mime .= "Content-transfer-encoding: base64\n";
         } else {
            $out_mime .= "Content-Transfer-Encoding: 7bit\n";
         }
         #Config{output} html
         if ( $Config{'format'} eq "html" ) {
            $out_mime .= "Content-Type: text/html; charset=\"iso-8859-1\"\n\n";
         } else {
            $out_mime .= "Content-Type: text/plain; charset=\"iso-8859-1\"\n\n";
         }

         if ($Config{'hostformat'} eq "split") { #8.0 check hostlimit also? or ne none?
            print OUTFILE "Reporting on hosts: @hosts\n";
         }
         $emailopen = 'y';
      } #End if hostformat || emailopen
   } #End if printing/save/else
   $printing = 'y';

   # simple parse of the dates
   my $simple_timematch = &TimeFilter(" %Y-%b-%d %Hh %Mm %Ss ");
   my @simple_range = split(/\|/, $simple_timematch);
   if ($#simple_range > 1) {
       # delete all array entries, except first and last
       splice(@simple_range, 1, $#simple_range-1);
   }
   for (my $range_index=0; $range_index<$#simple_range+1; $range_index++) {
       $simple_range[$range_index] =~ s/\.\.[hms]//g;
       $simple_range[$range_index] =~ s/\.//g;
       $simple_range[$range_index] =~ tr/--//s;
       $simple_range[$range_index] =~ s/ -|- //;
       $simple_range[$range_index] =~ tr/ //s;
   }

   my $print_range = join("/",@simple_range);

   $index_par++;
   if ( $Config{'format'} eq "html" ) {
      &output( $index_par, "LOGWATCH Summary" . (($Config{'hostformat'} ne "none") ? ": $Config{'hostname'}" : ""), "start");
      &output( $index_par, "       Logwatch Version: $Version ($VDate)\n", "line");
   }       else {
      &output( $index_par, "\n ################### Logwatch $Version ($VDate) #################### \n", "line");
   }

   &output( $index_par, "       Processing Initiated: " . localtime(time) . "\n", "line");
   &output( $index_par, "       Date Range Processed: $Config{'range'}\n", "line");
   &output( $index_par, "                             $print_range\n", "line")
      if ($Config{'range'} ne 'all');
   &output( $index_par, "                             Period is " . &GetPeriod() . ".\n", "line")
      if ($Config{'range'} ne 'all');
   &output( $index_par, "       Detail Level of Output: $Config{'detail'}\n", "line");
   &output( $index_par, "       Type of Output/Format: $Config{'output'} / $Config{'format'}\n", "line");
   &output( $index_par, "       Logfiles for Host: $Config{'hostname'}\n", "line");

   if ( $Config{'format'} eq "html" ) {
      &output( $index_par, "\n", "stop");
   } else {
      &output( $index_par, " ################################################################## \n", "line");
   }

}
####################################################################
#END sub initprint
####################################################################

###################################################################
#sub parselogs
#
###################################################################
sub parselogs {
   my $Service;

   #Load our ignore file order is [assume normal install]  /etc/conf, /usr/share/logwatch/dist.conf and then default.conf -mgt
   my @IGNORE;
   if ( -e "$ConfigDir/conf/ignore.conf") {
      open( IGNORE, "$ConfigDir/conf/ignore.conf" )  or return undef;
      @IGNORE = grep {!/(^#|^\s+$)/} <IGNORE>;
      close IGNORE;
   } elsif ( -e "$BaseDir/dist.conf/ignore.conf") {
      open( IGNORE, "$BaseDir/dist.conf/ignore.conf" )  or return undef;
      @IGNORE = grep {!/(^#|^\s+$)/} <IGNORE>;
      close IGNORE;
   } elsif ( -e "$BaseDir/default.conf/ignore.conf") {
      open( IGNORE, "$BaseDir/default.conf/ignore.conf" )  or return undef;
      @IGNORE = grep {!/(^#|^\s+$)/} <IGNORE>;
      close IGNORE;
   }

   my @EnvList = ();

   # first sort alphabetically, and then based on DisplayOrder
   foreach $Service ( sort {$ServiceData{$a}{'displayorder'} <=>
                            $ServiceData{$b}{'displayorder'}     } (sort @ServiceList)) {

      my $Ignored = 0;
      $ENV{'PRINTING'} = $printing;
      if (defined $ServiceData{$Service}{'detail'}) {
	      $ENV{'LOGWATCH_DETAIL_LEVEL'} = $ServiceData{$Service}{'detail'};
      } else {
         $ENV{'LOGWATCH_DETAIL_LEVEL'} = $ENV{'LOGWATCH_GLOBAL_DETAIL'};
      }
      @FileList = @{$ServiceData{$Service}{'logfiles'}};
      my $FileText = "";
      foreach $ThisFile (@FileList) {
         if (-s $TempDir . $ThisFile) {
            $FileText .= ( $TempDir . $ThisFile . " ");
         }
      }

      # remove the ENV entries set by previous service
      foreach my $Parm (@EnvList) {
         delete $ENV{$Parm};
      }
      @EnvList = ();

      my $FilterText = " ";
      foreach (sort keys %{$ServiceData{$Service}}) {
         my $cmd = $_;
         if ($cmd =~ s/^\d+-\*//) {
            if (-f "$ConfigDir/scripts/shared/$cmd") {
               $FilterText .= ("$PerlVersion $ConfigDir/scripts/shared/$cmd '$ServiceData{$Service}{$_}' |" );
            } elsif (-f "$BaseDir/scripts/shared/$cmd") {
               $FilterText .= ("$PerlVersion $BaseDir/scripts/shared/$cmd '$ServiceData{$Service}{$_}' |" );
            } else {
               die "Cannot find shared script $cmd\n";
            }
         } elsif ($cmd =~ s/^\$//) {
            $ENV{$cmd} = $ServiceData{$Service}{$_};
            push @EnvList, $cmd;
            if ($Config{'debug'}>4) {
               print "export $cmd='$ServiceData{$Service}{$_}'\n";
            }
         }
      }
      # ECP - insert the host stripping now
      my $HostStrip = " ";
      if ($Config{'hostformat'} ne "none") { #8.0
         ###############################################
         # onlyhost reads $ENV{'LOGWATCH_ONLY_HOSTNAME'} and uses it to try and match
         # based on $line =~ m/^... .. ..:..:.. $hostname\b/io
         ###############################################
         $HostStrip = "$PerlVersion $BaseDir/scripts/shared/onlyhost";
      }
      my $ServiceExec = "$BaseDir/scripts/services/$Service";
      if (-f "$ConfigDir/scripts/services/$Service") {
         $ServiceExec = "$ConfigDir/scripts/services/$Service";
      } else {
         $ServiceExec = "$BaseDir/scripts/services/$Service";
      }

      if (-f $ServiceExec ) {
         #If shell= was set in service.conf we will use it
         if ($ServiceData{$Service}{shell}) {
            my $shelltest = $ServiceData{$Service}{shell};
            $shelltest =~ s/([\w\/]+).*/$1/;
            if (-e "$shelltest") {
               $FilterText .= "$ServiceData{$Service}{shell} $ServiceExec";
            } else {
               die "Can't use $ServiceData{$Service}{shell} for $ServiceExec";
            }
         } else {
            $FilterText .= "$PerlVersion $ServiceExec";
         } #End if shell
      }
      else {
         die "Can't open: " . $ServiceExec;
      }

      my $Command = '';
      if ($FileList[0] eq 'none') {
         $Command = " $FilterText 2>&1 ";
      } elsif ($FileText) {
         if ($HostStrip ne " ") {
            $Command = " ( $Config{'pathtocat'} $FileText | $HostStrip | $FilterText) 2>&1 ";
         } else {
            $Command = " ( $Config{'pathtocat'} $FileText | $FilterText) 2>&1 ";
         }
      }

      if ($Command) {
         if ($Config{'debug'}>4) {
            print "\nProcessing Service: " . $Service . "\n" . $Command . "\n";
         }
         open (TESTFILE,$Command . " |");
         my $ThisLine;
         my $has_output = 0;
         LINE: while (defined ($ThisLine = <TESTFILE>)) {
            next LINE if ((not $printing) and $ThisLine =~ /^\s*$/);
            IGNORE: for my $ignore_filter (@IGNORE) {
               chomp $ignore_filter;
               if ($ThisLine =~ m/$ignore_filter/) {
                  $Ignored++;
                  next LINE;
                  }
            }
            &initprint();
            if (($has_output == 0) and ($ServiceData{$Service}{'title'})) {
               $index_par++;
               &output($index_par, $ServiceData{$Service}{'title'}, "start" );
               my $BeginVar;
               if ($ENV{'LOGWATCH_GLOBAL_DETAIL'} == $ENV{'LOGWATCH_DETAIL_LEVEL'}) {
                  $BeginVar = "Begin";
               } else {
                  $BeginVar = "Begin (detail=" . $ENV{'LOGWATCH_DETAIL_LEVEL'} . ")";
               }
               if ( $Config{'format'} eq "html" ) {
               #BODY <!-- SERVICE START -->
                   #&output( $index_par, "\n <h2>$ServiceData{$Service}{'title'}</h2>\n", "header");
               } else {
                   &output( $index_par, "\n --------------------- $ServiceData{$Service}{'title'} $BeginVar ------------------------ \n\n", "line");
               }
               $has_output = 1;
            }
            &output( $index_par, $ThisLine, "line");
         }
         close (TESTFILE);

         if ($has_output and $ServiceData{$Service}{'title'}) {
            if ( $Config{'format'} eq "html" ) {
                if ( ($Ignored > 0) && ($Config{'supress_ignores'} == 0) ) {  &output( $index_par, "\n $Ignored Ignored Lines\n", "header"); };
                #&output( $index_par,  "\n <h3><font color=\"blue\">$ServiceData{$Service}{'title'} End </font></h3>\n", "header");
            } else {
                if ( ($Ignored > 0) && ($Config{'supress_ignores'} == 0) ) { &output( $index_par, "\n $Ignored Ignored Lines\n", "line"); };
                &output( $index_par,  "\n ---------------------- $ServiceData{$Service}{'title'} End ------------------------- \n\n", "line");
            }
            &output( $index_par, "\n", "stop");
         }
      }
   }

   #HTML should be external to logwatch.pl -mgt
   #These are steps only needed for HTML output
   if ( $Config{'format'} eq "html" ) {
      #HEADER
      #Setup temp Variables to swap
      my %HTML_var;
      $HTML_var{Version} = "$Version";
      $HTML_var{VDate} = "$VDate";
      #open template this needs to allow directory override like the rest of the confs
      open(HEADER, "$Config{html_header}") || die "Can not open HTML Header at $Config{html_header}: $!\n";
      my @header = <HEADER>;
      close HEADER;
      #Expand variables... There must be a better way -mgt
      for my $header_line (@header) {
         $header_line =~ s/\$([\w\_\-\{\}\[\]]+)/$HTML_var{$1}/g;
         $out_head .= $header_line;
      }

      #FOOTER
      #open template this needs to allow directory override like the rest of the confs
      open(FOOTER, "$Config{html_footer}") || die "Can not open HTML Footer at $Config{html_header}: $!\n";
      my @footer = <FOOTER>;
      close FOOTER;
      #Expand variables... There must be a better way -mgt
      for my $footer_line (@footer) {
         $footer_line =~ s/\$([\w\_\-\{\}\[\]]+)/$HTML_var{$1}/g;
         $out_foot .=  $footer_line;
      }

      #Set up out_reference
      &output("ul","<a name=top><ul>", "ref_extra") if defined( $index_par );
      foreach ( 0 .. $index_par ) {
         &output($_,$reports[$_], "ref") if defined( $reports[$_] );
      }
      &output("ul","</ul></a>", "ref_extra") if defined( $index_par );

   }

   if ( $Config{'format'} eq "html" ) {
      $index_par++;
      &output( $index_par,  "Logwatch Ended at " . localtime(time) , "start" );
      &output( $index_par, "\n", "stop");
   } else {
      &output( $index_par, $report_finish, "line") if ($printing);
   }

#Printing starts here $out_mime $out_head $out_reference $out_body $out_foot
   print OUTFILE $out_mime if $out_mime;
   if ( $Config{'encode'} eq "base64" ) {
      print OUTFILE encode_base64($out_head) if $out_head;
      print OUTFILE encode_base64($out_reference) if $out_reference;
      foreach ( 0 .. $index_par ) {
         print OUTFILE encode_base64($out_body{$_}) if defined( $out_body{$_} );
#fixme
         $out_body{$_} = ''; #We should track this down out_body could be an array instead also -mgt
      }
      print OUTFILE encode_base64($out_foot) if $out_foot;
   } else {
      print OUTFILE $out_head if $out_head;
      print OUTFILE $out_reference if $out_reference;
      foreach ( 0 .. $index_par ) {
         print OUTFILE $out_body{$_} if defined( $out_body{$_} );
         $out_body{$_} = '';
      }
      print OUTFILE $out_foot if $out_foot;
   }
#ends here

   if ($Config{'hostformat'} eq "splitmail") { #8.0
      $out_foot = '';
      $out_head = '';
      $out_mime = '';
      $out_reference = '';
      @reports = ();
      close(OUTFILE) unless ($Config{'output'} eq "stdout"); #fixme should never be true -mgt
   }
}
#############################################################################
#END parselogs
#############################################################################

#############################################################################
#sub output
#
#############################################################################
sub output {
   my ($index, $text, $type) = @_;
   #Types are start stop header line ref

   if ( $type eq "ref_extra" ) {
      $out_reference .= "$text\n";
   }

   if ( $type eq "ref" ) {
      $out_reference .= "   <li><a href=\"#$index\">$reports[$index]</a>\n";
   }

   if ( $type eq "start" ) {
      $reports[$index] = "$text";
   #SERVICE table headers if ( $index eq 'E' ) { #never happens change out_body from hash back to array
      if ( $Config{'format'} eq "html" ) {
         $out_body{$index} .=
         "<div class=service>
         <table border=1 width=100%>
           <tr><th>
           <h2><a name=\"$index\">$reports[$index]</a></h2>
           </tr></th>\n";
      }
   }

   if ( $type eq "stop" ) {
      if ( $Config{'format'} eq "html" ) {
         $out_body{$index} .= "  </table></div>\n";
         $out_body{$index} .= "  <div class=return_link><p><a href=\"#top\">Back to Top</a></p></div>\n";
      }
   }

   if ( $type eq "header" ) {
	   if ( $Config{'format'} eq "text" ) {
	      $out_body{$index} .= "$text \n";
      } elsif ( $Config{'format'} eq "html" ) {
         #Covert spaces
         $text =~ s/  / \&nbsp;/go;
         #Covert tabs 1 to 4 ratio
         $text =~ s/\t/ \&nbsp\;\&nbsp\;\&nbsp\;\&nbsp\;/go;
         #Filters
         $text =~ s/ $//go;
         $text = '&nbsp;' if ( $text eq '' );
         #This will make sure no unbroken string is longer then x characters
         $text =~ s/(\S{$Config{html_wrap}})/$1 /g;
         $out_body{$index} .= "<tr>\n    <th>$text</th>\n   </tr>\n";
      } else { #fixme what is this formatted?
         $out_body{$index} .=
         sprintf( substr( $text, 0, $format[0] ) . ' ' x( $format[0] - length($text) ) . " \n" );
      }
   }

   if ( $type eq "line" ) {
	   if ( $Config{'format'} eq "text" ) {
         $out_body{$index} .= "$text ";
      } elsif ( $Config{'format'} eq "html" ) {
         #Covert spaces
         $text =~ s/  / \&nbsp;/go;
         #Covert tabs 1 to 4 ratio
         $text =~ s/\t/ \&nbsp\;\&nbsp\;\&nbsp\;\&nbsp\;/go;
         #Filters
         $text =~ s/ $//go;
         $text =~ s/</\&lt\;/go;
         $text =~ s/>/\&gt\;/go;
         #This will make sure no unbroken string is longer then x characters
         $text =~ s/(\S{$Config{html_wrap}})/$1 /g;
         #Grey background for spaced output
         if ( $text =~ m/^ / ) {
            $out_body{$index} .= "  <tr>\n    <td bgcolor=#dddddd>$text</td>\n  </tr>\n";
         } else {
            $out_body{$index} .= "  <tr>\n    <th align=left>$text</th>\n  </tr>\n";
         }
      } else { #fixme formatted?
	      if ( length($text) > $format[0] ) {
	         $out_body{$index} .=
		      sprintf( $text . "\n" . ' ' x $format[0] . ' ' );
	      } else {
	         $out_body{$index} .=
		      sprintf( $text . ' ' x ( $format[0] - length($text) ) . ' ' );
	      }
      }
   }
}
###########################################################################
#END sub output
###########################################################################
# vi: shiftwidth=3 tabstop=3 et
# Local Variables:
# mode: perl
# perl-indent-level: 3
# indent-tabs-mode: nil
# End:
