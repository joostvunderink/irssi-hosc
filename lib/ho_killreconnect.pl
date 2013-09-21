use strict;
use warnings;
use vars qw(%IRSSI);

use Irssi;
use HOSC::again;
use HOSC::again 'HOSC::Base';
use HOSC::again 'HOSC::Tools';

%IRSSI = HOSC::Base::ho_get_IRSSI(
    name        => 'Killreconnect',
    description => 'Reconnects if you are killed by an oper.',
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
