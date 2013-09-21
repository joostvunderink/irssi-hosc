# ho_stats_y.pl
#
# $Id: ho_stats_y.pl,v 1.6 2004/08/21 09:25:58 jvunder REL_0_1 $
#
# Part of the Hybrid Oper Script Collection
#
# Reformats /stats y output.
#

use strict;
use vars qw($VERSION %IRSSI $SCRIPT_NAME);

use Irssi;
use Irssi::Irc;
use HOSC::again;
use HOSC::again 'HOSC::Base';
use HOSC::again 'HOSC::Tools';

# ---------------------------------------------------------------------

$SCRIPT_NAME = "Stats Y reformatting";
($VERSION) = '$Revision: 1.6 $' =~ / (\d+\.\d+) /;
%IRSSI = (
    authors     => 'JamesOff',
    contact     => 'james@jamesoff.net',
    name        => 'stats_y',
    description => 'Reformats stats y',
    license     => 'GPL v2',
    url         => 'http://www.jamesoff.net',
);

# Script rewritten using formats by Garion.

# 1218.34 Y opers 90 0 100 10485760 100.0 1000.0
# 1228.37 [@    Manic] Y:name:ping:max conns:total for class:sendq:max local: max global

sub format_y_stats {
    my ($server, $data, $nick, $address) = @_;

    my ($name, $ping, $max_conns, $total, $sendq, $local, $global, $cur) =
        $data =~ /\w+ Y ([\w-]+) (\d+) (\d+) (\d+) :?(\d+)\/?\d* ?(\S+)? ?(\S+)? ?(\d+)?/;
    $sendq = int($sendq);

    if (defined $cur) {
        Irssi::printformat(MSGLEVEL_CRAP, 'ho_stats_y_header_plus',
            $name, $cur);
    } else {
        Irssi::printformat(MSGLEVEL_CRAP, 'ho_stats_y_header', $name);
    }
    Irssi::printformat(MSGLEVEL_CRAP, 'ho_stats_y_pingconn',
        $ping, $max_conns);
    Irssi::printformat(MSGLEVEL_CRAP, 'ho_stats_y_totalsendq',
        $total, $sendq);
    if ($local) {
        Irssi::printformat(MSGLEVEL_CRAP, 'ho_stats_y_localglobal',
            $local, $global);
    }
}

Irssi::theme_register([
    'ho_stats_y_header',
    'Class %Y$0%n',

    'ho_stats_y_header_plus',
    'Class %Y$0%n (%G$1%n)',

    'ho_stats_y_pingconn',
    '  Ping:      %_$[-6]0%_   Max conns: %_$[-6]1%_',

    'ho_stats_y_totalsendq',
    '  Total:     %_$[-6]0%_   SendQ:  %_$[-9]1%_',

    'ho_stats_y_localglobal',
    '  Max local: %_$[-6]0%_   global:    %_$[-6]1%_',
]);


Irssi::signal_add("event 218", "format_y_stats");


