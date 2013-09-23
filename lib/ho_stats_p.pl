use strict;
use warnings;
use vars qw(%IRSSI);

use Irssi;
use Irssi::Irc;
use Irssi::HOSC::again;
use Irssi::HOSC::again 'Irssi::HOSC::Base';
use Irssi::HOSC::again 'Irssi::HOSC::Tools';
import Irssi::HOSC::Tools qw(seconds_to_hms);

# ---------------------------------------------------------------------

%IRSSI = Irssi::HOSC::Base::ho_get_IRSSI(
    name        => 'ho_stats_p',
    description => 'Reformats stats p',
);

my %stats_p_data;
my @stats_p_idletimes;
my ($stats_p_num_tcm, $stats_p_num_bopm, $stats_p_num_ddd);


# ---------------------------------------------------------------------
# Adds this oper to the stats p data hash.

sub event_stats_p_line {
    my ($server, $data, $servername) = @_;

    my %oper;

    if ($data =~ /\[([OoAa])\](\[.*\])? (.+) \((.+)\) [Ii]dle:? ([0-9]+)/) {
        $oper{level}    = $1;
        $oper{flags}    = $2;
        $oper{nick}     = $3;
        $oper{hostmask} = $4;
        $oper{idle}     = $5;
    } else {
        return;
    }

    if ($oper{nick} =~ /tcm$/i || $oper{hostmask} =~ /tcm@/i) {
       $oper{tcm} = 1;
       $stats_p_num_tcm++;
    }

    $oper{bopm} = 0;
    if ($oper{nick} =~ /bopm$/i || $oper{hostmask} =~ /bopm@/i) {
        $oper{bopm} = 1;
        $stats_p_num_bopm++;
    }

    if ($oper{nick} =~ /ddd/i || $oper{hostmask} =~ /ddd@/i) {
        $oper{ddd} = 1;
        $stats_p_num_ddd++;
    }

    $stats_p_data{ $oper{nick} } = \%oper;

    # Check if this idle time is already present in the array with
    # idle times; if not, add it.
    my $alreadypresent = 0;
    for my $idletime (@stats_p_idletimes) {
        if ($oper{idle} == $idletime) {
            $alreadypresent = 1;
            last;
        }
    }

    push @stats_p_idletimes, $oper{idle} unless $alreadypresent;

    Irssi::signal_stop();
}

# ---------------------------------------------------------------------

sub reemit_stats_p_line {
    my ($server, $data, $servername) = @_;

    # We need to re-emit this 249 numeric in case it contains data which
    # has nothing to do with stats p. Unfortunately, the end of STATS ?
    # also uses numeric 249, and we don't want to lose this data.

    # For some reason I do not comprehend, Irssi does not display
    # the first word of $args when re-emitting this signal. Hence
    # the 'dummy_data' addition.
    # Perhaps the number of the numeric should be here.
    # Perhaps there is a rational explanation.
    # I do not know, but this seems to work properly.
    Irssi::signal_emit("default event numeric",
        $server, "dummy_data " . $data, $servername);
    Irssi::signal_stop();
}

# ---------------------------------------------------------------------
# Prints the hash of collected stats p data.

sub event_stats_end {
    my ($server, $data, $servername) = @_;

    return unless $data =~ /p :End of \/STATS report/;

    Irssi::signal_stop();

    print_stats_p_data($servername);

    undef %stats_p_data;
    undef @stats_p_idletimes;
    $stats_p_num_tcm = 0;
    $stats_p_num_bopm = 0;
}

# ---------------------------------------------------------------------
# Prints a list of opers, tcms and bopms, sorted by idle time.

sub print_stats_p_data {
    my ($servername) = @_;
    my @sorted_idletimes = sort {$a <=> $b} @stats_p_idletimes;

    Irssi::printformat(MSGLEVEL_CRAP, 'ho_stats_p_begin_report',
        $servername);
    Irssi::printformat(MSGLEVEL_CRAP, 'ho_stats_p_head_opers',
        $servername);

    # Kind of clumsy way to sort these opers on idle times.
    # Sort the idle times, then for each idle time value, walk
    # through the whole hash of opers and print the one(s) with
    # this idle time.
    for my $idletime (@sorted_idletimes) {
        for my $opernick (keys %stats_p_data) {
            next unless $stats_p_data{$opernick}->{idle} == $idletime;

            next if $stats_p_data{$opernick}->{tcm} ||
                    $stats_p_data{$opernick}->{bopm} ||
                    $stats_p_data{$opernick}->{ddd};

            print_stats_p_oper($stats_p_data{$opernick});
        }
    }

    # Print the TCM(s)
    if ($stats_p_num_tcm > 0) {
        Irssi::printformat(MSGLEVEL_CRAP, 'ho_stats_p_head_tcm',
            $servername);
        for my $opernick (keys %stats_p_data) {
            if ($stats_p_data{$opernick}->{tcm} == 1) {
                print_stats_p_oper($stats_p_data{$opernick});
            }
        }
    }

    # Print the BOPM(s)
    if ($stats_p_num_bopm > 0) {
        Irssi::printformat(MSGLEVEL_CRAP, 'ho_stats_p_head_proxy',
            $servername);
        foreach my $opernick (keys %stats_p_data) {
            if ($stats_p_data{$opernick}->{"bopm"} == 1) {
                print_stats_p_oper($stats_p_data{$opernick});
            }
        }
    }

    # Print the DDD(s)
    if ($stats_p_num_ddd > 0) {
            Irssi::printformat(MSGLEVEL_CRAP, 'ho_stats_p_head_ddd',
                $servername);
        for my $opernick (keys %stats_p_data) {
            if ($stats_p_data{$opernick}->{"ddd"} == 1) {
                print_stats_p_oper($stats_p_data{$opernick});
            }
        }
    }

    Irssi::printformat(MSGLEVEL_CRAP, 'ho_stats_p_end_report',
        $servername);
}

# ---------------------------------------------------------------------
# Prints a line with idle time, nick and hostmask of this oper.

sub print_stats_p_oper {
    my ($oper) = @_;

    my ($hours, $mins, $secs) = seconds_to_hms($oper->{idle});

    Irssi::printformat(MSGLEVEL_CRAP, 'ho_stats_p_line', $oper->{nick},
        $hours, $mins, $secs, $oper->{hostmask});
}

# ---------------------------------------------------------------------

ho_print_init_begin();

#>> :irc.Prison.NET 249 Garion :[O] RFdrone (~asamonte@SanQuentin.Prison.NET) idle 31546s
#>> :irc.Prison.NET 219 Garion p :End of /STATS report
Irssi::signal_add_first('event 249', 'event_stats_p_line');
Irssi::signal_add_last('event 249', 'reemit_stats_p_line');
Irssi::signal_add_last('event 219', 'event_stats_end');

Irssi::theme_register( [
    'ho_stats_p_begin_report',
    '%YSTATS p report%n of $0',

    'ho_stats_p_head_opers',
    '* %_Operators%_ on $0:',

    'ho_stats_p_head_tcm',
    '* %_TCM bots%_ on $0:',

    'ho_stats_p_head_proxy',
    '* %_Proxy monitors%_ on $0:',

    'ho_stats_p_end_report',
    '* %_End of report%_ of $0',

    'ho_stats_p_line',
    '$[-9]0 $[-3]1:$[-2]2:$[-2]3 ($4)',

        'ho_stats_p_head_ddd',
    '* %_DDD bots%_ on $0',
] );

ho_print("Output style is determined by ho_stats_p_* formats.");
ho_print_init_end();

# ---------------------------------------------------------------------

