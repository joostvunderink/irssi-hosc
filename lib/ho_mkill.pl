# ho-mkill.pl
#
# $Id: ho_mkill.pl,v 1.8 2004/08/22 20:19:26 jvunder REL_0_1 $
#
# Part of the Hybrid Oper Script Collection.
#
# This provides a /MKILL command.

# ---------------------------------------------------------------------

use strict;
use vars qw(%IRSSI);

use Irssi;
use Irssi::Irc;
use HOSC::again;
use HOSC::again 'HOSC::Base';
use HOSC::again 'HOSC::Tools';
use Getopt::Long;

# ---------------------------------------------------------------------

%IRSSI = HOSC::Base::ho_get_IRSSI(
    name        => 'Mass Kill',
    description => 'Masskill command for a channel.',
);

my $args;
my $who_data;

# ---------------------------------------------------------------------

sub cmd_mkill {
    my ($cmdline, $server, $chan) = @_;

    if ($cmdline =~ /^help/) {
        return print_help();
    }

    $args = process_arguments($cmdline);

    if ($args->{help}) {
        return print_help();
    }

    if (!$server) {
        ho_print_error("Please use /MKILL from a window of the server you want to masskill on.");
        return;
    }

    if (!defined $args->{channel}) {
        ho_print_error("<channel> argument missing. See /MKILL HELP for help.");
        return;
    }

    my $channel = $server->channel_find($args->{channel});

    if (!defined $channel) {
        ho_print_error("You are not on channel " . $args->{channel} .
            " on this server.");
        return;
    }
    $args->{channel_obj} = $channel;
    $args->{server_obj} = $server;

    if (!defined $args->{reason}) {
        $args->{reason} = Irssi::settings_get_str('ho_mkill_reason');
    }

    # If we're going for a takeover, we don't need to send a WHO because
    # we'll kill all other clients anyway.
    if ($args->{takeover}) {
        perform_takeover();
        return;
    }

    if (defined $args->{hostmask} &&
        $args->{hostmask} =~ /^(?:(.+)!)?(.+)@(.+)$/
    ) {
        $args->{nick} = $1 ? $1 : "*";
        $args->{user} = $2;
        $args->{host} = $3;
    } else {
        ho_print_error("Missing or invalid hostmask. See /MKILL HELP for help.");
        return;
    }

    ho_print('Simulation enabled.') if $args->{simulation};
    ho_print('Masskilling clients matching ' .
        $args->{nick} . "!" .
        $args->{user} . "@" .
        $args->{host} . " in " .
        $args->{channel} . " for reason '" . $args->{reason} . "'.");

    # Get rid of all previous WHO data.
    delete $who_data->{$_} for keys %$who_data;

    # Enable the redirects; otherwise we may end up killing opers.
    $server->redirect_event('who', 1, $args->{channel}, 0, undef,
        {
            'event 352' => 'redir event_who_line',
            'event 315' => 'redir event_who_end',
            ''          => 'event empty',
        }
    );
    ho_print("Sending WHO.") if $args->{verbose};
    $server->send_raw_now("WHO " . $args->{channel});
}

# Need to capture who is opered via the output of WHO.
sub event_who_line {
    my ($server, $data, $nick, $address) = @_;
    my @tokens = split / /, $data;
    my $nick = $tokens[5];
    $who_data->{$nick} = {
        user     => $tokens[2],
        host     => $tokens[3],
        server   => $tokens[4],
        userhost => $tokens[2] . '@' . $tokens[3],
    };

    $who_data->{$nick}->{opered} = 1 if $tokens[6] =~ /\*/;
    $who_data->{$nick}->{opped}  = 1 if $tokens[6] =~ /@/;
    Irssi::signal_stop();
}

sub event_who_end {
    Irssi::signal_stop();
    perform_masskill();
}

sub perform_takeover {
    ho_print("Taking over " . $args->{channel});
    # No need for /WHO data, just use internal irssi channel data.
    if ($args->{takeover}) {
        my @nicks = $args->{channel_obj}->nicks();
        for my $nick (@nicks) {
            # Don't kill myself!
            next if $nick->{nick} eq $args->{server_obj}->{nick};
            my $cmd = "KILL " . $nick->{nick} . " :" . $args->{reason};
            if ($args->{simulation}) {
                ho_print($cmd);
            } else {
                $args->{server_obj}->send_raw_now($cmd);
            }
        }
        ho_print("Killed " . (scalar @nicks - 1) . " clients.");
        if ($args->{simulation}) {
            ho_print("PART " . $args->{channel});
            ho_print("JOIN " . $args->{channel});
        } else {
            $args->{server_obj}->send_raw_now("PART " . $args->{channel});
            $args->{server_obj}->send_raw_now("JOIN " . $args->{channel});
        }
        ho_print("Channel takeover of " . $args->{channel} . " complete.");
        return;
    }
}

sub perform_masskill {
    ho_print("Performing masskill.");
    my $num_kills = 0;
    # Normal masskill. Uses WHO #channel data.
    for my $nick (keys %$who_data) {
        # Don't kill myself!
        next if $nick eq $args->{server_obj}->{nick};

        my $hostmask = $who_data->{$nick}->{userhost};
        if (Irssi::mask_match_address($args->{nick} . '!' .
            $args->{user} . '@' . $args->{host},
            $nick, $hostmask)
        ) {
            if ($who_data->{$nick}->{opped} && !$args->{ops}) {
                ho_print($nick . " is opped. Not killing.")
                    if $args->{verbose};
                next;
            }
            if ($who_data->{$nick}->{opered} && !$args->{opers}) {
                ho_print($nick . " is an oper. Not killing.")
                    if $args->{verbose};
                next;
            }
            my $cmd = "KILL $nick :" . $args->{reason};
            if ($args->{simulation}) {
                ho_print($cmd);
            } else {
                $args->{server_obj}->send_raw_now($cmd);
            }
            $num_kills++;
        }
    }

    delete $who_data->{$_} for keys %$who_data;

    ho_print("Done. Killed $num_kills client" .
        ($num_kills == 1 ? '' : 's') . ".");
}


sub process_arguments {
    my ($arguments) = @_;
    my $opt;

    local @ARGV = split / /, $arguments;

    my $res = GetOptions(
        'ops'        => \$opt->{ops},
        'opers'      => \$opt->{opers},
        'takeover'   => \$opt->{takeover},
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

ho_print_init_begin();

Irssi::command_bind('mkill', 'cmd_mkill');
Irssi::settings_add_str('ho', 'ho_mkill_reason', 'Plonk!');

Irssi::signal_add({ 'redir event_who_line' => \&event_who_line });
Irssi::signal_add({ 'redir event_who_end'  => \&event_who_end });

ho_print_init_end();
ho_print("Use /MKILL HELP for help.");

# ---------------------------------------------------------------------

sub print_help {
    ho_print_help('head', $IRSSI{name});

    ho_print_help('section', 'Syntax');
    ho_print_help('syntax', 'MKILL [-simulation] [-ops] [-opers] <channel> <[nick!]user@host> [<reason>]');
    ho_print_help('syntax', 'MKILL [-simulation] -takeover <channel>');

    ho_print_help('section', 'Description');
    ho_print_help(
    "Mass kills all users in this channel matching the given hostmask. ".
    "By default only non-opped users are killed, but if ".
    "you specify the -ops flag, ops are killed as well.".
    "Opers are NOT killed by this command. BE CAREFUL if you want ".
    "to MKILL *\@*; make sure you do a /WHO first because the internal ".
    "status list might not be up to date with the actual status.\n"
    );
}

