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
    authors     => "Daniel 'dubkat' Reidy",
    contact     => 'dubkat@gmail.com',
    url         => 'http://sigterm.us',
    name        => 'stats c',
    description => 'Reformats stats c',
);

# shamelessly ripped from ho_stats_p.pl by Garion
#-----------------------------------------------------------------------

my %server_flags = (
    A => 'autoconnect',
    S => 'ssl',
    T => 'topicburst',
    Z => 'ziplinks',
);

my %stats_c_data;

sub event_stats_c_line {
    my ($server, $data, $servername) = @_;

    my %server_data;
    # C *@127.0.0.1 TZ ircd.mednor.net 6667 server
    if ($data =~ /c (\S+) (\S+) (\S+) (\d+)/i) {
        $server_data{mask}    = $1;
        $server_data{flags}   = $2;
        $server_data{server}  = $3;
        $server_data{port}    = $4;
        $stats_c_data{ $server_data{server} } = \%server_data;
        Irssi::signal_stop();
    }
}

sub event_stats_c_end {
    my ($server, $data, $servername) = @_;
    return unless $data =~ /c :End of \/STATS report/i;
    Irssi::signal_stop();
    print_stats_c_data($servername);
    undef %stats_c_data;
}

sub print_stats_c_data {
    my ($servername) = @_;

    Irssi::printformat(MSGLEVEL_CRAP, 'ho_stats_c_begin_report', $servername);
    for my $server_data (sort keys %stats_c_data) {
        my $long_flags = '';
        for my $char (split //, $stats_c_data{$server_data}->{'flags'}) {
            $long_flags .= $server_flags{$char} . " " unless (!defined $server_flags{$char});
        }
        Irssi::printformat(MSGLEVEL_CRAP, 'ho_stats_c_line',
            $stats_c_data{$server_data}->{'server'},
            $stats_c_data{$server_data}->{'port'},
            $long_flags,
            $stats_c_data{$server_data}->{'mask'},
        );
    }
}

ho_print_init_begin();

Irssi::signal_add_first("event 213", "event_stats_c_line");
Irssi::signal_add_last("event 219", "event_stats_c_end");

Irssi::theme_register( [
    'ho_stats_c_begin_report',
    '%YSTATS c report%n of %_$0%_',

    'ho_stats_c_line',
    '* %_$[20]0%_ $[-4]1 $2',
]);

ho_print_init_end();

