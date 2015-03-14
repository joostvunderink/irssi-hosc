# TODO
# - Add logging of G-lines to file.
# - Add supporting based on the nick!user@host mask of the G-line requester

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
    name         => 'G-Line',
    description  => 'Makes supporting G-lines on EFnet-like servers easier.',
);

# Hashref of G-lines. Contains $index => { details } pairs.
my $glines;

# ---------------------------------------------------------------------
# A Server Event has occurred. Check if it is a server GLINE NOTICE;
# if so, process it.

sub event_serverevent {
    my ($server, $msg, $nick, $hostmask) = @_;

    return if $msg !~ /^NOTICE/;

    # If the hostmask is set, it is not a server NOTICE, so we'll ignore it
    # as well.
    # TODO: we need to check if the source is indeed OUR server. Problems
    # appeared when getting a notice from another server.
    return if (defined $hostmask) && length($hostmask) > 0;

    my $ownnick = $server->{nick};

    # G-line request: opernick, operuser, operhost, server, mask, reason
    if ($msg =~ /(\S+)!([^@]+)@(\S+) on (\S+) is requesting gline for \[(\S+)\] \[(.+)\]/) {
        clean_glines();
        process_gline_request(
            server_obj  => $server,
            server_tag  => $server->{tag},
            nick        => $1,
            user        => $2,
            host        => $3,
            server      => $4,
            glinemask   => $5,
            glinereason => $6,
        );
        Irssi::signal_stop()
            if Irssi::settings_get_bool('ho_gline_suppress_server_notices');
    }

    # G-line trigger: opernick, operuser, operhost, server, mask, reason
    if ($msg =~ /(\S+)!(\S+)@(\S+) on (\S+) (?:(?:has triggered)|(?:added)) gline for \[(\S+)\] \[(.+)\]/) {
        process_gline_trigger(
            server_obj  => $server,
            server_tag  => $server->{tag},
            nick        => $1,
            user        => $2,
            host        => $3,
            server      => $4,
            glinemask   => $5,
            glinereason => $6,
        );
        clean_glines();
        Irssi::signal_stop()
            if Irssi::settings_get_bool('ho_gline_suppress_server_notices');
    }

    # Already voted
    if ($msg =~ /(serv|op)er or (op|serv)er has already voted/) {
        process_already_voted(
            server_obj  => $server,
            server_tag  => $server->{tag},
        );
        clean_glines();
        Irssi::signal_stop()
            if Irssi::settings_get_bool('ho_gline_suppress_server_notices');
    }
}

# ---------------------------------------------------------------------
# G-line request: opernick, operuser, operhost, server, mask, reason

sub process_gline_request {
    my %args = @_;
    my $index;

    my $tag = lc $args{server_tag};
    my @allowed_tags =
        split / +/, lc Irssi::settings_get_str('ho_gline_network_tags');
    return unless grep /^$tag$/, @allowed_tags;

    my $owin_name = Irssi::settings_get_str('ho_gline_output_window');
    my $owin = Irssi::window_find_name($owin_name);

    $index = find_gline($tag, $args{glinemask});
    if ($index == -1) {
        # A new G-line. Create it.
        $index = gline_add(%args);
        if ($owin) {
            $owin->printformat(MSGLEVEL_CRAP, 'ho_gline_request', $index,
                $tag, $args{nick}, $args{user}, $args{host}, $args{server},
                $args{glinemask}, $args{glinereason});
        } else {
            Irssi::printformat(MSGLEVEL_CRAP, 'ho_gline_request', $index,
                $tag, $args{nick}, $args{user}, $args{host}, $args{server},
                $args{glinemask}, $args{glinereason});
        }
    } else {
        # Existing G-line supported.
        gline_support(%args);
        if ($owin) {
            $owin->printformat(MSGLEVEL_CRAP, 'ho_gline_support', $index,
                $tag, $args{nick}, $args{user}, $args{host}, $args{server});
        } else {
            Irssi::printformat(MSGLEVEL_CRAP, 'ho_gline_support', $index,
                $tag, $args{nick}, $args{user}, $args{host}, $args{server});
        }
    }
    Irssi::signal_stop()
        if Irssi::settings_get_bool('ho_gline_suppress_server_notices');
}

# ---------------------------------------------------------------------
# G-line trigger: opernick, operuser, operhost, server, mask, reason

sub process_gline_trigger {
    my %args = @_;

    my $tag = lc $args{server_obj}->{tag};
    my @allowed_tags =
        split / +/, lc Irssi::settings_get_str('ho_gline_network_tags');
    return unless grep /^$tag$/, @allowed_tags;

    my $owin_name = Irssi::settings_get_str('ho_gline_output_window');
    my $owin = Irssi::window_find_name($owin_name);

    my $index = find_gline($tag, $args{glinemask});
    if ($index == -1) {
        ho_print('Ignoring G-line trigger for unknown G-line on '.
            $args{glinemask});
    } else {
        if ($owin) {
            $owin->printformat(MSGLEVEL_CRAP, 'ho_gline_trigger', $index,
                $tag, $args{nick}, $args{user}, $args{host}, $args{server});
        } else {
            Irssi::printformat(MSGLEVEL_CRAP, 'ho_gline_trigger', $index,
                $tag, $args{nick}, $args{user}, $args{host}, $args{server});
        }
        $glines->{$index}->{triggered} = 1;
    }
    Irssi::signal_stop()
        if Irssi::settings_get_bool('ho_gline_suppress_server_notices');
}

# ---------------------------------------------------------------------

sub process_already_voted {
    my %args = @_;

    my $tag = lc $args{server_obj}->{tag};
    my @allowed_tags =
        split / +/, lc Irssi::settings_get_str('ho_gline_network_tags');
    return unless grep $tag, @allowed_tags;

    my $index = find_gline($tag, $args{glinemask});
    if ($index == -1) {
        # Ignoring already voted on non-present G-line
    } else {
        $glines->{$index}->{alreadyvoted}++;
    }
    Irssi::signal_stop()
        if Irssi::settings_get_bool('ho_gline_suppress_server_notices');
}

# ---------------------------------------------------------------------
# Adds a G-line to the list of pending G-lines.
# If succesful addition, the location of this new G-line is returned.
# If already present, -1 is returned.

sub gline_add {
    my %args = @_;
    my $tag = $args{server_obj}->{tag};

    # Test if this G-line is already present. If so, return -1.
    my $index = find_gline($tag, $args{glinemask});

    if ($index != -1) {
        return -1;
    }

    $index = get_new_index($tag);

    my $gline = {
        tag          => $tag,
        index        => $index,
        mask         => $args{glinemask},
        reason       => $args{glinereason},
        support      => 0,
        triggered    => 0,
        opernick     => $args{nick},
        operuser     => $args{user},
        operhost     => $args{host},
        operserver   => $args{server},
        votedopers   => $args{nick},
        votedservers => $args{server},
        voted        => 0,
        alreadyvoted => 0,
        time         => time(),
    };

    if ($args{server} eq $args{server_obj}->{real_address}) {
        ho_print("GLINE $tag:$index requested by our server.")
            if Irssi::settings_get_bool('ho_gline_verbose');
        $gline->{voted} = 1;
    }
    $glines->{$index} = $gline;

    return $index;
}

# ---------------------------------------------------------------------

sub gline_support {
    my %args = @_;
    my $tag = $args{server_obj}->{tag};
    my $index = find_gline($tag, $args{glinemask});

    return if $index == -1;

    $glines->{$index}->{support}++;

    if ($args{server} eq $args{server_obj}->{real_address}) {
        ho_print("GLINE $index supported by our server.")
            if Irssi::settings_get_bool('ho_gline_verbose');
        $glines->{$index}->{voted} = 1;
    }
}

# ---------------------------------------------------------------------
# Searches the @glines array for a G-line matching $host. If found, the
# position in the array is returned. Otherwise, -1 is returned.

sub find_gline {
    my ($tag, $mask) = @_;

    for my $index (keys %$glines) {
        return $index
            if $glines->{$index}->{mask} eq $mask &&
               lc $glines->{$index}->{tag} eq lc $tag;
    }

    return -1;
}

# ---------------------------------------------------------------------
# Returns the highest index that's being used for this tag, plus one.

sub get_new_index {
    my ($tag) = @_;

    my @keys = sort { $a <=> $b } keys %$glines;

    if (!@keys) {
        @keys = (0);
    }

    return (pop @keys) + 1;
}

# ---------------------------------------------------------------------
# Removes all Glines that have expired.

sub clean_glines {
    my $ptime = Irssi::settings_get_int('ho_gline_pending_remove_time');
    my $ttime = Irssi::settings_get_int('ho_gline_triggered_remove_time');
    my $now = time();

    for my $index (keys %$glines) {
        if (( $glines->{$index}->{triggered} &&
              $now > $glines->{$index}->{time} + $ttime) ||
            $now > $glines->{$index}->{time} + $ptime
        ) {
            delete $glines->{$index};
        }
    }
}

# ---------------------------------------------------------------------
# /gline
# need:
# - show the list
# - support a gline
# - support multiple glines
# - support all glines
# - request new gline

sub cmd_gline {
    my ($args, $server, $item) = @_;

    clean_glines();
    if ($args =~ m/^(help)|(status)/i ) {
        Irssi::command_runsub ('gline', $args, $server, $item);
        return;
    }

    if (length $args == 0) {
        print_usage();
    } elsif ($args =~ /^[0-9\s]+$/) {
        my @indices = split /\s+/, $args;
        cmd_gline_support_index($server, $item, @indices);
    } elsif ($args =~ /^([0-9]+)-([0-9]+)$/) {
        my @indices = ($1..$2);
        ho_print("Supporting G-lines $1 - $2.");
        cmd_gline_support_index($server, $item, @indices);
    } elsif ($args =~ /^\s*all\s+(\S+)\s*$/i) {
        ho_print("Supporting all pending G-lines for tag $1.");
        cmd_gline_support_all($server, $item, $1);
    } elsif ($args =~ /^\s*all\s*$/i) {
        ho_print("Supporting all pending G-lines.");
        cmd_gline_support_all($server, $item, undef);
    } elsif ($args =~ /^([^@]+@\S+)\s+(.+)$/) {
        cmd_gline_place($server, $item, $1, $2);
    }
}

# ---------------------------------------------------------------------

sub cmd_gline_help {
    print_help();
}

# ---------------------------------------------------------------------

sub cmd_gline_status {
    clean_glines();
    print_status();
}

# ---------------------------------------------------------------------
# Prints the status info on current G-lines.

sub print_status {
    my ($data, $server, $item) = @_;

    my $num_glines = 0;
    for my $index (keys %$glines) {
        $num_glines++ unless $glines->{$index}->{triggered};
    }

    if ($num_glines == 0) {
        ho_print("No pending G-lines.");
        return;
    }

    if ($num_glines == 1) {
        ho_print("There is 1 pending G-line:");
    } else {
        ho_print("There are $num_glines pending G-lines:");
    }

    for my $index (sort { $a <=> $b } keys %$glines) {
        print_gline_details($glines->{$index});
    }
}

# ---------------------------------------------------------------------

sub print_gline_details {
    my ($gline) = @_;
    return if $gline->{triggered};

    Irssi::printformat(MSGLEVEL_CRAP, 'ho_gline_details',
        $gline->{index}, $gline->{tag},
        $gline->{opernick}, $gline->{operuser},
        $gline->{operhost}, $gline->{operserver},
        $gline->{mask}, $gline->{reason},
        (time() - $gline->{time}));

    ho_print("  supported by us.") if $gline->{voted};
}

# ---------------------------------------------------------------------

sub cmd_gline_place {
    my ($server, $item, $hostmask, $reason) = @_;

    if (!$server) {
        ho_print("Please use the GLINE command in a window with a ".
            "server connection.");
        return;
    }

    ho_print("Requesting G-line [" . $server->{tag} . "] on $hostmask " .
        "($reason).");
    $server->send_raw_now("GLINE $hostmask :$reason");
}

# ---------------------------------------------------------------------
# /gline <num>

sub cmd_gline_support_index {
    my ($server, $item, @indices) = @_;

    for my $index (@indices) {
        gline_support_index($index);
    }
}

# ---------------------------------------------------------------------
# Tries to support all G-lines. Network tag is optional. If the network
# tag is not given, this function will only work if it has been enabled
# for exactly one network tag.

sub cmd_gline_support_all {
    my ($server, $item, $support_tag) = @_;

    my @tags = split / +/, lc Irssi::settings_get_str('ho_gline_network_tags');
    if (@tags == 0) {
        ho_print("No tags set. Not supporting any G-lines.");
        return;
    }

    if (keys %$glines == 0) {
        ho_print("No pending G-lines.");
        return;
    }

    if (@tags > 1) {
        if (defined $support_tag && !grep /^$support_tag$/i, @tags) {
            ho_print("Script not enabled for tag $support_tag.");
            return;
        }

        my %pending_tags;
        for my $index (keys %$glines) {
            $pending_tags{ $glines->{$index}->{tag} } = 1;
        }
        my $num_tags = keys %pending_tags;
        if (!defined $support_tag && $num_tags > 1) {
            ho_print("There are pending G-lines for $num_tags network tags. " .
                "Please specify the tag with /gline all <tag>.");
            return;
        } else {
            $support_tag = (keys %pending_tags)[0];
        }
    } else {
        if (defined $support_tag) {
            if ($support_tag ne $tags[0]) {
                ho_print("Script not enabled for tag $support_tag.");
                return;
            }
        } else {
            $support_tag = $tags[0];
        }
    }

    my @indices;
    for my $index (sort { $a <=> $b } keys %$glines) {
        push @indices, $index
            if lc $glines->{$index}->{tag} eq lc $support_tag;
    }
    if (@indices) {
        ho_print("Supporting all G-lines (" . scalar @indices . ") for ".
            $support_tag . ".");
        cmd_gline_support_index($server, $item, @indices);
    } else {
        ho_print("No pending G-lines for $support_tag.");
    }
}


sub gline_support_index {
    my ($data) = @_;

    unless (defined $glines->{$data}) {
        ho_print_error("No such G-line $data.");
        return;
    }

    if ($glines->{$data}->{voted}) {
        ho_print("We have already voted on G-line $data.");
        return;
    }

    my $mask = $glines->{$data}->{mask};
    if (length $mask == 0) {
        ho_print_error("G-line mask of $data is empty!");
        return;
    }

    my $reason = $glines->{$data}->{reason};
    if (length $reason == 0) {
        ho_print_error("G-line reason of $data is empty!");
        return;
    }

    my $gserver = Irssi::server_find_tag($glines->{$data}->{tag});
    unless (defined $gserver) {
        ho_print_error("No server found with tag " . $glines->{$data}->{tag} .
            "for G-line $data.");
        return;
    }

    # Issue the support
    ho_print("Supporting G-line $data.")
        if Irssi::settings_get_bool('ho_gline_verbose');
    $gserver->send_raw_now("GLINE $mask :$reason");
}

# ---------------------------------------------------------------------

ho_print_init_begin();

Irssi::signal_add_first('server event', 'event_serverevent');

Irssi::command_bind('gline',        'cmd_gline');
Irssi::command_bind('gline help',   'cmd_gline_help');
Irssi::command_bind('gline status', 'cmd_gline_status');

Irssi::settings_add_bool('ho', 'ho_gline_suppress_server_notices', 0);
Irssi::settings_add_int('ho',  'ho_gline_pending_remove_time', 3600);
Irssi::settings_add_int('ho',  'ho_gline_triggered_remove_time', 300);

Irssi::settings_add_str('ho', 'ho_gline_network_tags', '');
Irssi::settings_add_bool('ho', 'ho_gline_verbose', 0);

Irssi::settings_add_str('ho', 'ho_gline_output_window', '');

Irssi::theme_register([
    # num, tag, nick, user, host, server, mask, reason
    'ho_gline_request',
    '%Cho%n %CGREQ%n %Y$0%n %c$1%n %_$2%_ ($3@$4) [$5] %_$6%_ $7',

    # num, tag, nick, user, host, server
    'ho_gline_support',
    '%Cho%n %cGSUP%n %Y$0%n %c$1%n $2 ($3@$4) [$5]',

    # num, tag, nick, user, host, server
    'ho_gline_trigger',
    '%Cho%n %CGTRG%n %Y$0%n %c$1%n $2 ($3@$4) [$5]',

    # num, tag, nick, user, host, server, mask, reason, secs_ago
    'ho_gline_details',
    '%Cho%n %cPEND%n %Y$0%n %c$1%n [$8 secs ago] %_$2%_ ($3@$4) [$5] %_$6%_ $7',
]);

ho_print_init_end();
ho_print("Use /GLINE for help.");
if (length Irssi::settings_get_str('ho_gline_network_tags') == 0) {
    ho_print('You have no networks set for this script. Please set them '.
        'via the ho_gline_network_tags setting, or see /GLINE HELP for help.');
}
my $owin_name = Irssi::settings_get_str('ho_gline_output_window');
my $owin = Irssi::window_find_name($owin_name);
if (defined $owin) {
    ho_print("Sending GLINE messages to window '$owin_name'.");
} else {
    ho_print_warning("Window named '$owin_name' not found. Not sending " .
        "GLINE mesages there.");
}
# ---------------------------------------------------------------------

sub print_help {
    ho_print_help('head', $IRSSI{name});

    ho_print_help('section', 'Syntax');
    print_usage();

    ho_print_help('section', 'Description');
    ho_print_help('This script makes it easier to support G-lines, both ' .
        'single ones and multiple at the same time.');
    ho_print_help('Each G-line that is requested is stored under a '.
        'unique identifier, an integer number. The standard way to support '.
        'that G-line is to call /GLINE with as only argument the number '.
        'of the G-line.');
    ho_print_help('As soon as a G-line is triggered, it is removed from ' .
        'the pending G-line list.');
    ho_print_help('To support multiple G-lines, you can use one of the ' .
        'following commands:');
    ho_print_help('/GLINE 1 4 5     - supports G-lines 1, 4 and 5.');
    ho_print_help('/GLINE 2-6       - supports all G-lines from 2 to 6.');
    ho_print_help('/GLINE ALL efnet - supports all G-lines of tag "efnet".');
    ho_print_help(' ');

    ho_print_help('section', 'Settings');
    ho_print_help('setting', 'ho_gline_network_tags',
        'A space separated list of network tags that this script should '.
        'facilitate G-lines on.');
    ho_print_help('setting', 'ho_gline_output_window',
        'The name of the output window of the request and trigger messages.');
}

sub print_usage {
    ho_print_help('syntax', '/GLINE help');
    ho_print_help('syntax', '/GLINE status');
    ho_print_help('syntax', '/GLINE <index> [<index> ...]');
    ho_print_help('syntax', '/GLINE <firstindex>-<lastindex>');
    ho_print_help('syntax', '/GLINE <user@host> <reason>');
}

# ---------------------------------------------------------------------

