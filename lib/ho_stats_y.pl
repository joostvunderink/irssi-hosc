use strict;
use warnings;
use vars qw(%IRSSI);

use Irssi;
use Irssi::Irc;
use Irssi::HOSC::again;
use Irssi::HOSC::again 'Irssi::HOSC::Base';
use Irssi::HOSC::again 'Irssi::HOSC::Tools';

# ---------------------------------------------------------------------

%IRSSI = Irssi::HOSC::Base::ho_get_IRSSI(
    authors     => 'JamesOff',
    contact     => 'james@jamesoff.net',
    name        => 'stats_y',
    description => 'Reformats stats y',
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


