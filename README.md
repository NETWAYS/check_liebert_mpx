check_liebert_mpx
=================

This plugin monitors Liebert MPX Rack PDUs.

MIB file is not required, OIDs are hardcoded. If you nonetheless want to
download them, they should be available here:

  http://www.liebert.com/downloads

Current Liebert MPX manual is to be found here:

  http://www.emersonnetworkpower.com/en-US/Products/ACPower/RackPDU/Documents/SL-20820_REV02_11-09.pdf

Plugin requires no special configuration, multiple PDUs, RBs and RCPs
are discovered automagically.


### Requirements

* Perl libraries: `Net::SNMP`


### Usage

    check_liebert_mpx -h

    check_liebert_mpx --man

    check_liebert_mpx -H <hostname> [<SNMP community>]

Options:

    -H  Hostname
    -C  Community string (default is "public")
    -h|--help
        Show help page
    --man
        Show manual
    -v--|verbose
        Be verbose
    -V  Show plugin name and version

