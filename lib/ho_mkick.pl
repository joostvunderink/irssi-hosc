# ho_mkick.pl
#
# $Id: ho_mkick.pl,v 1.6 2004/08/22 20:19:26 jvunder REL_0_1 $
#
# Part of the Hybrid Oper Script Collection.
#
# This provides a /MKICK command to masskick clients from a channel.
#
# TODO:
# * support multiple kicks in 1 line if the ircd supports it.

# ---------------------------------------------------------------------

use strict;
use vars qw($VERSION %IRSSI $SCRIPT_NAME);

use Irssi;
use Irssi::Irc;
use HOSC::again;
use HOSC::again 'HOSC::Base';
use HOSC::again 'HOSC::Tools';
use Getopt::Long;

# ---------------------------------------------------------------------

($VERSION) = '$Revision: 1.6 $' =~ / (\d+\.\d+) /;
%IRSSI = (
    authors    => 'Garion',
    contact    => 'garion@efnet.nl',
    name    => 'ho_mkick.pl',
    description    => 'Masskick command for a channel.',
    license    => 'Public Domain',
    url        => 'http://www.garion.org/irssi/',
    changed    => '25 May 2004 22:53:46',
);
$SCRIPT_NAME = 'Masskick';


# ---------------------------------------------------------------------

sub cmd_mkick {
    my ($cmdline, $server, $chan) = @_;

    if ($cmdline =~ /^help/) {
        return print_help();
    }

    my $args = process_arguments($cmdline);

    if ($args->{help}) {
        return print_help();
    }

    if (!$server) {
        ho_print_error("Please use /MKICK in a window of the server ".
            "you want to masskick on.");
        return;
    }

    if (!defined $args->{channel}) {
        ho_print_error("<channel> argument missing. See /MKICK HELP for help.");
        return;
    }

    my $channel = $server->channel_find($args->{channel});

    if (!defined $channel) {
        ho_print_error("You are not on channel " . $args->{channel} .
            " on this server.");
        return;
    }
    if (!$channel->{ownnick}->{op}) {
        ho_print_error("You are not opped on channel " . $args->{channel} .
            " on this server.");
        return;
    }

    $args->{channel_obj} = $channel;
    $args->{server_obj}  = $server;

    if (!defined $args->{reason}) {
        $args->{reason} = Irssi::settings_get_str('ho_mkick_reason');
    }

    if (defined $args->{hostmask} &&
        $args->{hostmask} =~ /^(?:(.+)!)?(.+)@(.+)$/
    ) {
        $args->{nick} = $1 ? $1 : "*";
        $args->{user} = $2;
        $args->{host} = $3;
    } else {
        ho_print_error("Missing or invalid hostmask. See /MKICK HELP for help.");
        return;
    }

    ho_print('Simulation enabled.') if $args->{simulation};
    ho_print('Masskicking clients matching ' .
        $args->{nick} . "!" .
        $args->{user} . "@" .
        $args->{host} . " in " .
        $args->{channel} . " for reason '" . $args->{reason} . "'.");

    perform_masskick($args);
}


sub perform_masskick {
    my ($args) = @_;
    ho_print("Performing masskick.");

    my $num_kicks = 0;

    for my $client ($args->{channel_obj}->nicks()) {
        my $nick = $client->{nick};
        # Don't kick myself!
        next if $nick eq $args->{server_obj}->{nick};

        my $hostmask = $client->{host};
        if (Irssi::mask_match_address($args->{nick} . '!' .
            $args->{user} . '@' . $args->{host},
            $nick, $hostmask)
        ) {
            if ($client->{op} && !$args->{ops}) {
                ho_print($nick . " is opped. Not kicking.")
                    if $args->{verbose};
                next;
            }
            if ($client->{voice} && !($args->{voices} || $args->{ops})) {
                ho_print($nick . " is voiced. Not kicking.")
                    if $args->{verbose};
                next;
            }
            my $rawcmd = "KICK " . $args->{channel} . " $nick :" . $args->{reason};
            my $cmd = "KICK " . $args->{channel} . " $nick " . $args->{reason};
            my $can_flood = Irssi::settings_get_bool('ho_mkick_can_flood');
            if ($args->{simulation}) {
                ho_print($cmd);
            } else {
                if ($can_flood) {
                    $args->{server_obj}->send_raw_now($rawcmd);
                } else {
                    $args->{server_obj}->command($cmd);
                }
            }
            $num_kicks++;
        }
    }

    ho_print("Done. Kicked $num_kicks client" .
        ($num_kicks == 1 ? '' : 's') . ".");
}


sub process_arguments {
    my ($arguments) = @_;
    my $opt;

    # Removes double spaces in kick reason *shrug*
    local @ARGV = split / +/, $arguments;

    my $res = GetOptions(
        'ops'        => \$opt->{ops},
        'voices'     => \$opt->{voices},
        'sim'        => \$opt->{simulation},
        'simulate'   => \$opt->{simulation},
        'simulation' => \$opt->{simulation},
        'verbose'    => \$opt->{verbose},
    );

    # Get the channel.
    if (@ARGV) {
        $opt->{channel} = shift @ARGV;
    }

    # Get the hostmask.
    if (@ARGV) {
        $opt->{hostmask} = shift @ARGV;
    }

    # Reassemble the reason.
    for my $arg (@ARGV) {
        $opt->{reason} .= $arg . " ";
    }
    $opt->{reason} =~ s/ $// if defined $opt->{reason};

    return $opt;
}

# ---------------------------------------------------------------------

ho_print_init_begin($SCRIPT_NAME);

Irssi::command_bind('mkick', 'cmd_mkick');

Irssi::settings_add_str('ho',  'ho_mkick_reason',    'Plonk!');
Irssi::settings_add_bool('ho', 'ho_mkick_can_flood', 0);

ho_print_init_end($SCRIPT_NAME);
ho_print("Use /MKICK HELP for help.");

# ---------------------------------------------------------------------

sub print_help {
    ho_print_help('head', $SCRIPT_NAME);

    ho_print_help('section', 'Syntax');
    ho_print_help('syntax', 'MKICK [-simulation] [-ops] [-voices] <channel> <[nick!]user@host> [<reason>]');

    ho_print_help('section', 'Description');
    ho_print_help(
    "Masskicks all users in this channel matching the given hostmask. ".
    "By default only non-opped users are kicked, but if ".
    "you specify the -ops flag, ops are killed as well.".
    "Same for voiced users and the -voices flag. The -ops flag overrules ".
    "the -voices flag, so if you want to kick both ops and voices you only ".
    "need to specify -ops."
    );
}

