use strict;
use warnings;

use Irssi;
use Irssi::Irc;
use Irssi::HOSC::again;
use Irssi::HOSC::again 'Irssi::HOSC::Base';
use Irssi::HOSC::again 'Irssi::HOSC::Tools';
import Irssi::HOSC::Tools qw{get_named_token};

use vars qw[%IRSSI];

%IRSSI = Irssi::HOSC::Base::ho_get_IRSSI(
    authors     => 'James Seward',
    contact     => 'james@jamesoff.net',
    name        => 'ho_operwall',
    description => 'Sends operwall and locops messages named windows.',
    license     => 'Public Domain',
    url         => 'http://www.jamesoff.net/irc',
);

# ---------------------------------------------------------------------
#
# Thanks to:
# Garion - for creating the hosc project :)
#
# ---------------------------------------------------------------------
# catch a line typed in any operwall window, and operwall it to the
# server

# Keeps track of the most recent operwall messages per tag. Used to
# prevent duplication of operwalls.
my %operwall_history;

# ---------------------------------------------------------------------

sub cmd_operwall {
    my ($args, $server, $item) = @_;

    if ($args =~ m/^(status)|(help)|(example)/i ) {
        Irssi::command_runsub ('operwall', $args, $server, $item);
        return;
    }

    print_usage();
}

# ---------------------------------------------------------------------

sub cmd_operwall_help {
    print_help();
}

# ---------------------------------------------------------------------

sub cmd_operwall_status {
    print_status();
}

# ---------------------------------------------------------------------

sub cmd_operwall_example {
    print_example();
}

# ---------------------------------------------------------------------

sub event_operwall_text {
    my ( $text, $server, $witem ) = @_;
    my $active_window = Irssi::active_win();

    # Only process typed text in named windows.
    return unless length $active_window->{name} > 0;

    my $sdata = get_send_data_for_windowname(lc $active_window->{name});
    return unless defined $sdata->{type};

    for my $tag (@{ $sdata->{servers} }) {
        if ($tag eq 'active server') {
            # special tag!
            my $server = Irssi::active_server();
            if (!defined $server) {
                ho_print_error("No active server in this window.");
                return;
            }
            if ($sdata->{type} eq 'operwall') {
                $server->send_raw_now("OPERWALL :$text");
            } else {
                $server->send_raw_now("LOCOPS :$text");
            }
            return;
        }
        my $server = Irssi::server_find_tag($tag);
        next unless defined $server;
        next unless $server->{server_operator} or $server->{usermode} =~ /o/i;

        if ($sdata->{type} eq 'operwall') {
            $server->send_raw_now("OPERWALL :$text");
        } else {
            $server->send_raw_now("LOCOPS :$text");
        }
        return;
    }

    ho_print_warning("Not connected to a server in (" .
        (join ',', @{ $sdata->{servers} }) . ") for this window.");
}

# ---------------------------------------------------------------------
# catch an incoming wallop and reformat if it's an operwall

sub event_wallop {
    my ($server, $args, $sender, $addr) = @_;

    clear_operwall_history();

    my @ignorenicks = split(/ +/, Irssi::settings_get_str("ho_operwall_ignore"));
    if (grep /^$sender$/, @ignorenicks) {
        Irssi::signal_stop();
        return;
    }

    if ($args =~ s/^:OPERWALL - //) {
        process_incoming_operwall($server, $sender, $args);
    }

    if ($args =~ s/^:LOCOPS - //) {
        process_incoming_locops($server, $sender, $args);
    }
}

# ---------------------------------------------------------------------

sub process_incoming_operwall {
    my ($server, $sender, $text) = @_;
    my $tag    = $server->{tag};
    my $lc_tag = lc $tag;

    my $window_name = get_named_token(
        lc Irssi::settings_get_str('ho_operwall_operwall_windows'),
        $lc_tag);

    # Fergot about it if no window has been found.
    return if length $window_name == 0;

    if ($window_name eq 'devnull') {
        Irssi::signal_stop();
        return;
    }

    my $win = Irssi::window_find_name(lc $window_name);

    if (!defined $win) {
        ho_print_error("Operwall: window named $window_name for tag " .
            "$tag not found.");
        return;
    }

    Irssi::signal_stop();

    return if already_displayed($server, $sender, $text);

    add_to_history($server, $sender, $text);

    my @prepend_tags = split / +/,
        lc Irssi::settings_get_str('ho_operwall_ow_prepend_tag');

    if (grep /^$lc_tag$/, @prepend_tags) {
        $win->printformat(MSGLEVEL_WALLOPS | MSGLEVEL_CLIENTCRAP,
            'ho_operwall_tag', $tag, $sender, $text);
    } else {
        $win->printformat(MSGLEVEL_WALLOPS | MSGLEVEL_CLIENTCRAP,
            'ho_operwall', $sender, $text);
    }
}

# ---------------------------------------------------------------------

sub process_incoming_locops {
    my ($server, $sender, $args) = @_;
    my $tag    = $server->{'tag'};
    my $lc_tag = lc $tag;

    my $window_name = get_named_token(
        lc Irssi::settings_get_str('ho_operwall_locops_windows'),
        $lc_tag);

    # Fergot about it if no window has been found.
    return if length $window_name == 0;

    if ($window_name eq 'devnull') {
        Irssi::signal_stop();
        return;
    }

    my $win = Irssi::window_find_name(lc $window_name);

    if (!defined $win) {
        ho_print_error("Locops: window named $window_name for tag " .
            "$tag not found.");
        return;
    }

    Irssi::signal_stop();

    my @prepend_tags = split / +/,
        lc Irssi::settings_get_str('ho_operwall_lo_prepend_tag');

    if (grep /^$lc_tag$/, @prepend_tags) {
        $win->printformat(MSGLEVEL_WALLOPS | MSGLEVEL_CLIENTCRAP,
            'ho_locops_tag', $tag, $sender, $args);
    } else {
        $win->printformat(MSGLEVEL_WALLOPS | MSGLEVEL_CLIENTCRAP,
            'ho_locops', $sender, $args);
    }
}

# ---------------------------------------------------------------------

sub get_send_data_for_windowname {
    my ($windowname) = @_;

    my %data = (
        type    => undef,
        servers => [],
    );

    for my $type (qw[operwall locops]) {
        my $windows = Irssi::settings_get_str("ho_operwall_".$type."_windows");

        for my $dest (split /\s+/, $windows) {
            if ($dest =~ /^([^:]+):$windowname$/) {
                push @{ $data{servers} }, $1;
            } elsif ($dest eq $windowname) {
                $data{type} = $type;
                push @{ $data{servers} }, 'active server';
                return \%data;
            }
        }

        if (@{ $data{servers} } > 0) {
            $data{type} = $type;
            return \%data;
        }
    }

    return \%data;
}

# ---------------------------------------------------------------------

sub add_to_history {
    my ($server, $sender, $text) = @_;

    my $group = get_group(lc $server->{tag});
    return unless $group;

    my $item = {
        ts     => time(),
        sender => $sender,
        text   => $text,
    };

    push @{ $operwall_history{$group} }, $item;
}

# ---------------------------------------------------------------------

sub clear_operwall_history {
    my $history_time = Irssi::settings_get_int('ho_operwall_history_time');

    my %new_history;
    my $now = time();

    for my $group (keys %operwall_history) {
        my @history_items = @{ $operwall_history{$group} };
        for my $msg (@history_items) {
            if ($msg->{ts} >= $now - $history_time) {
                push @{ $new_history{$group} }, $msg;
            }
        }
    }

    undef %operwall_history;
    %operwall_history = %new_history;
}

# ---------------------------------------------------------------------

sub already_displayed {
    my ($server, $sender, $text) = @_;

    my $group = get_group(lc $server->{tag});
    return 0 unless $group;

    my $now = time();
    my $history_time = Irssi::settings_get_int('ho_operwall_history_time');
    return 0 unless defined $operwall_history{$group};

    my @history_items = @{ $operwall_history{$group} };
    for my $msg (@history_items) {
        if ($msg->{ts} >= $now - $history_time &&
            $msg->{sender} eq $sender &&
            $msg->{text} eq $text
        ) {
            return 1;
        }
    }

    return 0;
}

# ---------------------------------------------------------------------

sub get_group {
    my ($tag) = @_;
    my @groups =
        split /\s+/, lc Irssi::settings_get_str('ho_operwall_groups');

    for my $group (@groups) {
        my @servers = split /,/, $group;
        next unless grep /^$tag$/, @servers;
        return $group;
    }

    return undef;
}

# ---------------------------------------------------------------------
# Still ugly, but will be improved.

sub print_status {
    ho_print("Operwall/Locops status.");

    my %target_windows;

    ho_print("Recv. OW.  Network     Target window");
    my $windows = Irssi::settings_get_str("ho_operwall_operwall_windows");
    for my $dest (split /\s+/, $windows) {
        if ($dest =~ /^([^:]+):(.+)$/) {
            $target_windows{$2} = 1;
            ho_print((' ' x 11) . $1 . (' ' x (12 - length $1)) . $2);
        } else {
            $target_windows{$dest} = 1;
            ho_print((' ' x 11) . "[rest]      $dest");
        }
    }

    ho_print("Recv. LO.  Network     Target window");
    $windows = Irssi::settings_get_str("ho_operwall_locops_windows");
    for my $dest (split /\s+/, $windows) {
        if ($dest =~ /^([^:]+):(.+)$/) {
            $target_windows{$2} = 1;
            ho_print((' ' x 11) . $1 . (' ' x (12 - length $1)) . $2);
        } else {
            $target_windows{$dest} = 1;
            ho_print((' ' x 11) . "[rest]      $dest");
        }
    }

    ho_print("Sent OW/LO Window name Type      Target server");
    for my $window_name (sort keys %target_windows) {
        my $data = get_send_data_for_windowname($window_name);
        if (defined $data->{type}) {
            ho_print((' ' x 11) . $window_name .
                (' ' x (11 - length $window_name)) . " " . $data->{type}.
                (' ' x (10 - length $data->{type})) .
                join ', ', @{ $data->{servers} });
        } else {
            ho_print("$window_name: ERROR");
        }
    }
}

# ---------------------------------------------------------------------

ho_print_init_begin();

Irssi::theme_register([
    # i like my nicks right-aligned to 9 chars, with overspill
    'ho_operwall',     '[{nick $[!-9]0}] $1-',
    'ho_locops',       '[{nick $[!-9]0}] $1-',
    'ho_operwall_tag', '[$0] [{nick $[!-9]1}] $2-',
    'ho_locops_tag',   '[$0] [{nick $[!-9]1}] $2-',
]);

Irssi::signal_add('send text',     'event_operwall_text');
Irssi::signal_add('event wallops', 'event_wallop');

Irssi::settings_add_str("ho",  "ho_operwall_ignore",       '');

Irssi::settings_add_str('ho',  'ho_operwall_operwall_windows', 'operwall');
Irssi::settings_add_str('ho',  'ho_operwall_locops_windows',   'locops');
Irssi::settings_add_str('ho',  'ho_operwall_groups',           '');
Irssi::settings_add_int('ho',  'ho_operwall_history_time',     15);
Irssi::settings_add_str('ho',  'ho_operwall_ow_prepend_tag',   '');
Irssi::settings_add_str('ho',  'ho_operwall_lo_prepend_tag',   '');

Irssi::command_bind('operwall',         'cmd_operwall');
Irssi::command_bind('operwall help',    'cmd_operwall_help');
Irssi::command_bind('operwall example', 'cmd_operwall_example');
Irssi::command_bind('operwall status',  'cmd_operwall_status');

ho_print("If you have an alias '/OPERWALL', remove that for optimal ".
    "functionality of this script.");
ho_print("Use /OPERWALL HELP for help.");
ho_print_init_end();

# ---------------------------------------------------------------------

sub print_usage {
    ho_print_help('section', 'Syntax');
    ho_print_help('syntax', 'OPERWALL help');
    ho_print_help('syntax', 'OPERWALL example');
    ho_print_help('syntax', 'OPERWALL status');
}

sub print_help {
    ho_print_help('head', $IRSSI{name});

    print_usage();

    ho_print_help('section', 'Description');
    ho_print_help('This script reformats all OPERWALL and LOCOPS '.
        "messages and sends them to the right windows. Also, it allows ".
        "text to be typed in those windows, which will then be sent as ".
        "OPERWALL or LOCOPS message to the right server.\n");
    ho_print_help("If you only oper on one server, forget about the ".
        "complex settings and just create a window named 'operwall' and ".
        "one named 'locops'.\n");
    ho_print_help("If you want to use the script to manipulate ".
        "OPERWALL and LOCOPS for multiple servers on multiple networks, ".
        "read the explanation of the settings carefully. The meaning of " .
        "the settings is best shown by example: /OPERWALL EXAMPLE.\n");

    ho_print_help('section', 'Settings');
    ho_print_help('setting', 'ho_operwall_operwall_windows',
        'Destination windows of OPERWALL messages. '.
        'This is a multitoken. See /HO HELP MULTITOKEN');
    ho_print_help('setting', 'ho_operwall_locops_windows',
        'Destination windows of LOCOPS messages. '.
        'This is a multitoken. See /HO HELP MULTITOKEN');
    ho_print_help('setting', 'ho_operwall_groups',
        'Space separated list of comma separated network tags. Each comma '.
        'separated list defines one group of tags which are considered to '.
        'be on the same network.');
    ho_print_help('setting', 'ho_operwall_ow_prepend_tag',
        'Space separated list of network tags for which each operwall '.
        'message must have [tag] in front of it.');
    ho_print_help('setting', 'ho_operwall_lo_prepend_tag',
        'Space separated list of network tags for which each locops '.
        'message must have [tag] in front of it.');
}

sub print_example {
    ho_print_help('section', 'Example');

    ho_print_help("Consider the following settings:\n");
    ho_print_help('setting', "ho_operwall_operwall_windows",
        "operwall cnqnet:ow_cnq vuurwerk:ow_efnet ".
        "dkom:ow_efnet blackened:ow_efnet test1:blah test2:blah");
    ho_print_help('setting', "ho_operwall_locops_windows",
        "locops vuurwerk:lo_vuurwerk test1:bleh test2:devnull");
    ho_print_help('setting', "ho_operwall_groups",
        "vuurwerk,dkom,blackened test1,test2\n");

    ho_print_help("Operwalls for network tag 'cnqnet' will be sent to the ".
        "window named 'ow_cnq'. Operwalls for tags 'vuurwerk', 'dkom', and ".
        "'blackened' all go to the window 'ow_efnet'. The operwalls for ".
        "'test1' and 'test2' both go to window 'blah', and all other ".
        "operwalls go to window 'operwall'.\n");
    ho_print_help("When typing in window 'ow_cnq', the script can see ".
        "that this should be an Operwall message for tag 'cnqnet', so ".
        "it will search for the server with that tag and send the operwall ".
        "to there.");
    ho_print_help("For a message in window 'ow_efnet', the script will " .
        "first see if a connection to tag 'vuurwerk' exists. If so, that " .
        "is used to send the operwall. If not, the script will try tags ".
        "'dkom' and 'blackened', i.e. the same order as in the setting.\n");
    ho_print_help("If the client is receiving operwall messages for all ".
        "three tags that send to ow_efnet, the script will still only ".
        "display each message once. That is because the ho_operwall_groups ".
        "setting indicates that these three servers are on the same ".
        "network.\n");
    ho_print_help("For Locops message, the same rules are followed, except ".
        "that they can't be grouped.");
}
