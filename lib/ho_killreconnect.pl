# ho_killreconnect.pl
# $Id: ho_killreconnect.pl,v 1.6 2004/08/15 08:53:05 jvunder REL_0_1 $
#
# Reconnects if you're killed by an oper.
#
# Part of the Hybrid Oper Script Collection.

use strict;
use vars qw($VERSION %IRSSI $SCRIPT_NAME);

use Irssi;
use HOSC::again;
use HOSC::again 'HOSC::Base';
use HOSC::again 'HOSC::Tools';

$SCRIPT_NAME = 'Killreconnect';
($VERSION) = '$Revision: 1.6 $' =~ / (\d+\.\d+) /;
%IRSSI = (
    authors        => 'Garion',
    contact        => 'garion@irssi.org',
    name        => 'ho_killreconnect',
    description    => 'Reconnects if you are killed by an oper.',
    license        => 'Public Domain',
    url            => 'http://www.garion.org/irssi/hosc/',
    changed        => '04 April 2004 12:34:38',
);

ho_print_init_begin();

Irssi::signal_add('event kill',
    sub {
        my ($server, $reason, $nick, $address) = @_;
        $reason =~ s/^[^:]+://;
        ho_print_warning('[' . $server->{tag} . '] ' .
            "You were killed by $nick [$address] $reason. Reconnecting.");
        Irssi::signal_stop();
    }
);

ho_print("Enabled auto-reconnect when killed by an oper.");
ho_print_init_end();

# Yes, that's all. Explanation:
# <cras> garion: you could probably do that more easily by preventing
#        irssi from seeing the kill signal
# <cras> garion: signal_add('event kill', sub { Irssi::signal_stop(); });
# <cras> garion: to prevent irssi from setting server->no_reconnect = TRUE
