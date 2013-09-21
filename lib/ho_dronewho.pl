# ho_tfind.pl
# $Id$
#

use strict;
use vars qw($VERSION %IRSSI $SCRIPT_NAME);

use Irssi;
use HOSC::again;
use HOSC::again 'HOSC::Base';
use HOSC::again 'HOSC::Tools';
use POSIX;

$SCRIPT_NAME = "Dronewho";
($VERSION) = '$Revision: 1.16 $' =~ / (\d+\.\d+) /;
%IRSSI = (
    authors        => 'Garion',
    contact        => 'garion@irssi.org',
    name           => 'ho_dronewho',
    description    => 'Logs /WHO #channel x to file.',
    license        => 'Public Domain',
    url            => 'http://www.garion.org/irssi/hosc/',
    changed        => '04 April 2004 12:34:38',
);

my ($stats, $args, $outputdir, $channel, $searchargs);

# - execmode -> 'cmd' || 'msg'
# - nick     -> in case of msg
my %params;
my @found_clients; # Storage place for found clients in case of sorting

# ---------------------------------------------------------------------
# /DRONEWHO

sub cmd_dronewho {
    my ($arguments, $server, $item) = @_;

    if ($arguments =~ /^help/i) {
        Irssi::command_runsub ('dronewho', 'help', $server, $item);
        return;
    }

    if (length $arguments == 0) {
        return print_usage();
    }

    my $chan = $arguments;
    $chan =~ s/^\s+//;
    $chan =~ s/\s+$//;

    if (!$server) {
        return ho_print_error("No server in this window.");
    }

    if ($server->{version} !~ /^u2/) {
        return ho_print_error("No ircu server in this window.");
    }

    if ($stats->{busy}) {
        ho_print_error("Sorry, already performing a DRONEWHO. Please wait.");
        return;
    }

    my $odir = Irssi::settings_get_str('ho_dronewho_output_dir');
    if (length $odir == 0) {
        ho_print("Please set the output dir in setting ".
            "ho_dronewho_output_dir.");
        return;
    }
    if (!-d $odir) {
        return ho_print_error("Outputdir $odir does not exist.");
    }

    $params{'execmode'} = 'cmd';
    do_dronewho($server, $chan);
}

sub event_public {
    my ($server, $data, $nick, $mask, $channel) = @_;

    my $ownnick = $server->{'nick'};

    return unless $data =~ /$ownnick:/;

    my @allowed_masks = split / +/,
        Irssi::settings_get_str('ho_dronewho_allowed_hostmasks');

    my $allowed = 0;
    for my $allowed_hostmask (@allowed_masks) {
        if (Irssi::mask_match_address("*!".$allowed_hostmask, "a",$mask)) {
            $allowed = 1;
        }
    }

    # Ignore siletnly if not allowed.
    return unless $allowed;

    if ($data =~ /$ownnick:\s+whox\s+(\S+)\s+(\S+)\s+(.+)/) {
        $server->command("msg $channel $nick: Performing whox on $1 ".
            "(type: $2); comment $3");
        $params{'execmode'} = 'msg';
        $params{'channel'}  = $channel;
        $params{'nick'}     = $nick;
        do_dronewho($server, $1);
    } elsif ($data =~ /$ownnick:\s+whox/) {
        $server->command("msg $channel $nick: Please use this syntax: ".
            "WHOX <channel|realname> <type> <comment>");
        $server->command("msg $channel The channel, realname and type ".
            "must be one word; the comment can be multiple words.");
        $server->command("msg $channel Example 1: whox ##centralplexus ".
            "drone_type These drones are uncleanable.");
        $server->command("msg $channel Example 2: whox aol.com ".
            "another_tye sprinkler knows which type these are.");
    }
}

sub do_dronewho {
    my ($server, $chan) = @_;

    # Set the global vars.
    my $odir = Irssi::settings_get_str('ho_dronewho_output_dir');
    $outputdir = $odir;
    $channel = undef;
    $searchargs = undef;
    if ($chan =~ /^#/) {
        $channel = $chan;
    } else {
        $searchargs = $chan;
    }
    ho_print("Logging WHO $chan to $outputdir");

        #'command cmd_dronewho', 0, '', (split(/\s+/, $arguments) > 2), undef, {
    $server->redirect_event(
        'command cmd_dronewho', 0, '', 0, undef, {
                "event 354", "redir dronewho_event_who_line",
                "event 315", "redir dronewho_event_who_end",
        }
    );

    $stats->{busy} = 1;
    @found_clients = ();
    if ($channel) {
        my $raw_cmd = "WHO $channel x%nuhirf";
        ho_print("Raw command: $raw_cmd");
        $server->send_raw($raw_cmd);
    } else {
        my $raw_cmd = "WHO $searchargs rx%nuhirf";
        ho_print("Raw command: $raw_cmd");
        $server->send_raw($raw_cmd);
    }
}

# ---------------------------------------------------------------------

sub cmd_dronewho_help {
    my ($arguments, $server, $item) = @_;
    print_help();
}

# ---------------------------------------------------------------------
# Catching and processing output of the ircd.

sub event_who_line {
    my ($server, $data, $nick, $address) = @_;
    my ($ownnick, $line) = $data =~ /^(\S*)\s+(.*)$/;

    my $details = get_who_line_details($line);
    push @found_clients, $details if defined $details;
    #use Data::Dumper; print Dumper $details;
}

# ---------------------------------------------------------------------
# Processes a single /TRACE output line and returns a hashref with the
# relevant data.

sub get_who_line_details {
    my ($line) = @_;

    my $details;

    # username ip host nick mode :realname
    if ($line =~ /^(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+) :(.+)$/) {
        return undef if $2 eq "0.0.0.0";
        $details->{nick}    = $4;
        $details->{user}    = $1;
        $details->{host}    = $3;
        $details->{ip}      = $2;
        $details->{mode}    = $5;
        $details->{gecos}   = $6;
        return $details;
    }

    return $details;
}

# ---------------------------------------------------------------------

sub event_who_end {
    my ($server, $data, $nick, $address) = @_;

    who_end();

    if ($params{'execmode'} eq 'cmd') {
        ho_print(scalar @found_clients . " clients found. Log written.");
    } else {
        $server->command("msg " . $params{'channel'} . " " .
            $params{'nick'} . ": " . scalar @found_clients .
            " clients found. Log written.");
    }
}

# ---------------------------------------------------------------------

sub who_end {
    $stats->{busy} = 0;

    my $day = strftime "%Y%m%d", localtime;
    my $outputfile = $channel ? "${day}_$channel.log" : "${day}_$searchargs.log";
    open F, ">$outputdir/$outputfile"
        or return ho_print_error("Could not open $outputdir/$outputfile: $!");

    my $now = strftime "%Y-%m-%d %H:%M:%S", localtime;
    print F "# Network   : Undernet\n";
    print F "# Channel   : $channel\n" if $channel;
    print F "# SearchArgs: $searchargs\n" if $searchargs;
    print F "# Timezone  : " .
        Irssi::settings_get_str("ho_dronewho_timezone") . "\n";
    print F "# Time      : $now\n";
    print F "# Drone type: \n";
    print F "# \n";

    print F "# Channel ops:\n" if $channel;
    for my $client (@found_clients) {
        next unless $channel && $client->{mode} =~ /@/;
        my $msg = sprintf "%s %s%s %12s (%10s@%s) %s",
            $now,
            $client->{ip}, ' ' x (15 - length $client->{ip}),
            $client->{nick}, $client->{user},
            $client->{host}, $client->{gecos};
        print F "$msg\n";
    }

    print F "#\n# Other clients:\n" if $channel;
    for my $client (@found_clients) {
        next if $channel && $client->{mode} =~ /@/;
        my $msg = sprintf "%s %s%s %12s (%10s@%s) %s",
            $now,
            $client->{ip}, ' ' x (15 - length $client->{ip}),
            $client->{nick}, $client->{user},
            $client->{host}, $client->{gecos};
        print F "$msg\n";
    }

    close F;
}

# ---------------------------------------------------------------------
# Initialisation

ho_print_init_begin();

Irssi::settings_add_str('ho',  'ho_dronewho_output_dir', '');
Irssi::settings_add_str('ho',  'ho_dronewho_timezone', 'GMT');
Irssi::settings_add_str('ho',  'ho_dronewho_allowed_hostmasks', '');

Irssi::command_bind('dronewho',       'cmd_dronewho');
Irssi::command_bind('dronewho help',  'cmd_dronewho_help');

Irssi::signal_add({
    "redir dronewho_event_who_line"       => \&event_who_line,
    "redir dronewho_event_who_end"        => \&event_who_end,
});

Irssi::signal_add_last('message public',   'event_public');


# ok this is IMO realy ugly, if anyone has a suggestion please let me know
Irssi::Irc::Server::redirect_register("command cmd_dronewho", 0, 0,
    {
        "event 354" => 1,  # who line
    },
    {
        "event 315" => 1,  # end of who
    },
    undef,
);

# Register format.
# nick, user, host, gecos, ip

ho_print_init_end();

# ---------------------------------------------------------------------
# Help.

sub print_usage {
}

sub print_help {
}

