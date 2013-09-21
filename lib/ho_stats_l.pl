# ho_stats_y.pl
#
# $Id: ho_stats_l.pl,v 1.3 2004/08/26 16:57:46 jvunder REL_0_1 $
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

$SCRIPT_NAME = 'Stats L reformatting';
($VERSION) = '$Revision: 1.3 $' =~ / (\d+\.\d+) /;
%IRSSI = (
    authors     => 'JamesOff',
    contact     => 'james@jamesoff.net',
    name        => 'stats l',
    description => 'Reformats stats l and stats ?',
    license     => 'GPL v2',
    url         => 'http://www.jamesoff.net',
);

# Temporary variables to be able to print the output of two lines in a
# single line. A rather ugly hack, but, shrug.
# Sent total :   11.72 Megabytes
# Recv total :   13.37 Megabytes
# $sent_server is used to store "11.72 Megabytes" which is used when the
# Recv total line is processed.
my ($sent_server, $sent_total, $sent_total_speed);

# ---------------------------------------------------------------------

sub event_stats_l_line {
    my ($server, $data, $nick, $address) = @_;

    my ($user, $sendq, $sentMsgs, $sentK, $recvMsgs, $recvK, $time_on, $time_idle, $features) =
        $data =~ /\w+ (\S+) (\d+) (\d+) (\d+) (\d+) (\d+) :(\d+) (\d+)( .+)?/;

    my ($username, $hostname) = ('unknown', 'unknown');
    if ($user =~ /^([^[]+)\[(.+)@(.+)\]$/) {
        ($user, $username, $hostname) = ($1, $2, $3);
    }
    Irssi::printformat(MSGLEVEL_CRAP, 'ho_stats_l_header',
        $user, $username, $hostname);

    my $sendq_format = 'ho_stats_l_sendq_zero';
    my $tick_size = Irssi::settings_get_int('ho_stats_l_sendq_tick');
    $sendq_format = 'ho_stats_l_sendq_low'    if $sendq > 4 * $tick_size;
    $sendq_format = 'ho_stats_l_sendq_medium' if $sendq > 8 * $tick_size;
    $sendq_format = 'ho_stats_l_sendq_high'   if $sendq > 16 * $tick_size;

    my $ticks  = '*' x ($sendq / $tick_size);
    my $spaces = '.' x
        (Irssi::settings_get_int('ho_stats_l_sendq_width') - (length $ticks));

    Irssi::printformat(MSGLEVEL_CRAP, $sendq_format, $sendq,
        $ticks, $spaces, ' ' x (8 - (length $sendq)));

    Irssi::printformat(MSGLEVEL_CRAP, 'ho_stats_l_sent', $sentMsgs, $sentK)
        unless Irssi::settings_get_bool('ho_stats_l_print_sendq_only');
    Irssi::printformat(MSGLEVEL_CRAP, 'ho_stats_l_recv', $recvMsgs, $recvK)
        unless Irssi::settings_get_bool('ho_stats_l_print_sendq_only');

    my $days = int($time_on / 86400);
    my $hours = int(($time_on - $days * 86400) / 3600);
    $time_on -= ($days * 86400);
    my $mins = int(($time_on - $hours * 3600) / 60);
    my $secs = $time_on - $hours * 3600 - $mins * 60;

    $time_on = sprintf("%03d+%02d:%02d:%02d", $days, $hours, $mins, $secs);

    $days = int($time_idle / 86400);
    $hours = int(($time_idle - $days * 86400) / 3600 );
    $time_idle -= ($days * 86400);
    $mins = int(($time_idle - $hours * 3600) / 60);
    $secs = $time_idle - $hours * 3600 - $mins * 60;

    $time_idle = sprintf("%03d+%02d:%02d:%02d", $days, $hours, $mins, $secs);

    Irssi::printformat(MSGLEVEL_CRAP, 'ho_stats_l_connidle',
        $time_on, $time_idle)
        unless Irssi::settings_get_bool('ho_stats_l_print_sendq_only');

    if ($features ne " -") {
        Irssi::printformat(MSGLEVEL_CRAP, 'ho_stats_l_supports', $features)
            unless Irssi::settings_get_bool('ho_stats_l_print_sendq_only');
    }
}

# ---------------------------------------------------------------------

sub event_stats_l_line_traffic {
    my ($server, $data, $nick, $address) = @_;

    if ($data =~ /:(\d) total server/) {
        Irssi::printformat(MSGLEVEL_CRAP, 'ho_stats_l_total_servers', $1)
            unless Irssi::settings_get_bool('ho_stats_l_print_sendq_only');
    } elsif ($data =~ /:Sent total\s*:\s*(\d+\.\d+\s+\w+)\s*$/) {
        $sent_server = $1;
    } elsif ($data =~ /:Recv total\s*:\s*(\d+\.\d+\s+\w+)\s*$/) {
        Irssi::printformat(MSGLEVEL_CRAP, 'ho_stats_l_traffic_servers',
                $sent_server, $1)
            unless Irssi::settings_get_bool('ho_stats_l_print_sendq_only');
    } elsif ($data =~ /:Server send:\s*(\d+\.\d+\s+\w+)\s+\(\s*([^)]+)\)/) {
        ($sent_total, $sent_total_speed) = ($1, $2);
    } elsif ($data =~ /:Server recv:\s*(\d+\.\d+\s+\w+)\s+\(\s*([^)]+)\)/) {
        Irssi::printformat(MSGLEVEL_CRAP, 'ho_stats_l_traffic_total',
                $sent_total, $sent_total_speed, $1, $2)
            unless Irssi::settings_get_bool('ho_stats_l_print_sendq_only');
    } else {
        # Let the signal continue, it's not for us.
        return;
    }

    Irssi::signal_stop();
}

# ---------------------------------------------------------------------

sub reemit_stats_l_line {
    my ($server, $data, $servername) = @_;

    # We need to re-emit this 249 numeric in case it contains data which
    # has nothing to do with stats l or ?. Unfortunately, STATS p
    # also uses numeric 249, and we don't want to lose this data.

    # For some reason I do not comprehend, Irssi does not display
    # the first word of $args when re-emitting this signal. Hence
    # the 'dummy_data' addition.
    # Perhaps the number of the numeric should be here.
    # Perhaps there is a rational explanation.
    # I do not know, but this seems to work properly.
    Irssi::signal_emit("default event numeric",
        $server, "dummy_data " . $data, $servername);
    Irssi::signal_stop();
}

# ---------------------------------------------------------------------

sub event_stats_end {
    my ($server, $data, $servername) = @_;

    return unless $data =~ /[lL?] :End of \/STATS report/;

    Irssi::signal_stop();
}

# ---------------------------------------------------------------------

ho_print_init_begin();

Irssi::theme_register([
    'ho_stats_l_header',
    '%_$0%_ ($1@$2)',

    'ho_stats_l_sendq_zero',
    '  SendQ %G$0%n bytes $3[%G$1%n$2]',

    'ho_stats_l_sendq_low',
    '  SendQ %Y$0%n bytes $3[%Y$1%n$2]',

    'ho_stats_l_sendq_medium',
    '  SendQ %r$0%n bytes $3[%r$1%n$2]',

    'ho_stats_l_sendq_high',
    '  SendQ %R$0%n bytes $3[%R$1%n$2]',

    'ho_stats_l_sent',
    '  Sent %_$[-10]0%_ msgs in %_$[-10]1%_kB',

    'ho_stats_l_recv',
    '  Recv %_$[-10]0%_ msgs in %_$[-10]1%_kB',

    'ho_stats_l_connidle',
    '  Conn %_$0%_  Idle %_$1%_',

    'ho_stats_l_supports',
    '  Supports %_$0%_',

    'ho_stats_l_total_servers',
    'Linked servers: %G$0%n',

    'ho_stats_l_traffic_servers',
    'Sent %Y$0%n  Recv %G$1%n  [to/from other servers]',

    'ho_stats_l_traffic_total',
    'Sent %Y$0%n ($1) Recv %G$2%n ($3) [total]',

]);

Irssi::settings_add_bool('ho', 'ho_stats_l_print_sendq_only', 0);
Irssi::settings_add_int('ho', 'ho_stats_l_sendq_tick', 262144);
Irssi::settings_add_int('ho', 'ho_stats_l_sendq_width', 40);

Irssi::signal_add_first("event 211", "event_stats_l_line");
Irssi::signal_add_first("event 249", "event_stats_l_line_traffic");
Irssi::signal_add_last ("event 249", "reemit_stats_l_line");
Irssi::signal_add_first("event 219", "event_stats_end");

ho_print("STATS L and STATS ? output is now being reformatted.");
ho_print("Enable the 'ho_stats_l_print_sendq_only' setting if you ".
    "only want to see the sendqs if you use STATS ?.");

ho_print_init_end();

# ---------------------------------------------------------------------


