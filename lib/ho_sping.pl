
# Ping choopa from efnet.nl:
# /quote ping irc.efnet.nl :irc.choopa.net

use strict;
use warnings;
use vars qw(%IRSSI);

use Irssi;
use Irssi::Irc;           # necessary for redirect_register()
use Irssi::HOSC::again;
use Irssi::HOSC::again 'Irssi::HOSC::Base';
use Irssi::HOSC::again 'Irssi::HOSC::Tools';

eval {
    require Time::HiRes;
};
if ($@) {
    Irssi::print("You need Time::HiRes for this script. Please install ".
        "it or upgrade to Perl 5.8.");
    return 0;
}
import Time::HiRes qw(gettimeofday tv_interval);

# Any server replying slower than this is considered to be slow.
my $SLOW_TIME = 2;

# ---------------------------------------------------------------------

%IRSSI = Irssi::HOSC::Base::ho_get_IRSSI(
    name        => 'Server Ping',
    description => 'Checks the latency of all linked servers.',
);

# Hashtable with server latency.
# Key is the server name.
# Value is the ping delay, in seconds.
my %server_pings;

my %data = (
    currently_busy       => 0,
    servers_linked       => 0,
    servers_processed    => 0,
    my_server_tag        => undef,
    timer_gather_id      => undef,
    timer_gather_done_id => undef,
    time_started_tv      => undef,
);

# ---------------------------------------------------------------------

sub cmd_sping {
    my ($data, $server, $item) = @_;
    if ($data =~ m/^[(help)]/i ) {
        Irssi::command_runsub ('sping', $data, $server, $item);
        return;
    }

    if ($data{currently_busy}) {
        ho_print_error("Sorry, already performing a latency check.");
        return;
    }

    ho_print("Checking latency of all linked servers on " .
             $server->{tag} . ".");
    ho_print("Please wait up to " .
        Irssi::settings_get_int('ho_sping_max_time') . " seconds.");
    $server->redirect_event('command cmd_sping', 1, undef, 0, undef,
        {
            'event 364' => 'redir event_links_line',
            'event 365' => 'redir event_links_end',
        }
    );
    delete $server_pings{$_} for keys %server_pings;
    $data{currently_busy}    = 1;
    $data{servers_linked}    = 0;
    $data{servers_processed} = 0;
    $data{my_server_tag}     = $server->{tag};
    $data{time_started_tv}   = [gettimeofday()];

    # Now send LINKS to obtain a list of all linked servers. Then we can
    # send a PING for each server.
     $server->send_raw_now('LINKS');
}

# ---------------------------------------------------------------------

sub cmd_sping_help {
    print_help();
}

# ---------------------------------------------------------------------

sub event_links_line {
    my ($server, $args, $nick, $address) = @_;
    if ($args =~ /^\S+\s+(\S+)\s/) {
        $server_pings{$1} = undef;
    }
    Irssi::signal_stop();
    $data{servers_linked}++;
}

# ---------------------------------------------------------------------

sub event_links_end {
    my ($server, $args, $nick, $address) = @_;

    # We've obtained the complete list of servers. Now go send a PING
    # for each one.
    send_pings($server);
    Irssi::signal_stop();
}

# ---------------------------------------------------------------------

sub send_pings {
    my ($server) = @_;

    # Here we'll send a PING $myserver :$servername for each server.
    # Then we wait until the last pong gets back, or up to
    # sversion_max_time seconds, whichever occurs first. During this
    # time we will steal all PONG replies and signal_stop them.
    my $own_name = $server->{real_address};
    for my $sname (keys %server_pings) {
        $server->command("QUOTE PING $own_name :$sname");
        #print ("QUOTE PING $own_name :$sname");
    }

    # We -must- have a timeout on this latency gathering in case one or
    # more servers fail to reply. The latency gathering is considered to
    # be complete as soon as all pong replies have been received, or
    # this timer is executed, whichever occurs first.
    my $time = Irssi::settings_get_int('ho_sping_max_time');
    $time = 10 if $time < 10;
    $data{timer_gather_id} =
       Irssi::timeout_add($time * 1000, 'gather_completed', undef);
}

# ---------------------------------------------------------------------

sub event_pong {
    my ($server, $args, $nick, $address, $target) = @_;

    return unless $data{currently_busy};

    my ($sname, $me) = $args =~ /^(\S+)\s+(\S+)$/;
    if ($sname) {
        $server_pings{$sname} = [gettimeofday()];
        Irssi::signal_stop();
        $data{servers_processed}++;
        if ($data{servers_linked} == $data{servers_processed}) {
            gather_completed();
        }
    }
}

# ---------------------------------------------------------------------

sub gather_completed {
    if ($data{timer_gather_id}) {
        Irssi::timeout_remove($data{timer_gather_id});
        undef $data{timer_gather_id};
    }
    if ($data{timer_gather_done_id}) {
        Irssi::timeout_remove($data{timer_gather_done_id});
        undef $data{timer_gather_done_id};
    }
    $data{currently_busy} = 0;
    print_pings();
}

# ---------------------------------------------------------------------

sub print_pings {
    my ($server) = @_;

    my @slow_servers      = ();
    my $num_total_servers = scalar keys %server_pings;
    my %time_diffs;
    for my $sname (keys %server_pings) {
        my $timediff =
            tv_interval($data{time_started_tv}, $server_pings{$sname});
        my $timediff_fmt = sprintf "%.2f", $timediff;
            $time_diffs{$sname} = $timediff_fmt;
        if ($timediff > $SLOW_TIME) {
            push @slow_servers, $sname;
        }
    }

    # Print short report.
    if (scalar @slow_servers == 0) {
        ho_print("All $num_total_servers servers replied within ".
            "$SLOW_TIME seconds.");
    } elsif (scalar @slow_servers == 1) {
        ho_print("All $num_total_servers servers except $slow_servers[0] ".
            "replied within $SLOW_TIME seconds.");
    } else {
        ho_print("Out of $num_total_servers servers, the following " .
            (scalar @slow_servers) . " servers ".
            "replied slower than $SLOW_TIME seconds:");
        ho_print(join ' ', @slow_servers);
    }

    # If desired, print full report.
    if (Irssi::settings_get_bool('ho_sping_full_report')) {
        ho_print('Server pings:');
        for my $sname (sort keys %server_pings) {
            Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'ho_sping_line',
                $sname, $time_diffs{$sname});
        }
        ho_print("Total servers linked: $data{servers_linked}.");
    }
}

# ---------------------------------------------------------------------

ho_print_init_begin();

# The redirect for LINKS output.
Irssi::Irc::Server::redirect_register('command cmd_sping', 0, 0,
    {
        'event 364' => 1,
    },
    {
        'event 365' => 1,
    },
    undef
);

Irssi::signal_add('redir event_links_line', 'event_links_line');
Irssi::signal_add('redir event_links_end',  'event_links_end');

Irssi::signal_add_first('event pong', 'event_pong');

Irssi::command_bind('sping',      'cmd_sping');
Irssi::command_bind('sping help', 'cmd_sping_help');

Irssi::settings_add_int('ho', 'ho_sping_max_time', 20);
Irssi::settings_add_bool('ho', 'ho_sping_full_report', 0);

Irssi::theme_register([
    'ho_sping_line',
    '$[25]0 - $1s',
]);

ho_print_init_end();
ho_print("Use /SPING HELP for help.");

# ---------------------------------------------------------------------

sub print_help {
    ho_print_help('head', $IRSSI{name});

    ho_print_help('section', 'Description');
    ho_print_help("This script does a latency check ".
        "of all servers on the network.");
    ho_print_help("It does so by first issuing /LINKS and then doing a ".
        "/PING <server> for each server.");
    ho_print_help("Make sure your settings 'cmds_max_at_once' and ".
        "'cmd_queue_speed' are set to proper values so this script can ".
        "issue the /PING commands as quickly as possible without ".
        "being disconnected for excess flood.\n");

    ho_print_help('section', 'Syntax');
    ho_print_help('syntax', 'SPING [HELP]');

    ho_print_help('section', 'Settings');
    ho_print_help('setting', 'ho_sping_max_time',
        'Maximum time to wait for PONG replies.');
    ho_print_help('setting', 'ho_sping_full_report',
        'Whether or not to print a full report.');
}

# ---------------------------------------------------------------------
