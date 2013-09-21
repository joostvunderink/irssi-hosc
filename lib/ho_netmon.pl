use strict;
use warnings;
use vars qw(%IRSSI);

use POSIX;
use Irssi;
use Irssi::Irc;           # for redirect_register()
use Irssi::TextUI;        # for statusbar
use HOSC::again;
use HOSC::again 'HOSC::Base';
use HOSC::again 'HOSC::Tools';
import HOSC::Tools qw{is_server_notice seconds_to_dhms};

use constant NETMON_FILENAME => 'netmon.data';

# ---------------------------------------------------------------------

%IRSSI = HOSC::Base::ho_get_IRSSI(
    name        => 'ho_netmon',
    description => 'Monitors the network for split servers.',
);

# Data hash.
my %status;

# Temp hash for server checking.
my %checked_servers;

my @subcommands = qw[help status check list learn save load add remove name];

sub event_serverevent {
    my ($server, $msg, $nick, $hostmask) = @_;
    my ($nickname, $username, $hostname);

    return unless is_server_notice(@_);

    my $tag = lc $server->{tag};
    return unless grep /^$tag$/,
        split / +/, lc Irssi::settings_get_str('ho_netmon_network_tags');

    my $ownnick = $server->{nick};

    # Remove the NOTICE part from the message
    # NOTE: this is probably unnecessary.
    $msg =~ s/^NOTICE $ownnick ://;
    $msg =~ s/^NOTICE . ://;
    $msg =~ s/\*\*\* Notice -- //;

    # -- Server split messages (all splits create this):
    # Server services.eu split from hub.dk
    # test.sente.nl had been connected for 0 days,  0:00:07
    # -- Server join messages:
    # Server hub.efnet.nl being introduced by hub.uk
    # Link with chanfix.carnique.nl[unknown@255.255.255.255] established:
    # We need the second message too because not all joins generate the
    # first message.
    if ($msg =~ /^Server (\S+) split from \S+$/) {
        process_split($tag, $1);
    } elsif ($msg =~ /^(\S+) was connected for/) {
        process_split($tag, $1);
    } elsif ($msg =~ /^Server (\S+) being introduced by \S+$/) {
        process_join($tag, $1);
    } elsif ($msg =~ /^Link with ([^[]+)(?:\[.+\])? established/) {
        process_join($tag, $1);
    }
}

# ---------------------------------------------------------------------
# Statusbar item determination function.

sub netmon_sb {
    my ($item, $get_size_only) = @_;

    my $txt = '';# = "{sb ";

    for my $tag (sort keys %status) {
        my $missing = 0;
        my $tag_txt = "$tag: ";
        for my $server (sort keys %{ $status{$tag} }) {
            if ($status{$tag}->{$server}->{status} eq 'missing') {
                $missing++;
                $tag_txt .= $status{$tag}->{$server}->{name} . ",";
            }
        }
        $tag_txt =~ s/,$/ /;
        if ($missing > Irssi::settings_get_int('ho_netmon_sb_max_servers')) {
            $txt .= "$tag: $missing missing ";
        } elsif ($missing > 0) {
            $txt .= $tag_txt
        }
    }

      $txt =~ s/ $//;
    if (length $txt) {
        $item->default_handler($get_size_only, "{sb nm: $txt}", undef, 1);
    } else {
        $item->default_handler($get_size_only, "{sb nm: all ok}", undef, 1);
    }
}

# ---------------------------------------------------------------------

sub cmd_netmon {
    my ($data, $server, $item) = @_;

    for my $cmd (@subcommands) {
        if ($data =~ m/^$cmd/i ) {
            Irssi::command_runsub ('netmon', $data, $server, $item);
            Irssi::statusbar_items_redraw('netmon');
            return;
        }
    }

    print_syntax();
}

# ---------------------------------------------------------------------

sub cmd_netmon_help {
    print_help();
}

# ---------------------------------------------------------------------

sub cmd_netmon_load {
    if (load_netmon_data()) {
        ho_print("Loaded netmon data successfully.");
    } else {
        ho_print("Not loaded netmon data.");
    }
}

# ---------------------------------------------------------------------

sub cmd_netmon_save {
    if (save_netmon_data()) {
        ho_print("Saved netmon data successfully.");
    } else {
        ho_print("Not saved netmon data.");
    }
}

# ---------------------------------------------------------------------

sub cmd_netmon_status {
    my ($data, $server, $item) = @_;

    if ($data) {
        my $tag = lc $data;
        print_status($tag);
    } else {
        ho_print("Status is available for the following tags: " .
            lc Irssi::settings_get_str('ho_netmon_network_tags'));
    }
}

# ---------------------------------------------------------------------

sub cmd_netmon_list {
    my ($data, $server, $item) = @_;

    if ($data) {
        my $tag = lc $data;
        print_list($tag);
    } else {
        ho_print("List is available for the following tags: " .
            lc Irssi::settings_get_str('ho_netmon_network_tags'));
    }
}

# ---------------------------------------------------------------------

sub cmd_netmon_learn {
    my ($data, $srv, $item) = @_;

    if (length $data == 0) {
        ho_print("Please use /NETMON LEARN <tag>.");
        return;
    }

    my $server = Irssi::server_find_tag($data);
    if (!defined $server) {
        ho_print("Not connected to server with tag $data.");
        return;
    }

    ho_print("Learning the servers on network $data.");

    $server->redirect_event('command cmd_netmon', 1, undef, 0, undef,
        {
            'event 364' => 'redir event_links_line_learn',
            'event 365' => 'redir event_links_end_learn',
        }
    );

    # Now send LINKS to obtain a list of all linked servers.
     $server->send_raw_now('LINKS');
}

# ---------------------------------------------------------------------
# Performs a /LINKS for this network tag and inspects if all servers
# are present. This command will not add new servers to the list; it
# will only update the status of the already defined servers.

sub cmd_netmon_check {
    my ($data, $srv, $item) = @_;

    if (length $data == 0) {
        ho_print("Please use /NETMON CHECK <tag>.");
        return;
    }

    my $server = Irssi::server_find_tag($data);
    if (!defined $server) {
        ho_print("Not connected to server with tag $data.");
        return;
    }

    ho_print("Checking the servers on network $data.");
    %checked_servers = ();

    $server->redirect_event('command cmd_netmon', 1, undef, 0, undef,
        {
            'event 364' => 'redir event_links_line_check',
            'event 365' => 'redir event_links_end_check',
        }
    );

    # Now send LINKS to obtain a list of all linked servers.
     $server->send_raw_now('LINKS');
}

# ---------------------------------------------------------------------

sub cmd_netmon_add {
    my ($data, $srv, $item) = @_;

    if ($data =~ /^(\S+)\s+(\S+)\s*$/) {
        my ($tag, $server) = (lc $1, $2);
        if (grep /^$tag$/,
            split / +/, lc Irssi::settings_get_str('ho_netmon_network_tags')
        ) {
            if (exists $status{$tag}->{$server}) {
                ho_print("Server $server already present in tag $tag.");
                return;
            }

            ho_print("Adding server $server to tag $tag.");
            $status{$tag}->{$server} = {
                status      => 'unknown',
                ts          => time,
                full_name   => $server,
                name        => $server,
                split_ts    => undef,
                split_count => 0,
            };
        }
    } else {
        ho_print("Use /NETMON HELP for help.");
    }
}

# ---------------------------------------------------------------------

sub cmd_netmon_remove {
    my ($data, $srv, $item) = @_;

    if ($data =~ /^(\S+)\s+(\S+)\s*$/) {
        my ($tag, $server) = (lc $1, $2);
        if (grep /^$tag$/,
            split / +/, lc Irssi::settings_get_str('ho_netmon_network_tags')
        ) {
            if (!exists $status{$tag}->{$server}) {
                ho_print("No server $server present in tag $tag.");
                return;
            }
            ho_print("Removing server $server from tag $tag.");
            delete $status{$tag}->{$server};
            save_netmon_data();
        }
    } else {
        ho_print("Use /NETMON HELP for help.");
    }
}

# ---------------------------------------------------------------------

sub cmd_netmon_name {
    my ($data, $srv, $item) = @_;

    if ($data =~ /^(\S+)\s+(\S+)\s+(\S+)\s*$/) {
        my ($tag, $server, $name) = (lc $1, $2, $3);
        if (exists $status{$tag}->{$server}) {
            $status{$tag}->{$server}->{name} = $3;
            ho_print("Changed name of server $server to $name.");
            save_netmon_data();
        } else {
            ho_print("No server $server present in tag $tag.");
        }
    } else {
        ho_print("Use /NETMON HELP for help.");
    }
}

# ---------------------------------------------------------------------

sub process_join {
    my ($tag, $server) = @_;

    if (grep /^$tag:$server$/,
        (split / +/, lc Irssi::settings_get_str('ho_netmon_ignore_servers'))
    ) {
        return;
    }

    if (exists $status{$tag}->{$server}) {
        ho_print("[$tag] Rejoin: $server.")
            if Irssi::settings_get_bool('ho_netmon_verbose');
    } else {
        ho_print("[$tag] Join new server: $server.")
            if Irssi::settings_get_bool('ho_netmon_verbose');
        $status{$tag}->{$server}->{name}        = $server;
        $status{$tag}->{$server}->{split_count} = 0;
    }
    $status{$tag}->{$server}->{status} = 'present';
    $status{$tag}->{$server}->{ts} = time;

    Irssi::statusbar_items_redraw('netmon');
}

# ---------------------------------------------------------------------

sub process_split {
    my ($tag, $server) = @_;

    if (grep /^$tag:$server$/,
        (split / +/, lc Irssi::settings_get_str('ho_netmon_ignore_servers'))
    ) {
        return;
    }

    if (exists $status{$tag}->{$server}) {
        ho_print("[$tag] Split: $server.")
            if Irssi::settings_get_bool('ho_netmon_verbose');
    } else {
        ho_print("[$tag] Split new server: $server.")
            if Irssi::settings_get_bool('ho_netmon_verbose');
        $status{$tag}->{$server}->{name} = $server;
    }
    $status{$tag}->{$server}->{status}   = 'missing';
    $status{$tag}->{$server}->{ts}       = time;
    $status{$tag}->{$server}->{split_ts} = time;
    $status{$tag}->{$server}->{split_count}++;

    Irssi::statusbar_items_redraw('netmon');
}

# ---------------------------------------------------------------------

sub print_list {
    my ($tag) = @_;

    if (!exists $status{$tag}) {
        ho_print("No list for tag $tag.");
        return;
    }

    my $now = time;
    ho_print("Server list for tag $tag:");
    for my $server (sort keys %{ $status{$tag} }) {
        my $format = 'ho_netmon_list_line_' .
            $status{$tag}->{$server}->{status};
        my $time = strftime "%Y-%m-%d %H:%M:%S",
            localtime($status{$tag}->{$server}->{ts});
        my ($d, $h, $m, $s) =
            seconds_to_dhms($now - $status{$tag}->{$server}->{ts});
        my $timediff = "$d+$h:$m:$s";
        Irssi::printformat(MSGLEVEL_CRAP, $format,
            $server, $status{$tag}->{$server}->{name},
            $status{$tag}->{$server}->{split_count}, $timediff, $time);
    }
}

# ---------------------------------------------------------------------

sub print_status {
    my ($tag) = @_;

    if (!exists $status{$tag}) {
        ho_print("No status for tag $tag.");
        return;
    }

    my $now = time;
    ho_print("Status report for tag $tag:");
    my @missing;
    for my $server (sort keys %{ $status{$tag} }) {
        if ($status{$tag}->{$server}->{status} eq 'missing') {
            push @missing, $status{$tag}->{$server}->{name};
        }
    }
    if (@missing) {
        ho_print("Missing servers (" . scalar @missing . "/" .
            scalar (keys %{ $status{$tag} }) . "): " . join ' ', @missing);
    } else {
        ho_print("All " . scalar (keys %{ $status{$tag} }).
            " servers are present.");
    }
}

# ---------------------------------------------------------------------

sub event_links_line_learn {
    my ($server, $args, $nick, $address) = @_;
    Irssi::signal_stop();
    my $tag = lc $server->{tag};

    # hoscgaar hub.nl towel.carnique.nl :1 Carnique main hub server
    if ($args =~ /^\S+\s(\S+)\s(\S+) :/) {
        if (!exists $status{$tag}->{$1}) {
            ho_print("Learned new server: $1.")
                if Irssi::settings_get_bool('ho_netmon_verbose');
            $status{$tag}->{$1} = {
                status      => 'present',
                ts          => time,
                full_name   => $1,
                name        => $1,
                split_ts    => undef,
                split_count => 0,
            };
        }
    }
}

# ---------------------------------------------------------------------

sub event_links_end_learn {
    my ($server, $args, $nick, $address) = @_;

    Irssi::signal_stop();
    Irssi::statusbar_items_redraw('netmon');
    ho_print("Done learning.");
    save_netmon_data();
}

# ---------------------------------------------------------------------

sub event_links_line_check {
    my ($server, $args, $nick, $address) = @_;
    Irssi::signal_stop();

    my $tag = lc $server->{tag};

    # hoscgaar hub.nl towel.carnique.nl :1 Carnique main hub server
    if ($args =~ /^\S+\s(\S+)\s(\S+) :/) {
        $checked_servers{$1} = 1;
        if (exists $status{$tag}->{$1}) {
            if ($status{$tag}->{$1}->{status} ne 'present') {
                $status{$tag}->{$1}->{status} = 'present';
                $status{$tag}->{$1}->{ts} = time;
            }
        }
    }
}

# ---------------------------------------------------------------------

sub event_links_end_check {
    my ($server, $args, $nick, $address) = @_;

    my ($present, $missing, $total) = (0, 0, 0);

    my $tag = lc $server->{tag};
    my $now = time;

    # All servers we did not find can be changed from whatever status they
    # currently have to missing.
    for my $server (sort keys %{ $status{$tag} }) {
        if (!$checked_servers{$server} &&
            $status{$tag}->{$server}->{status} ne 'missing'
        ) {
            $status{$tag}->{$server}->{status} = 'missing';
            $status{$tag}->{$server}->{ts}     = $now;
        }
    }


    for my $server (sort keys %{ $status{$tag} }) {
        $present++ if $status{$tag}->{$server}->{status} eq 'present';
        $missing++ if $status{$tag}->{$server}->{status} eq 'missing';
    }
    $total = $present + $missing;

    ho_print("[$tag] Found $present present and $missing missing servers.");
    Irssi::signal_stop();
    Irssi::statusbar_items_redraw('netmon');
}

# ---------------------------------------------------------------------

sub save_netmon_data {
    my $file = Irssi::get_irssi_dir() . '/' . NETMON_FILENAME;

    open F, ">$file"
        or return ho_print_error("Error opening outputfile $file: $!");

    for my $tag (sort keys %status) {
        for my $server (sort keys %{ $status{$tag} }) {
            my $msg = "$tag $server " . $status{$tag}->{$server}->{name};
            print F "$msg\n";
        }
    }

    close F;
    return 1;
}

# ---------------------------------------------------------------------

sub load_netmon_data {
    my $file = Irssi::get_irssi_dir() . '/' . NETMON_FILENAME;
    return unless -f $file;
    open F, $file
        or return ho_print_error("Error opening inputfile $file: $!");

    my @lines = <F>;
    close F;

    %status = ();
    # Each line is like this:
    #    EFNet efnet.demon.co.uk demon
    # Being the tag, complete server name, and short server name.
    my $now = time;
    for my $line (@lines) {
        if ($line =~ /^\s*(\S+)\s+(\S+)\s+(\S+)\s*$/) {
            my $tag = lc $1;
            $status{$tag}->{$2} = {
                full_name => $2,
                name      => $3,
                status    => 'unknown',
                ts        => $now,
                split_ts    => undef,
                split_count => 0,
            };
        }
    }
    return 1;
}

# ---------------------------------------------------------------------

ho_print_init_begin();

# The redirect for LINKS output.
Irssi::Irc::Server::redirect_register('command cmd_netmon', 0, 0,
    {
        'event 364' => 1,
    },
    {
        'event 365' => 1,
    },
    undef
);

Irssi::signal_add_first('server event', 'event_serverevent');

Irssi::signal_add('redir event_links_line_learn', 'event_links_line_learn');
Irssi::signal_add('redir event_links_end_learn',  'event_links_end_learn');

Irssi::signal_add('redir event_links_line_check', 'event_links_line_check');
Irssi::signal_add('redir event_links_end_check',  'event_links_end_check');

Irssi::command_bind('netmon',        'cmd_netmon');
Irssi::command_bind("netmon $_", "cmd_netmon_$_")
    for @subcommands;

Irssi::settings_add_str('ho', 'ho_netmon_network_tags', '');
Irssi::settings_add_int('ho', 'ho_netmon_sb_max_servers', 3);
Irssi::settings_add_str('ho', 'ho_netmon_ignore_servers', '');
Irssi::settings_add_bool('ho', 'ho_netmon_verbose', 1);

Irssi::statusbar_item_register('netmon', '{sb $1-}', 'netmon_sb');

Irssi::theme_register([
    'ho_netmon_line',
    '$[25]0 - $1',

    'ho_netmon_list_line',
    '$[25]0 - $1',

    'ho_netmon_list_line_unknown',
    '$[25]0 - $[20]1 ($[-2]2) $[-12]3',

    'ho_netmon_list_line_present',
    '%G$[25]0%n - $[20]1 ($[-2]2) %g$[-12]3%n',

    'ho_netmon_list_line_missing',
    '%R$[25]0%n - $[20]1 ($[-2]2) %r$[-12]3%n',
]);

load_netmon_data();

{
    my @tags = split / +/, lc Irssi::settings_get_str('ho_netmon_network_tags');
    ho_print("Checking all configured networks...") if @tags;
    for my $tag (@tags) {
        cmd_netmon_check($tag);
    }
}

ho_print_init_end();
ho_print("Use /NETMON HELP for help.");

# ---------------------------------------------------------------------

sub print_syntax {
    ho_print_help('section', 'Syntax');
    ho_print_help('syntax', 'NETMON HELP');
    ho_print_help('syntax', 'NETMON LIST <tag>');
    ho_print_help('syntax', 'NETMON STATUS <tag>');
    ho_print_help('syntax', 'NETMON CHECK <tag>');
    ho_print_help('syntax', 'NETMON LEARN <tag>');
    ho_print_help('syntax', 'NETMON LOAD');
    ho_print_help('syntax', 'NETMON SAVE');
    ho_print_help('syntax', 'NETMON ADD <tag> <server>');
    ho_print_help('syntax', 'NETMON REMOVE <tag> <server>');
    ho_print_help('syntax', 'NETMON NAME <tag> <server> <name>');
}

sub print_help {
    ho_print_help('head', $IRSSI{name});

    print_syntax();

    ho_print_help('section', 'Description');
    ho_print_help("This script monitors the presence of all servers on one ".
        "or more networks. It provides a statusbar item which shows which ".
        "servers, if any, are missing (split).");
    ho_print_help("Each network has a list of servers, and each server has ".
        "a full name and a short name. The short name is what shows up in ".
        "the statusbar item.");
    ho_print_help("Typical usage of this script is as follows. Load, set the ".
        "network tags, do /netmon learn for each of those tags, and add a ".
        "few servers that are missing. Then /statusbar <bar> add netmon, and ".
        "you're all set.");

    ho_print_help('section', 'Commands');
    ho_print_help('command', 'NETMON LIST <tag>',
        'Prints a list of all servers on <tag> and their status.');
    ho_print_help('command', 'NETMON STATUS <tag>',
        'Shows a status report of <tag>.');
    ho_print_help('command', 'NETMON CHECK <tag>',
        'Does a /LINKS and checks which servers are present.');
    ho_print_help('command', 'NETMON LEARN <tag>',
        'Does a /LINKS and learns the servers which are on the network. '.
        'This means the server list for this network is updated.');
    ho_print_help('command', 'NETMON LOAD',
        'Loads the datafile "netmon.data" from disk.');
    ho_print_help('command', 'NETMON SAVE',
        'Saves the server data to "netmon.data".');
    ho_print_help('command', 'NETMON ADD <tag> <server>',
        'Adds server <server> to the list of servers this script knows for '.
        '<tag>.');
    ho_print_help('command', 'NETMON REMOVE <tag> <server>',
        'Removes server <server> from the serverlist of <tag>.');
    ho_print_help('command', 'NETMON NAME <tag> <server> <name>',
        'Sets the short name of <server> in network <tag> to <name>.');

    ho_print_help('section', 'Statusbar item');
    ho_print_help("The statusbar item for this script is called 'netmon'. ".
        "You can add that to an existing statusbar by calling ".
        "'/STATUSBAR <name> add netmon'. Use /STATUSBAR to get a list ".
        "of existing statusbars.\n");

    ho_print_help('section', 'Settings');
    ho_print_help('setting', 'ho_netmon_network_tags',
        'Space separated list of network tags that this script should'.
        'monitor.');
    ho_print_help('setting', 'ho_netmon_ignore_servers',
        'Space separated list of servers that must be ignored. Each server '.
        'is denoted by <tag>:<server>. Example: e:stats.efnet.info');
    ho_print_help('setting', 'ho_netmon_sb_max_servers',
        'If the number of split servers is above this number, the statusbar '.
        'item does not show a list of their names, but only the amount of '.
        'servers missing. You can still use /NETMON STATUS to get the '.
        'list of missing servers.');
    ho_print_help('setting', 'ho_netmon_verbose',
        'Print messages when servers join/split and be more verbose.');
}

# ---------------------------------------------------------------------
