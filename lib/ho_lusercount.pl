# This provides a statusbar item containing the users on the server.
# It uses /lusers for that, plus usermode +c to increase/decrease the
# number of users whenever a client (dis)connects.

# Known bugs:
# * Doing /lusers <other_server> <other_server> may confuse the script.
# * You need to do a manual /lusers for every network after loading.
# * The "I have <num> clients" server notice gets eaten. It is resent,
#   but not with optimal formatting.

# Todo:
# Add different formats for increase/decrease history lines with different
# colours.

# /lusers output
# >> :irc.efnet.nl 255 Garion :I have 10970 clients and 2 servers

use strict;
use warnings;
use vars qw(%IRSSI);

# Why doesn't use constant work in my irssi? *confused*
#use constant MIN_HISTORY_DELTA_TIME => 10; # seconds
my $MIN_HISTORY_DELTA_TIME = 10;

use Irssi qw(
    settings_get_int settings_get_str settings_get_bool
    settings_set_int settings_set_str settings_set_bool
    settings_add_int settings_add_str settings_add_bool
);
use Irssi::TextUI; # for statusbar
use HOSC::again;
use HOSC::again 'HOSC::Base';
use HOSC::again 'HOSC::Tools';

# ---------------------------------------------------------------------

%IRSSI = HOSC::Base::ho_get_IRSSI(
    name        => 'Lusercount',
    description => 'Statusbar item with number of clients, and client history graph.',
);

# ---------------------------------------------------------------------
#
# Thanks to:
#
# - mofo, for suggestions

# ---------------------------------------------------------------------

# Hash that holds a {$network}->{variable} substructure.
my %luserinfo;

# Statusbar timer refresh handle
my $delta_handle_statusbar;

# Statusbar timer refresh time
my $delta_statusbar;

# History timer refresh handle
my $delta_handle_history;

# History timer refresh time
my $delta_history;

# ---------------------------------------------------------------------
# >> :irc.efnet.nl 255 Garion :I have 10970 clients and 2 servers

sub event_lusers_output {
    my ($server, $msg) = @_;
    if ($msg =~ /I have ([0-9]+) clients/o) {
        for my $n (split /\s+/,
                        lc(settings_get_str('ho_lusercount_networks'))
        ) {
            if (lc($n) eq lc($server->{tag})) {
                $luserinfo{$n}->{numclients} = $1;
            }
        }

        # Re-send the message. Needs proper formatting..?
        $msg =~ s/^[^:]+://;
        Irssi::print($msg, MSGLEVEL_CRAP);

        Irssi::statusbar_items_redraw('lusercount');
    }
}

# ---------------------------------------------------------------------

# A Server Event has occurred. Check if it is a server NOTICE;
# if so, process it.

sub event_serverevent {
    my ($server, $msg, $nick, $hostmask) = @_;
    my ($nickname, $username, $hostname);

    # If it is not a NOTICE, we don't want to have anything to do with it.
    return if $msg !~ /^NOTICE/o;

    # If the hostmask is set, it is not a server NOTICE, so we'll ignore it
    # as well.
    return if length($hostmask) > 0;

    # Check whether the server notice is on one of the networks we are
    # monitoring.
    my $watch_this_network = 0;
    foreach my $network (split /\s+/,
        lc(settings_get_str('ho_lusercount_networks'))
    ) {
        if ($network eq lc($server->{tag})) {
            $watch_this_network = 1;
            last;
        }
    }
    return unless $watch_this_network;

    my $ownnick = $server->{'nick'};

    # Remove the NOTICE part from the message
    # NOTE: this is probably unnecessary.
    $msg =~ s/^NOTICE $ownnick ://;

    # Remove the server prefix
    # NOTE: this is probably unnecessary.
    #$msg =~ s/^$prefix//;

    process_event($server, $msg);
}

# ---------------------------------------------------------------------

# This function takes a server notice and matches it with a few regular
# expressions to see if any special action needs to be taken.

sub process_event {
    my ($server, $msg) = @_;

    # Client connect: nick, user, host, ip, class, realname
    if (index($msg ,"tice -- Client connecting: ") >= 0) {
        client_add(lc($server->{tag}));
        if (settings_get_bool('ho_lusercount_suppress_snotices')) {
            Irssi::signal_stop();
        }
        return;
    }

    # Client exit: nick, user, host, reason, ip
    if (index($msg, "tice -- Client exiting: ") >= 0) {
        client_remove(lc($server->{tag}));
        if (settings_get_bool('ho_lusercount_suppress_snotices')) {
            Irssi::signal_stop();
        }
        return;
    }
}

# ---------------------------------------------------------------------
# Refreshes the number of clients connected in the past N seconds,
# where N is the setting ho_lusercount_delta_statusbar.

sub delta_statusbar {
    foreach my $n (split /\s+/,
                    lc(settings_get_str('ho_lusercount_networks'))
    ) {
        my $l = $luserinfo{$n};
        $l->{deltaclients}             = $l->{deltaclients_temp};
        $l->{deltaclients_temp}        = 0;
        $l->{connectedclients}         = $l->{connectedclients_temp};
        $l->{connectedclients_temp}    = 0;
        $l->{disconnectedclients}      = $l->{disconnectedclients_temp};
        $l->{disconnectedclients_temp} = 0;
    }

    my $time = settings_get_int("ho_lusercount_delta_statusbar") * 1000;
    $time = 5000 if $time < 1000;

    if ($time != $delta_statusbar) {
        Irssi::print("Changing statusbar timer.");
        Irssi::timeout_remove($delta_handle_statusbar)
            if $delta_handle_statusbar;
        $delta_statusbar = $time;
        Irssi::timeout_add($delta_statusbar, 'delta_statusbar', undef);
    }
}

# ---------------------------------------------------------------------

sub delta_history {
    my $now = time();
    foreach my $n (split /\s+/,
                    lc(settings_get_str('ho_lusercount_networks'))
    ) {
        $luserinfo{$n}->{client_history}->{$now} = $luserinfo{$n}->{numclients};
    }

    clean_delta_history();

    my $time = settings_get_int("ho_lusercount_delta_history") * 1000;
    $time = $MIN_HISTORY_DELTA_TIME if $time < $MIN_HISTORY_DELTA_TIME;

    if ($time != $delta_history) {
        ho_print("lusercount - Changing history timer.");
        if ($delta_handle_history) {
            Irssi::timeout_remove($delta_handle_history);
        }
        $delta_history = $time;
        Irssi::timeout_add($delta_history, 'delta_history', undef);
    }
}

# ---------------------------------------------------------------------

sub clean_delta_history {
    my $keeptime = settings_get_int("ho_lusercount_history_time");
    my $now = time();

    for my $n (split /\s+/,
        lc(settings_get_str('ho_lusercount_networks'))
    ) {
        next unless defined $luserinfo{$n};

        for my $time (sort {$a <=> $b} keys %{ $luserinfo{$n}->{client_history} }) {
            if ($now - $time > $keeptime) {
                delete($luserinfo{$n}->{client_history}->{$time});
            } else {
                last;
            }
        }
    }
}

# ---------------------------------------------------------------------
# Adds a client object to the client array, and an entry in the client
# hashtable pointing to this object.

sub client_add {
    my ($n) = @_;

    # Increase the number of clients.
    $luserinfo{$n}->{numclients}++;
    $luserinfo{$n}->{deltaclients_temp}++;
    $luserinfo{$n}->{connectedclients_temp}++;

    # Redraw the statusbar item.
    Irssi::statusbar_items_redraw("lusercount");
}

# ---------------------------------------------------------------------
# Removes a client from the client array and from the client hash.
# Argument is the nickname of the client to be removed.
# If this nickname is not in the client array, nothing happens.

sub client_remove {
    my ($n) = @_;

    # Decrease the number of clients.
    $luserinfo{$n}->{numclients}--;
    $luserinfo{$n}->{deltaclients_temp}--;
    $luserinfo{$n}->{disconnectedclients_temp}++;

    # Redraw the statusbar item.
    Irssi::statusbar_items_redraw("lusercount");
}

# ---------------------------------------------------------------------

sub cmd_lusercount {
    my ($data, $server, $item) = @_;
    if ($data =~ /^[(history)|(help)]/i ) {
        Irssi::command_runsub ('lusercount', $data, $server, $item);
    } else {
        ho_print("Use '/lusercount history <network>' to show the ".
            "history of that network or '/lusercount help' for help.")
    }
}

# ---------------------------------------------------------------------

sub cmd_lusercount_help {
    print_help();
}

# ---------------------------------------------------------------------
# Shows the history of connected clients.

sub cmd_lusercount_history {
    my ($data, $server, $item) = @_;

    if ($data =~ /^\s*$/) {
        ho_print("Use /LUSERCOUNT HISTORY <network> [time in minutes].");
        return;
    }

    my ($tag, $time);
    if ($data =~ /^(\S+)\s+(\d+)/) {
        ($tag, $time) = ($1, int($2));
    } else {
        $tag = lc($data);
        $time = 0;
    }

    if (!defined $luserinfo{$tag}) {
        ho_print("No lusercount history available for network '$tag'.");
        return;
    }

    # Determine the begin time of the history to display.
    my $begin_time = 0;
    $begin_time = int(time - 60 * $time) if $time > 0;

    Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'ho_lusercount_history_begin',
        $tag);
    my $previous_time = undef;
    my $diff = 0;

    my $max_diff = get_max_diff($tag, $begin_time);

    my $graph_width = settings_get_int('ho_lusercount_graph_width');
    $graph_width++ unless $graph_width % 2; # make sure width is odd

    for my $time (sort {$a <=> $b}
                    keys %{ $luserinfo{$tag}->{client_history} }
    ) {
        next if $time < $begin_time;
        my $humantime = sprintf("%02d:%02d",
                            (localtime($time))[2], (localtime($time))[1]);
        my $diff_col = '%n';

        if (defined $previous_time) {
            $diff =
                $luserinfo{$tag}->{client_history}->{$time} -
                $luserinfo{$tag}->{client_history}->{$previous_time};

            if ($diff > 0.6 * $max_diff) {
                $diff_col = '%G';
            } elsif ($diff < - 0.6 * $max_diff) {
                $diff_col = '%R';
            }
        }

        Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'ho_lusercount_history_line',
            $humantime,
            sprintf("%4d", $luserinfo{$tag}->{client_history}->{$time}),
            sprintf("%3d", $diff),
            get_graph_line($diff, $max_diff, $graph_width)
        );
        $previous_time = $time;
    }
    Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'ho_lusercount_history_end',
        $tag);
}

# ---------------------------------------------------------------------
# Returns the maximum difference between 2 consecutive timestamps in
# the client history of $network_tag.

sub get_max_diff {
    my ($network_tag, $begin_time) = @_;
    my $previous_time = undef;
    my $diff = 0;
    my $maxdiff = 0;
    $begin_time = 0 unless defined $begin_time;

    for my $time (
        sort {$a <=> $b}
            keys %{ $luserinfo{$network_tag}->{client_history} }
    ) {
        next if $time < $begin_time;
        if (defined $previous_time) {
            $diff = abs(
                $luserinfo{$network_tag}->{client_history}->{$time} -
                $luserinfo{$network_tag}->{client_history}->{$previous_time}
            );
        }

        $maxdiff = $diff if $diff > $maxdiff;

        $previous_time = $time;
    }

    return $maxdiff;
}

# ---------------------------------------------------------------------

sub get_graph_line {
    my ($diff, $max_diff, $width) = @_;

    my $half_width = int(0.5 * $width);
    my $left = " " x $half_width;
    my $right = $left;

    # Don't bother if there is no difference.
    return $left . '|' . $right if $max_diff == 0;

    my $num_blocks = int( abs( $half_width * ($diff / $max_diff) ) );

    if ($diff > 0) {
        $right = '*' x $num_blocks . ' ' x ($half_width - $num_blocks);
    } elsif ($diff < 0) {
        $left  = ' ' x ($half_width - $num_blocks) . '*' x $num_blocks;
    }

    return $left . '|' . $right;
}

# ---------------------------------------------------------------------
# Statusbar item determination function.

sub lusercount_sb {
    my ($item, $get_size_only) = @_;

    my $txt = "{sb ";
    for my $n (split /\s+/, lc(settings_get_str('ho_lusercount_networks'))) {
        if (defined($luserinfo{$n})) {
            my $info = settings_get_str('ho_lusercount_format');
            $info =~ s/\$n/$n/;
            $info =~ s/\$c/$luserinfo{$n}->{numclients}/;
            $info =~ s/\$D/$luserinfo{$n}->{deltaclients}/;
            $info =~ s/\$i/$luserinfo{$n}->{connectedclients}/;
            $info =~ s/\$d/$luserinfo{$n}->{disconnectedclients}/;
            $txt .= $info . " ";
        }
    }

      $txt =~ s/ $/}/;
    $item->default_handler($get_size_only, "$txt", undef, 1);
}

# ---------------------------------------------------------------------

ho_print_init_begin();

Irssi::signal_add_first('server event', 'event_serverevent');
Irssi::signal_add_first('event 255', 'event_lusers_output');

Irssi::command_bind('lusercount', 'cmd_lusercount');
Irssi::command_bind('lusercount help', 'cmd_lusercount_help');
Irssi::command_bind('lusercount history', 'cmd_lusercount_history');

settings_add_int('ho', 'ho_lusercount_delta_statusbar', 10);
settings_add_int('ho', 'ho_lusercount_delta_history', 300);
settings_add_int('ho', 'ho_lusercount_history_time', 86400);
settings_add_str('ho', 'ho_lusercount_networks', "");
settings_add_bool('ho', 'ho_lusercount_suppress_snotices', 0);
settings_add_str('ho', 'ho_lusercount_format', '$n: $c/$D ($i:$d)');
settings_add_int('ho', 'ho_lusercount_graph_width', 40);

Irssi::theme_register( [
    'ho_lusercount_history_begin',
    '%Y+-%n Lusercount history for $0:',

    'ho_lusercount_history_line',
    '%Y|%n $0 - $1 ($2) $3',

    'ho_lusercount_history_end',
    '%Y+-%n End of lusercount history for $0.',
]);

Irssi::statusbar_item_register('lusercount', '{sb $1-}', 'lusercount_sb');

Irssi::statusbar_items_redraw("lusercount");

# Add the statusbar update timer
$delta_statusbar = settings_get_int("ho_lusercount_delta_statusbar") * 1000;
$delta_statusbar = 5000 if $delta_statusbar < 1000;
$delta_handle_statusbar =
    Irssi::timeout_add($delta_statusbar, 'delta_statusbar', undef);

# Add the history update timer
$delta_history = settings_get_int("ho_lusercount_delta_history") * 1000;
$delta_history = $MIN_HISTORY_DELTA_TIME
    if $delta_history < $MIN_HISTORY_DELTA_TIME;
$delta_handle_history =
    Irssi::timeout_add($delta_history, 'delta_history', undef);

if (length(settings_get_str('ho_lusercount_networks')) == 0) {
    ho_print("Use /SET ho_lusercount_networks <networks> to set ".
        "the list of network tags the lusercount must be tracked on. This is ".
        "a space separated list.");
}

ho_print_init_end();
ho_print('Use /LUSERCOUNT HELP for help.');

# ---------------------------------------------------------------------

sub print_help {
    ho_print_help('head', $IRSSI{name});

    ho_print_help('section', 'Syntax');
    ho_print_help('syntax', 'LUSERCOUNT HISTORY <tag> [<time>]');

    ho_print_help('section', 'Description');
    ho_print_help("This script provides a statusbar item named ".
        "'lusercount' which keeps track of the number of users on any ".
        "number of servers by means of client connect and exit server ".
        "notices.");
    ho_print_help("The appearance of this statusbar item is determined ".
        "by the ho_lusercount_format setting. Use that to tweak the ".
        "appearance to your liking. There are 5 special variables in this ".
        "setting, which will be replaced by their value:");
    ho_print_help('  $n - the network tag');
    ho_print_help('  $c - the number of clients');
    ho_print_help('  $D - the delta (change) in clients in the past time unit');
    ho_print_help('  $i - the increase in clients in the past time unit');
    ho_print_help('  $d - the decrease in clients in the past time unit');
    ho_print_help('$D is $i plus $d.' . "\n");

    ho_print_help('The other feature of this script is that it keeps track '.
        'of the history of the number of clients on servers. That history '.
        "can be displayed via the 'lusercount history' command. The first ".
        'argument is the network tag to display, and the second (optional) '.
        "argument indicates that only the last N minutes should be shown.\n");

    ho_print_help('section', 'Settings');
    ho_print_help('setting', 'ho_lusercount_format',
        'Appearance of the statusbar.');
    ho_print_help('setting', 'ho_lusercount_network_tags',
        'Tags of the networks the lusercount must be tracked.');
    ho_print_help('setting', 'ho_lusercount_delta_statusbar',
        'Time between two consecutive statusbar updates, in seconds.');
    ho_print_help('setting', 'ho_lusercount_delta_history',
        'Time between two consecutive history snapshots, in seconds.');
    ho_print_help('setting', 'ho_lusercount_history_time',
        'How long to keep usercount history, in seconds.');
    ho_print_help('setting', 'ho_lusercount_graph_width',
        'Width of the lusercount history graph.');
    ho_print_help('setting', 'ho_lusercount_suppress_snotices',
        'Whether this script should block the client connect/exit '.
        'server notices after having processed them.');
}

# ---------------------------------------------------------------------

