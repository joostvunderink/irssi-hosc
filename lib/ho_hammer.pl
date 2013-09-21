# ho_hammer.pl
#
# $Id: ho_hammer.pl,v 1.5 2004/09/11 12:21:49 jvunder REL_0_1 $
#
# Part of the Hybrid Oper Script Collection.
#
# Looks for hammering clients and acts upon them.
#
# TODO: code HOSC::Kliner and use it.

use strict;
use vars qw(%IRSSI);

use Irssi;
use Irssi::Irc;
use HOSC::again;
use HOSC::again 'HOSC::Base';
use HOSC::again 'HOSC::Tools';
use HOSC::again 'HOSC::Kliner';
import HOSC::Tools qw{is_server_notice};

# ---------------------------------------------------------------------

%IRSSI = HOSC::Base::ho_get_IRSSI(
    name        => 'Hammer',
    description => 'Looks for hammering clients and acts upon them.',
);

# Hashtable with connection times per host
# Key is the host
# Value is an array of connection times (unix timestamp)
my %conntimes;

# The last time the connection hash has been cleaned (unix timestamp)
my $conntimes_last_cleaned = 0;

my $kliner = HOSC::Kliner->new();

# ---------------------------------------------------------------------
# A Server Event has occurred. Check if it is a server NOTICE;
# if so, process it.

sub event_serverevent {
    my ($server, $msg, $nick, $hostmask) = @_;

    return unless is_server_notice(@_);

    process_event($server, $msg);
}


# ---------------------------------------------------------------------
# This function takes a server notice and matches it with a few regular
# expressions to see if any special action needs to be taken.

sub process_event {
    my ($server, $msg) = @_;

    # HYBRID 7 - need a setting to determine which server type we have!
    # Client connect: nick, user, host, ip, class, realname
    if ($msg =~ /Client connecting: (.*) \((.*)@(.*)\) \[(.*)\] {(.*)} \[(.*)\]/) {
        process_connect($server, $1, $2, $3, $4, $5, $6);
        return;
    }

    # HYBRID 6
    # Client connect: nick, user, host, ip, class, realname
    if ($msg =~ /Client connecting: (.*) \((.*)@(.*)\) \[(.*)\] {(.*)}/) {
        process_connect($server, $1, $2, $3, $4, $5, undef);
        return;
    }
}

# ---------------------------------------------------------------------
# This function processes a client connect.
# It shows warning in case of:
# - many connects in a short timespan from a single host

sub process_connect {
    my ($server, $nick, $user, $host, $ip, $class, $realname) = @_;

    return unless Irssi::settings_get_bool('ho_hammer_enable');

    return if $ip eq '255.255.255.255' &&
        Irssi::settings_get_bool('ho_hammer_ignore_spoofs');

    my $tag = $server->{tag};

    # Check whether the server notice is on one of the networks we are
    # monitoring.
    my $watch_this_network = 0;
    foreach my $network (split /\s+/,
        lc(Irssi::settings_get_str('ho_hammer_network_tags'))
    ) {
        if ($network eq lc($server->{tag})) {
            $watch_this_network = 1;
            last;
        }
    }
    return unless $watch_this_network;

    my $now = time();
    push @{ $conntimes{$tag}->{$host} }, $now;

    # Check whether this host has connected more than
    # ho_hammer_warning_count times in the past
    # ho_hammer_warning_time seconds.
    if (@{ $conntimes{$tag}->{$host} } ==
        Irssi::settings_get_int('ho_hammer_warning_count')
    ) {
        # Get the time of the first connect
        my $firsttime = ${ $conntimes{$tag}->{$host} }[0];

        # Get the time of the last connect
        my $lasttime = ${ $conntimes{$tag}->{$host} }[@{ $conntimes{$tag}->{$host} } - 1];

        my $timediff = $lasttime - $firsttime;

        if ($timediff < Irssi::settings_get_int('ho_hammer_warning_time')) {
            ho_print_warning("Hammer: " . @{ $conntimes{$tag}->{$host} } . "/".
                "$timediff: $nick ($user\@$host).");
        }
    }

    # Check whether this host has connected more than
    # ho_hammer_violation_count times in the past
    # ho_hammer_violation_time seconds.
    if (@{ $conntimes{$tag}->{$host} } >=
        Irssi::settings_get_int('ho_hammer_violation_count')) {
        # Get the time of the first connect
        my $firsttime = ${ $conntimes{$tag}->{$host} }[0];

        # Get the time of the last connect
        my $lasttime = ${ $conntimes{$tag}->{$host} }[@{ $conntimes{$tag}->{$host} } - 1];

        my $timediff = $lasttime - $firsttime;

        if ($timediff < Irssi::settings_get_int('ho_hammer_violation_time')) {
            my $time   = Irssi::settings_get_int('ho_hammer_kline_time');
            my $reason = Irssi::settings_get_str('ho_hammer_kline_reason');

            # If number of connections is equal to max number of connections
            # allowed, kline user@host. If it is higher, that means the user
            # has been k-lined once and has changed ident; therefore, kline
            # *@host.
            if (@{ $conntimes{$tag}->{$host} } ==
                Irssi::settings_get_int('ho_hammer_violation_count')
            ) {
                $kliner->kline(
                    server => $server,
                    user   => $user,
                    host   => $host,
                    reason => $reason,
                );
                ho_print("K-lined $user\@$host for hammering.");
            } else {
                $kliner->kline(
                    server => $server,
                    user   => '*',
                    host   => $host,
                    reason => $reason,
                );
                ho_print("K-lined *\@$host for hammering.");
            }
        }
    }

    # Clean up the connection times hash to make sure it doesn't grow
    # to infinity :)
    # Do this every 60 seconds.
    if ($now > $conntimes_last_cleaned + 60) {
        $conntimes_last_cleaned = $now;
        cleanup_conntimes_hash(300);
    }
}



# ---------------------------------------------------------------------
# Cleans up the connection times hash.
# The only argument is the number of seconds to keep the hostnames for.
# This means that if the last connection from a hostname was longer ago
# than that number of seconds, the hostname is dropped from the hash.

sub cleanup_conntimes_hash {
    my ($keeptime) = @_;
    my $now = time();

    # If the last time this host has connected is over $keeptime secs ago,
    # delete it.
    for my $tag (keys %conntimes) {
        for my $host (keys %{ $conntimes{$tag} }) {
            my $lasttime = ${ $conntimes{$tag}->{$host} }[@{ $conntimes{$tag}->{$host} } - 1];

            # Discard this host if no connections have been made from it during
            # the last $keeptime seconds.
            if ($now > $lasttime + $keeptime) {
                delete $conntimes{$tag}->{$host};
            }
        }
    }
}

# ---------------------------------------------------------------------
# The /hammer command.

sub cmd_hammer {
    my ($data, $server, $item) = @_;
    if ($data =~ m/^[(help)]/i ) {
        Irssi::command_runsub ('hammer', $data, $server, $item);
    } else {
        ho_print("Use /HAMMER HELP for help.")
    }
}

# ---------------------------------------------------------------------
# The /hammer help command.

sub cmd_hammer_help {
    print_help();
}

# ---------------------------------------------------------------------

ho_print_init_begin();

Irssi::signal_add_first('server event', 'event_serverevent');

Irssi::command_bind('hammer',      'cmd_hammer');
Irssi::command_bind('hammer help', 'cmd_hammer_help');

Irssi::settings_add_bool('ho', 'ho_hammer_enable',            0);
Irssi::settings_add_bool('ho', 'ho_hammer_ignore_spoofs',     1);
Irssi::settings_add_int('ho', 'ho_hammer_warning_count',      8);
Irssi::settings_add_int('ho', 'ho_hammer_warning_time',     100);
Irssi::settings_add_int('ho', 'ho_hammer_violation_count',   10);
Irssi::settings_add_int('ho', 'ho_hammer_violation_time',   120);
Irssi::settings_add_int('ho', 'ho_hammer_kline_time',      1440);
Irssi::settings_add_str('ho', 'ho_hammer_network_tags',      '');
Irssi::settings_add_str('ho', 'ho_hammer_kline_reason',
    '[Automated K-line] Reconnecting too fast. Please try again later.');

if (length Irssi::settings_get_str('ho_hammer_network_tags') > 0) {
    if (Irssi::settings_get_bool('ho_hammer_enable')) {
        ho_print("Script enabled for the following tags: " .
            Irssi::settings_get_str('ho_hammer_network_tags'));
    } else {
        ho_print("Script disabled. The following tags have been set: " .
            Irssi::settings_get_str('ho_hammer_network_tags') .
            ". Use /SET ho_hammer_enable ON to enable the script.");
    }
} else {
    ho_print_warning("No network tags set. Please use ".
        "/SET ho_hammer_network_tags tag1 tag2 tag3 .. ".
        "to choose the tags the script will work on.");
}

ho_print_init_end();
ho_print("Use /HAMMER HELP for help.");

# ---------------------------------------------------------------------

sub print_help {
    ho_print_help('head', $IRSSI{name});

    ho_print_help('section', 'Description');
    ho_print_help("This script tracks reconnecting clients and can take action on ".
        "them, being either printing a warning or banning them from the server ".
        "automatically. Clients that reconnect rapidly are called 'hammering ".
        "clients', which explains the name of this script.\n");

    ho_print_help('section', 'Settings');
    ho_print_help('setting', 'ho_hammer_enable',
        'Master setting to enable/disable this script.');
    ho_print_help('setting', 'ho_hammer_network_tags',
        'Tags of the networks hammering clients must be tracked.');
    ho_print_help('setting', 'ho_hammer_ignore_spoofs',
        'Whether spoofs should be ignored.');
    ho_print_help('setting', 'ho_hammer_kline_reason',
        'The reason of the ban placed on the hammering client.');

    ho_print_help('setting', 'ho_hammer_warning_count', 'and');
    ho_print_help('setting', 'ho_hammer_warning_time',
        'If clients from a host connect more than ho_hammer_warning_count '.
        'times in ho_hammer_warning_time seconds, a warning is printed.');

    ho_print_help('setting', 'ho_hammer_violation_count', 'and');
    ho_print_help('setting', 'ho_hammer_violation_time',
        'If clients from a host connect more than ho_hammer_violation_count '.
        'times in ho_violation_warning_time seconds, the host is banned.');
}
