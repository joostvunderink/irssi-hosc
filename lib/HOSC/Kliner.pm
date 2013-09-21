package HOSC::Kliner;

# $Id: Kliner.pm,v 1.4 2004/08/21 11:28:59 jvunder REL_0_1 $
#
# K-line module.

# ---------------------------------------------------------------------

use strict;
use Irssi;
use HOSC::again;
use HOSC::again 'HOSC::Base';
use HOSC::again 'HOSC::Tools';

# ---------------------------------------------------------------------
# Constructor.

sub new {
    my ($class) = @_;
    return bless {
        settings       => {},
        warnings       => 0,
        default_time   => 1440,
        default_reason => 'spamming is prohibited',
    }, $class;
}

# ---------------------------------------------------------------------

sub kline {
    my ($self, %args) = @_;

    return unless defined $args{server};
    return unless defined $args{host};

    my $userhost;
    if (defined $args{user}) {
        $userhost = $args{user} . '@' . $args{host};
    } else {
        $userhost = '*@' . $args{host};
    }

    my $time = $self->{'default_time'};
    $time = $args{'time'} if defined $args{'time'};

    my $reason = $self->{'default_reason'};
    $reason = $args{'reason'} if defined $args{'reason'};

    my $msg;
    my $server = $args{server};
    if ($server->{version} =~ /(hybrid|ratbox)/) {
        $msg = "KLINE $time $userhost :$reason";
        $server->send_raw_now($msg);
    } elsif ($server->{version} =~ /^u2/) {
        $time *= 60;
        $msg = "GLINE !+$userhost $time :$reason";
        # Don't raw send this - ircu doesn't like flooding.
        $server->command("QUOTE $msg");
    } else {
        ho_print_error("Unknown server version '" . $server->{version} .
            "' for " . $server->{tag} . " found in HOSC::Kliner::kline().");
    }
}

# ---------------------------------------------------------------------

1;  # so the require or use succeeds

# ---------------------------------------------------------------------
# EOF
