#!/usr/bin/perl -w
# $Id$

=pod

=head1 COPYRIGHT

This software is Copyright (c) 2010 NETWAYS GmbH, Thomas Gelf
                               <support@netways.de>

(Except where explicitly superseded by other copyright notices)

=head1 LICENSE

This work is made available to you under the terms of Version 2 of
the GNU General Public License. A copy of that license should have
been provided with this software, but in any event can be snarfed
from http://www.fsf.org.

This work is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
02110-1301 or visit their web page on the internet at
http://www.fsf.org.


CONTRIBUTION SUBMISSION POLICY:

(The following paragraph is not intended to limit the rights granted
to you to modify and distribute this software under the terms of
the GNU General Public License and is only of importance to you if
you choose to contribute your changes and enhancements to the
community by submitting them to NETWAYS GmbH.)

By intentionally submitting any modifications, corrections or
derivatives to this work, or any other work intended for use with
this Software, to NETWAYS GmbH, you confirm that
you are the copyright holder for those contributions and you grant
NETWAYS GmbH a nonexclusive, worldwide, irrevocable,
royalty-free, perpetual, license to use, copy, create derivative
works based on those contributions, and sublicense and distribute
those contributions and any derivatives thereof.

Nagios and the Nagios logo are registered trademarks of Ethan Galstad.

=head1 NAME

check_liebert_rackpdu

=head1 SYNOPSIS

check_liebert_mpx -h

check_liebert_mpx --man

check_liebert_mpx -H <hostname> [<SNMP community>]

=head1 DESCRIPTION

This plugin monitors Liebert MPX Rack PDUs

MIB file is not required, OIDs are hardcoded. If you nonetheless want to
download them, they should be available here:

  http://www.liebert.com/downloads

Current Liebert MPX manual is to be found here:

  http://www.emersonnetworkpower.com/en-US/Products/ACPower/RackPDU/Documents/SL-20820_REV02_11-09.pdf

Plugin requires no special configuration, multiple PDUs, RBs and RCPs
are discovered automagically.

=head1 OPTIONS

=over

=item   B<-H>

Hostname

=item   B<-C>

Community string (default is "public")

=item   B<-h|--help>

Show help page

=item   B<--man>

Show manual

=item   B<-v--|verbose>

Be verbose

=item   B<-V>

Show plugin name and version

=cut

use Getopt::Long;
use Pod::Usage;
use File::Basename;
use Net::SNMP;
use Data::Dumper;

# predeclared subs
use subs qw/help fail fetchOids/;

# predeclared vars
use vars qw (
  $PROGNAME
  $VERSION

  %states
  %state_names
  %performance

  @info
  @perflist

  $opt_host
  $opt_help
  $opt_man
  $opt_verbose
  $opt_version
);

# Main values
$PROGNAME = basename($0);
$VERSION  = '1.0';

# Nagios exit states
%states = (
	'OK'       => 0,
	'WARNING'  => 1,
	'CRITICAL' => 2,
	'UNKNOWN'  => 3
);

# Nagios state names
%state_names = (
	0 => 'OK',
	1 => 'WARNING',
	2 => 'CRITICAL',
	3 => 'UNKNOWN'
);

# SNMP
my $opt_community = "public";
my $snmp_version  = "2c";
my $global_state = 'OK';

# Retrieve commandline options
Getopt::Long::Configure('bundling');
GetOptions(
	'h|help'    => \$opt_help,
	'man'       => \$opt_man,
	'H=s'       => \$opt_host,
	'C=s',      => \$opt_community,
	'v|verbose' => \$opt_verbose,
	'V'		    => \$opt_version
) || help( 1, 'Please check your options!' );

# Any help needed?
help( 1) if $opt_help;
help(99) if $opt_man;
help(-1) if $opt_version;
help(1, 'Not enough options specified!') unless ($opt_host);

### OID definitions ###
my $vendor  = '.1.3.6.1.4.1.476';  # Enterprise OID for Emerson Electric
$vendor = $vendor . '.1';          # Liebert Corporation obtains it branch from Emerson Electric
my $baseOid = $vendor . '.42.3.8'; # liebertGlobalProducts(42).lgpFoundations(3).lgpPdu(8)

# Prepare SNMP Session
($session, $error) = Net::SNMP->session(
	-hostname  => $opt_host,
	-community => $opt_community,
	-port      => 161,
	-version   => $snmp_version,
);
fail('UNKNOWN', $error) unless defined($session);

checkMpx();

foreach (keys %performance) {
	push @perflist, $_ . '=' . $performance{$_};
}
my $info_delim = ', ';
$info_delim = "\n";
printf('%s %s|%s', $global_state, join($info_delim, @info), join(' ', sort @perflist));
exit $states{$global_state};

# Check Liebert MPX
sub checkMpx {
	my $overallStatus  = $baseOid . '.10.5.0';  # .lgpPdu(10).lgpPduCluster(5)
    my $pduCount       = $baseOid . '.19.0';    # .lgPduTableCount(19)
    my $rbCount        = $baseOid . '.40.19.0'; # .lgpPduReceptacleBranch(40).lgPduRbTableCount(19)
    my $rcpCount       = $baseOid . '.50.19.0'; # .lgpPduReceptacle(50).lgPduRcpTableCount(19)
	my @oids = (
		$overallStatus, $pduCount, $rbCount, $rcpCount
	);
    my %result = fetchOids({
        $baseOid . '.10.5.0'  => 'overallStatus',

		# Currently unused:
        $baseOid . '.19.0'    => 'pduCount',
        $baseOid . '.40.19.0' => 'rbCount',
        $baseOid . '.50.19.0' => 'rcpCount',
    });

    my %overallStati = (
        1  => OK,       # normalOperation
        2  => WARNING,  # startUp
        4  => UNKNOWN,  # unknownNoSupport
        8  => WARNING,  # normalWithWarning
        16 => CRITICAL, # normalWithAlarm
        32 => CRITICAL, # abnormalOperation
        64 => CRITICAL  # unknownCommFailure
    );
    my %overallInfo = (
        1  => 'PDU(s) in the cluster are operating normally',
        2  => 'One or more PDUs are in the startup state (initializing)',
        4  => 'The state of one or more PDUs are not known at this time',
        8  => 'One or more PDUs are operating normally with one or more active warnings',
        16 => 'One or more PDUs are operating normally with one or more active alarms',
        32 => 'One ore more PDUs are operating abnormally', # FW Upgrade needed?
        64 => 'Communication failure, hardware problem?',
    );
    raiseGlobalState($overallStati{$result{'overallStatus'}});
    push @info, $overallInfo{$result{'overallStatus'}};

    for ($i = 1; $i <= $result{'pduCount'}; $i++) {
        checkPdu($i);
    }

}

# Fetch information for a given Receptacle
sub checkRcp {
    my $pdu = shift;
    my $rb  = shift;
    my $rcp  = shift;
   # lgpPduRcpEntry
    my $oid = sprintf('%s.50.20.1.%%d.%d.%d.%d', $baseOid, $pdu, $rb, $rcp);

	my %result = fetchOids({
        sprintf($oid, 10) => 'usrLabel',
        sprintf($oid, 50) => 'capabilities',

        # 1:off, 2:on
        sprintf($oid, 95) => 'pwrState',
    });

    if ($result{'capabilities'} > 1) {
        my %perf = fetchOids({
            # Voltage being delivered to the load attached to the receptacle.
            # Alternating Current RMS Electrical Potential measurement.
            sprintf($oid, 56)  => 'epTenths',
            # Current (amperage) being delivered to the load attached to
            # the receptacle. Electrical Current is measured in 
            # Amperes RMS (Root Mean Squared).
            sprintf($oid, 61)  => 'ecHundredths',
            # Warning/Critical Thresholds, percent
            sprintf($oid, 150) => 'ecThreshldUndrAlm',
            sprintf($oid, 151) => 'ecThreshldOvrWarn',
            sprintf($oid, 152) => 'ecThreshldOvrAlm',

            sprintf($oid, 159) => 'ecAvailBeforeAlarmHundredths',
        });
        my $rated = ($perf{'ecAvailBeforeAlarmHundredths'} + $perf{'ecHundredths'}) / $perf{'ecThreshldOvrAlm'} * 100;
        my $amp = $perf{'ecHundredths'} / 100;
        my $clo = $perf{'ecThreshldUndrAlm'} * $rated / 10000;
        my $whi = $perf{'ecThreshldOvrWarn'} * $rated / 10000;
        my $chi = $perf{'ecThreshldOvrAlm'} * $rated / 10000;
        my $state = 'OK';
        $state = 'WARNING' if ($amp > $whi);
        $state = 'CRITICAL' if ($amp < $clo || $amp > $chi);
	    $performance{sprintf('RCP%d.%d.%d-Ampere', $pdu, $rb, $rcp)} = sprintf(
		    "%.2fA;%.1f:%.1f;%.1f:%.1f;%.1f;%.1f",
            $amp, $clo, $whi, $clo, $chi, 0, $rated / 100
	    );
        $state = 'OFF' if ($result{'pwrState'} == 1);
	    push @info, sprintf(
		    '*** %s "%s" [RCP %d.%d.%d] Ampere: %.2f (%.1f:%.1f/%.1f:%.1f)',
            $state, $result{'usrLabel'}, $pdu, $rb, $rcp, $amp, $clo, $whi, $clo, $chi
 	    );
    } else {
        push @info, sprintf(
            '*** OK "%s" [RCP %d.%d.%d]: No measurement capabilities',
            $result{'usrLabel'}, $pdu, $rb, $rcp
        );
    }
}

# Fetch information for a given Receptacle Branch
sub checkRb {
    my $pdu = shift;
    my $rb  = shift;
    # lgpPduRbEntry
    my $oid = sprintf('%s.40.20.1.%%d.%d.%d', $baseOid, $pdu, $rb);
	my %result = fetchOids({
        sprintf($oid, 8)  => 'usrLabel',
        sprintf($oid, 30) => 'serialNum',
        sprintf($oid, 35) => 'model',
        sprintf($oid, 50) => 'capabilities',
        sprintf($oid, 60) => 'rcpCount'
    });

    # Capabilities:
    # not-specified(0)
    # no-optional-capabilities(1)
    # measurement-only(2)
    # measurement-and-control(3)
    if ($result{'capabilities'} > 1) {
        my %perf = fetchOids({
            # Rated Line Voltage for the receptacle branch and its associated
            # receptacles (nominal/available, NOT measured voltage)
            sprintf($oid,  75)  => 'EepRated',

            #  Rated input line current for the module (A) x 10 (200 = 20A)
            # (NOT the measured current)
            sprintf($oid,  75)  => 'ecRated',

            # LNTenths: line-to-neatural measurement of the Electrical
            # Potential measured in Volts RMS (Root Mean Squared)
            # x10: 2272, 2282, 2283
            sprintf($oid, 100)  => 'epLNTenths',

            # The line-to-neutral measurement of the Apparent Power (VA)
            sprintf($oid, 120)  => 'ap', # 0??

            # The line-to-neutral measurement of the Electrical Current
            # measured in Amperes RMS (Root Mean Squared)
            #: (51 [=0.51 Amps])
            sprintf($oid, 130)  => 'ecHundredths',

            # Warning/Critical Thresholds, percent
            sprintf($oid, 135)  => 'ecThreshldUndrAlm',
            sprintf($oid, 140)  => 'ecThreshldOvrWarn',
            sprintf($oid, 145)  => 'ecThreshldOvrAlm',
        });
        my $amp = $perf{'ecHundredths'} / 100;
        my $clo = $perf{'ecThreshldUndrAlm'} * $perf{'ecRated'} / 1000;
        my $whi = $perf{'ecThreshldOvrWarn'} * $perf{'ecRated'} / 1000;
        my $chi = $perf{'ecThreshldOvrAlm'} * $perf{'ecRated'} / 1000;
        my $state = 'OK';
        $state = 'WARNING' if ($amp > $whi);
        $state = 'CRITICAL' if ($amp < $clo || $amp > $chi);
	    $performance{sprintf('RB%d.%d-Ampere', $pdu, $rb)} = sprintf(
		    "%.2fA;%.1f:%.1f;%.1f:%.1f;%.1f;%.1f",
            $amp, $clo, $whi, $clo, $chi, 0, $perf{'ecRated'} / 10
	    );
	    push @info, sprintf(
		    '** %s "%s" [RB %d.%d] Ampere: %.2f (%.1f:%.1f/%.1f:%.1f)',
            $state, $result{'usrLabel'}, $pdu, $rb, $amp, $clo, $whi, $clo, $chi
 	    );
    }

    for (my $i = 1; $i <= $result{'rcpCount'}; $i++) {
        checkRcp($pdu, $rb, $i);
    }
}

# Fetch information for a given PDU
sub checkPdu {
    my $pdu = shift;
    my $oid = sprintf('%s.20.1.%%d.%d', $baseOid, $pdu);

	my %result = fetchOids({
        sprintf($oid, 10)  => 'usrLabel',
        sprintf($oid, 25)  => 'sysStatus',
        sprintf($oid, 45)  => 'serialNumber',
        sprintf($oid, 50)  => 'rbCount',
    });
    push @info, sprintf(
	    '* "%s" [PDU %d]',
        $result{'usrLabel'},
        $pdu
    );
    for (my $i = 1; $i <= $result{'rbCount'}; $i++) {
        checkRb($pdu, $i);
    }
}

# Fetch given OIDs, return a hash
sub fetchOids {
	my %result;
	my %oids = %{$_[0]};
	my $r = $session->get_request(keys %oids);
	if (!defined($r)) {
		fail('CRITICAL', "Failed to query device $opt_host");
	};
    foreach (keys %{$r}) {
       $result{$oids{$_}} = $r->{$_};
    }
	return %result;
}

# Raise global state if given one is higher than the current state
sub raiseGlobalState {
	my @states = @_;
	foreach my $state (@states) {
		# Pay attention: UNKNOWN > CRITICAL
		if ($states{$state} > $states{$global_state}) {
			$global_state = $state;
		}
	}
}

# Print error message and terminate program with given status code
sub fail {
	my ($state, $msg) = @_;
	print $state_names{ $states{$state} } . ": $msg";
	exit $states{$state};
}

# help($level, $msg);
# prints some message and the POD DOC
sub help {
	my ($level, $msg) = @_;
	$level = 0 unless ($level);
	if ($level == -1) {
		print "$PROGNAME - Version: $VERSION\n";
		exit $states{UNKNOWN};
	}
	pod2usage({
		-message => $msg,
		-verbose => $level
	});
	exit $states{'UNKNOWN'};
}

1;
