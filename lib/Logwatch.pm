#!/usr/bin/perl
#
# $Id: Logwatch.pm,v 1.18 2007/02/05 02:31:56 bjorn Exp $

package Logwatch;

use strict;
use Exporter;
use POSIX qw(strftime);

=pod

=head1 NAME

Logwatch -- Utility functions for Logwatch Perl modules.

=head1 SYNOPSIS

 use Logwatch ':sort';

 ##
 ## Show CountOrder()
 ##

 # Sample Data
 my %UnknownUsers = (jb1o => 4, eo00 => 1, ma3d => 4, dr4b => 1);
 my $sortClosure = CountOrder(%UnknownUsers);
 foreach my $user (sort $sortClosure keys %UnknownUsers) {
     my $plural = ($UnknownUsers{$user} > 1) ? "s" : "";
     printf "  %-8s : %2d time%s\n", $user, $UnknownUsers{$user}, $plural;
 }

 ##
 ## Show TotalCountOrder()
 ##

 # Sample Data
 my %RelayDenied = ( some.server  => {you@some.where => 2, foo@bar.com => 4},
                     other.server => { foo@bar.com => 14 }
                   );

 my $sub = TotalCountOrder(%RelayDenied);
 foreach my $relay (sort $sub keys %RelayDenied) {
     print "    $relay:\n";
     my $countOrder = CountOrder(%{$RelayDenied{$relay}});
     foreach my $dest (sort $countOrder keys %{$RelayDenied{$relay}}) {
         my $plural = ($RelayDenied{$relay}{$dest} > 1) ? "s" : "";
         printf "        %-36s: %3d Time%s\n", $dest,
             $RelayDenied{$relay}{$dest}, $plural;
     }
 }

 use Logwatch ':ip';

 ##
 ## Show SortIP()
 ##

 # Sample Data
 @ReverseFailures = qw{10.1.1.1 172.16.1.1 10.2.2.2 192.168.1.1 };
 @ReverseFailures = sort SortIP @ReverseFailures;
 { local $" = "\n  "; print "Reverse DNS Failures:\n  @ReverseFailures\n" }

        -or-

 ##
 ## Show LookupIP()
 ##
 foreach my $ip (sort SortIP @ReverseFailures) {
     printf "%15s : %s\n", $ip, LookupIP($ip);
 }

=head1 DESCRIPTION

This module provides utility functions intended for authors of Logwatch
scripts. The purpose is to abstract commonly performed actions into a
set of generally available subroutines. The subroutines can optionally
be imported into the local namespace.

=over 4

=cut

our @ISA = qw{Exporter};
our @EXPORT;
our @EXPORT_OK;
our %EXPORT_TAGS = (sort => [qw(CountOrder TotalCountOrder SortIP)],
                    ip   => [qw(LookupIP SortIP)],
                    dates   => [qw(RangeHelpDM GetPeriod TimeBuild TimeFilter)],
                    );

Exporter::export_ok_tags(qw{sort ip dates});

$EXPORT_TAGS{all} = [@EXPORT, @EXPORT_OK];

=pod

=item I<CountOrder(%hash [, $coderef ])>

This function returns a closure suitable to be passed to Perl's C<sort>
builtin. When two values are passed to the closure, it compares the
numeric values of those keys in C<%hash>, and if they're equal, the
lexically order of the keys. Thus:

  my $sortClosure = CountOrder(%UnknownUsers);
  foreach my $user (sort $sortClosure keys %UnknownUsers) {
      my $plural = ($UnknownUsers{$user} > 1) ? "s" : "";
      printf "  %-8s : %2d time%s\n", $user, $UnknownUsers{$user}, $plural;
  }

Will print the keys and values of C<%UnknownUsers> in frequency order,
with keys of equal values sorted lexically.

The optional second argument is a coderef to be used to sort the keys in
an order other than lexically. (a reference to C<SortIP>, for example.)

=cut

# Use a closure to abstract the sort algorithm
sub CountOrder(\%;&) {
    my $href = shift;
    my $coderef = shift;
    return sub {
        # $a & $b are in the caller's namespace, moving this inside
        # guarantees that the namespace of the sort is used, in case
        # it's different (admittedly, that's highly unlikely), at a
        # miniscule performance cost.
        my $package = (caller)[0];
        no strict 'refs'; # Back off, man. I'm a scientist.
        my $A = $ {"${package}::a"};
        my $B = $ {"${package}::b"};
        use strict 'refs'; # We are a hedge. Please move along.
        # Reverse the count, but not the compare
        my $count = $href->{$B} <=> $href->{$A};
        return $count if $count;
        if (ref $coderef) {
            $a = $A;
            $b = $B;
            &$coderef();
        } else {
            ($A cmp $B);
        }
    }
}

=pod

=item I<TotalCountOrder(%hash [, $coderef ])>

This function returns a closure similar to that returned by
C<CountOrder()>, except that it assumes a hash of hashes, and totals the
keys of each sub hash. Thus:

 my $sub = TotalCountOrder(%RelayDenied);
 foreach my $relay (sort $sub keys %RelayDenied) {
     print "    $relay:\n";
     my $countOrder = CountOrder(%{$RelayDenied{$relay}});
     foreach my $dest (sort $countOrder keys %{$RelayDenied{$relay}}) {
         my $plural = ($RelayDenied{$relay}{$dest} > 1) ? "s" : "";
         printf "        %-36s: %3d Time%s\n", $dest,
             $RelayDenied{$relay}{$dest}, $plural;
     }
 }

Will print the relays in the order of their total denied destinations
(equal keys sort lexically), with each sub hash printed in frequency
order (equal keys sorted lexically)

The optional second argument is a coderef to be used to sort the keys in
an order other than lexically. (a reference to C<SortIP>, for example.)

=cut

sub TotalCountOrder(\%;&) {
    my $href = shift;
    my $coderef = shift;
    my $cache = {};
    return sub {
        # $a & $b are in the caller's namespace, moving this inside
        # guarantees that the namespace of the sort is used, in case
        # it's different (admittedly, that's highly unlikely), at a
        # miniscule performance cost.
        my $package = (caller)[0];
        no strict 'refs'; # Back off, man. I'm a scientist.
        my $A = $ {"${package}::a"};
        my $B = $ {"${package}::b"};
        use strict 'refs'; # We are a hedge. Please move along.
        my ($AA, $BB);

        foreach my $tuple ( [\$A, \$AA], [\$B, \$BB] ) {
            my $keyRef = $tuple->[0];
            my $totalRef = $tuple->[1];

            if (exists($cache->{$$keyRef})) {
                $$totalRef = $cache->{$$keyRef};
            } else {
                grep {$$totalRef += $href->{$$keyRef}->{$_}}
                    keys %{$href->{$$keyRef}};
                $cache->{$$keyRef} = $$totalRef;
            }
        }
        my $count = $BB <=> $AA;

        return $count if $count;
        if (ref $coderef) {
            $a = $A;
            $b = $B;
            &$coderef();
        } else {
            ($A cmp $B);
        }
    }
}

=pod

=item I<SortIP>

This function is meant to be passed to the perl C<sort> builtin. It
sorts a list of "dotted quad" IP addresses by the values of the
individual octets.

=cut

sub canonical_ipv6_address {
    my @a = split /:/, shift;
    my @b = qw(0 0 0 0 0 0 0 0);
    my $i = 0;
    # comparison is numeric, so we use hex function
    while (defined $a[0] and $a[0] ne '') {$b[$i++] = hex(shift @a);}
    @a = reverse @a;
    $i = 7;
    while (defined $a[0] and $a[0] ne '') {$b[$i--] = hex(shift @a);}
    @b;
}

sub SortIP {
    # $a & $b are in the caller's namespace.
    my $package = (caller)[0];
    no strict 'refs'; # Back off, man. I'm a scientist.
    my $A = $ {"${package}::a"};
    my $B = $ {"${package}::b"};
    $A =~ s/^::(ffff:)?(\d+\.\d+\.\d+\.\d+)$/$2/;
    $B =~ s/^::(ffff:)?(\d+\.\d+\.\d+\.\d+)$/$2/;
    use strict 'refs'; # We are a hedge. Please move along.
    if ($A =~ /:/ and $B =~ /:/) {
        my @a = canonical_ipv6_address($A);
        my @b = canonical_ipv6_address($B);
        while ($a[1] and $a[0] == $b[0]) {shift @a; shift @b;}
        $a[0] <=> $b[0];
    } elsif ($A =~ /:/) {
        -1;
    } elsif ($B =~ /:/) {
        1;
    } else {
        my ($a1, $a2, $a3, $a4) = split /\./, $A;
        my ($b1, $b2, $b3, $b4) = split /\./, $B;
        $a1 <=> $b1 || $a2 <=> $b2 || $a3 <=> $b3 || $a4 <=> $b4;
    }
}

=pod

=item I<LookupIP($dottedQuadIPaddress)>

This function performs a hostname lookup on a passed in IP address. It
returns the hostname (with the IP in parentheses) on success and the IP
address on failure. Results are cached, so that many calls with the same
argument don't tax the resolver resources.

For (new) backward compatibility, this function now uses the $DoLookup
variable in the caller's namespace to determine if lookups will be made.

=cut

# Might as well cache it for the duration of the run
my %LookupCache = ();

sub LookupIP {
   my $Addr = $_[0];

   # OOPS! The 4.3.2 scripts have a $DoLookup variable. Time for some
   # backwards compatible hand-waving.

   # for 99% of the uses of this function, assuming package 'main' would
   # be sufficient, but a good perl hacker designs so that the other 1%
   # isn't in for a nasty suprise.
   my $pkg = (caller)[0];

   if ($ENV{'LOGWATCH_NUMERIC'} == 1 )
      { return $Addr; }

   # Default to true
   my $DoLookup = 1;
   {
       # An eval() here would be shorter (and probably clearer to more
       # people), but QUITE a bit slower. This function should be
       # designed to be called a lot, so efficiency is important.
       local *symTable = $main::{"$pkg\::"};

       # here comes the "black magic," (this "no" is bound to the
       # enclosing block)
       no strict 'vars';
       if (exists $symTable{'DoLookup'} && defined $symTable{'DoLookup'}) {
           *symTable = $symTable{'DoLookup'};
           $DoLookup = $symTable;
       }
   }

   # "Socket" is used solely to get the AF_INET() and AF_INET6()
   # constants, usually 2 and 10, respectively.  Using Socket is
   # preferred because of portability, and should be in the standard
   # Perl distribution.
   eval "use Socket"; my $hasSocket = $@? 0 : 1;
   return $Addr unless($DoLookup && $hasSocket);

   return $LookupCache{$Addr} if exists ($LookupCache{$Addr});

   $Addr =~ s/^::ffff://;
   my $PackedAddr;
   my $name = "";

   # there are other module functions that do this more gracefully
   # (such as inet_pton), but we can't guarantee that they are available
   # in every system, so we use the built-in gethostbyaddr.
   if ($Addr =~ /^[\d\.]*$/) {
      $PackedAddr = pack('C4', split /\./,$Addr);
      $name = gethostbyaddr($PackedAddr,AF_INET());
   } elsif ($Addr =~ /^[0-9a-zA-Z:]*/) {
      $PackedAddr = pack('n8', canonical_ipv6_address($Addr));
      $name = gethostbyaddr($PackedAddr, AF_INET6());
   }
   if ($name) {
       my $val = "$Addr ($name)";
       $LookupCache{$Addr} = $val;
       return $val;
   } else {
       $LookupCache{$Addr} = $Addr;
       return ($Addr);
   }
}

=pod

=item I<RangeHelpDM()>

This function merely prints out some information about --range to STDERR.

=cut

sub RangeHelpDM {
   eval "use Date::Manip"; my $hasDM = $@ ? 0 : 1;

   if ($hasDM) {
       print STDERR "\nThis system has the Date::Manip module loaded, and therefore you may use all\n";
       print STDERR "of the valid --range parameters.\n";
   } else {
       print STDERR "\nThis system does not have Date::Manip module loaded, and therefore\n";
       print STDERR "the only valid --range parameters are 'yesterday', 'today', or 'all'.\n";
       print STDERR "The Date::Manip module can be installed by using either of:\n";
       print STDERR "   apt-get install libdate-manip-perl (recommended on Debian)'\n";
       print STDERR "   cpan -i 'Date::Manip'\n";
       print STDERR "   perl -MCPAN -e 'install Date::Manip'\n";
       print STDERR "\nFollowing is a description of the full capabilities available if\n";
       print STDERR "Date::Manip is available.\n";
   }

   print STDERR <<"EOT";

The format of the range option is:
    --range \"date_range [period]\"

Parameter date_range (and optional period) must be enclosed in quotes if it is
more than one word.  The default for date_range is \"yesterday\". Valid
instances of date_range have one of the following formats:

   yesterday
   today
   all
   date1
   between date1 and date2
   since date1

For the above, date1 and date2 have values that can be parsed with the
Date::Manip perl module.

Valid instances of the optional parameter period have one of the following
formats:
   for (that|this) (year|month|day|hour|minute|second)
   for those (years|months|days|hours|minutes|seconds)

The period defines the resolution of the date match.  The default is
\"for that day\".

Examples:


   --range today
   --range yesterday
   --range '4 hours ago for that hour'
   --range '-3 days'
   --range 'since 2 hours ago for those hours'
   --range 'between -10 days and -2 days'
   --range 'Apr 15, 2005'
   --range 'first Monday in May'
   --range 'between 4/23/2005 and 4/30/2005'
   --range '2005/05/03 10:24:17 for that second'

(The last entry might be used by someone debugging a log or filter.)

A caution about efficiency: a range of \"yesterday for those hours\"
will search for log entries for the last 24 hours, and is innefficient
because it searches for individual matches for each hour.  A range of
\"yesterday\" will search for log entries for the previous day, and
it searches for a single date match.
EOT
;

}


=pod

=item I<GetPeriod()>

This function returns the period, which is the part after the "for (those|that|this) "
in a range

=cut

sub GetPeriod {

   my $range = lc $ENV{"LOGWATCH_DATE_RANGE"} || "yesterday";
   my ($period) =
      ($range =~ /for\s+(?:those|that|this)\s+(year|month|day|hour|minute|second)s?\s*$/);
   if ($range eq 'all') {
        $period = 'all';
   }
   unless ($period) { $period = "day"; }
   return($period);
}

=pod

=item I<TimeBuild()>

This function returns an array of integers denoting time since the epoch
(Jan. 1, 1970).  Each entry represents a timestamp for the period that will
that will need to be looked up to create the filter.

=cut

sub TimeBuild {
   my @time_t;
   my $time = time;
   eval "use Date::Manip"; my $hasDM = $@ ? 0 : 1;

   if ($hasDM) {
      eval 'Date_TimeZone();';
      if ($@) {
         die "ERROR: Date::Manip unable to determine TimeZone.\n\nExecute the following command in a shell prompt:\n\tperldoc Date::Manip\nThe section titled TIMEZONES describes valid TimeZones\nand where they can be defined.\n";
      }
   }

   my $range = lc $ENV{"LOGWATCH_DATE_RANGE"} || "yesterday";
   my $period = GetPeriod;
   $range =~ s/for\s+(?:those|that|this)\s+((year|month|day|hour|minute|second)s?)\s*$//;
   my ($range1, $range2) = ($range =~ /^between\s+(.*)\s+and\s+(.*)\s*$/);
   if ($range =~ /^\s*since\s+/) {
       ($range1) = ($range =~ /\s*since\s+(.*)/);
       $range2 = "now";
   }

   if ($range1 && $range2 && $hasDM) {
        # range between two dates specified
        my $date1 = ParseDate($range1);
        my $date2 = ParseDate($range2);
        if ($date1 && $date2) {
           if (Date_Cmp($date1, $date2) > 0) {
                   # make sure date1 is earlier
                my $switch_date = $date1;
                   $date1 = $date2;
                   $date2 = $switch_date;
            }
            while (Date_Cmp($date1, $date2) < 0) {
                $time_t[++$#time_t] = UnixDate($date1, "%s");
                $date1 = DateCalc($date1, "+1 $period");
            }
            $time_t[++$#time_t] = UnixDate($date2, "%s");
        } else { # $date1 or $date2 not valid
            # set to zero, which indicates it is not parsed
            $time_t[0] = 0;
        }
    } else {
        # either a single date or we don't have Date::Manip
        if ($range eq 'yesterday') {
           $time_t[0] = $time-86400;
        } elsif ($range eq 'today') {
           $time_t[0] = $time;
        } elsif ($range eq 'all') {
           # set arbitrarily to 1
           $time_t[0] = 1;
        } elsif ($hasDM) {
           $time_t[0] = UnixDate($range, "%s") || 0;
        } else {
           $time_t[0] = 0;
        }
    }

   # this is an optimization when we use Date::Manip, and
   # the period is either 'month' or 'year'.  It is intended
   # to reduce the number of archived logs searched.
   # We use the second day of month or year to account for
   # different timezones.
   if ($time_t[0] && $hasDM) {
      my $mod_date = ParseDateString("epoch $time_t[0]");
      if ($period =~ /^month|year$/) {
	  # set to beginning of month
	  $mod_date =~ s/\d\d\d\d:\d\d:\d\d$/0200:00:00/;
	  if ($period =~ /^year$/) {
	      # set to beginning of year
	      $mod_date =~ s/\d\d0100:00:00/010200:00:00/;
	  }
      }
      $time_t[0] = UnixDate($mod_date, "%s");
   }
   return(@time_t);
}

=pod

=item I<TimeFilter($date_format)>

This function returns a regexp to filter by date/time

=cut


sub TimeFilter {
   my ($format) = $_[0];

   my $SearchDate;

   my $range = lc $ENV{"LOGWATCH_DATE_RANGE"} || "yesterday";
   my $debug = $ENV{"LOGWATCH_DEBUG"} || 0;

   my @time_t = TimeBuild();

   # get period
   my $period = GetPeriod;
   if ($debug > 5) {
       print STDERR "\nTimeFilter: Period is $period\n";
   }
   # we need the following bracketed section because of 'last'
   {
           if ($period eq 'second') {last;}
           $format =~ s/%S/../;
           if ($period eq 'minute') {last;}
           $format =~ s/%M/../;
           if ($period eq 'hour') {last;}
           $format =~ s/%H/../;
           if ($period eq 'day') {last;}
           $format =~ s/%a/.../;
           $format =~ s/%d/../;
           $format =~ s/%e/../;
           if ($period eq 'month') {last;}
           $format =~ s/%b/.../;
           $format =~ s/%m/../;
           if ($period eq 'year') {last;}
           $format =~ s/%y/../;
           $format =~ s/%Y/..../;
   }

   $SearchDate .= "(";

   for my $time (@time_t) {
        if ($time) {
           $SearchDate .= strftime($format, localtime($time)) . "|";
        }
        else {
           # the following is a string guaranteed to not match
           $SearchDate .= "Range \"$range\" not understood. ";
           print STDERR "ERROR: Range \"$range\" not understood\n";
           RangeHelpDM;
           }
   }
   # get rid of last character (usually the extra "|")
   if (length($SearchDate) > 1) {
      chop($SearchDate);
   }
   $SearchDate .= ")";
   if ($debug> 5) {
       # DebugSearchDate sometimes makes it more readable - not used
       #   functionally
       my $DebugSearchDate = $SearchDate;
       $DebugSearchDate =~ tr/:/ /;
       $DebugSearchDate =~ tr/\./ /;
       $DebugSearchDate =~ tr/ //s;
       print STDERR "\nTimeFilter: SearchDate is $SearchDate\n";
       print STDERR "\nTimeFilter: Debug SearchDate is $DebugSearchDate\n";
   }
   return ($SearchDate);
}


=back

=head1 TAGS

In addition to importing each function name explicitly, the following
tags can be used.

=over 4

=item I<:sort>

Imports C<CountOrder>, C<TotalCountOrder and C<SortIP>

=item I<:ip>

Imports C<SortIP> and C<LookupIP>

=item I<:dates>

Imports C<RangeHelpDM GetPeriod TimeBuild TimeFilter>

=item I<:all>

Imports all importable symbols.

=cut

1;

# vi: shiftwidth=3 tabstop=3 et

