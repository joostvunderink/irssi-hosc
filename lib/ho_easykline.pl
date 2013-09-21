use strict;
use warnings;
use vars qw(%IRSSI);

use Irssi;
use Irssi::Irc;           # necessary for redirect_register()
use HOSC::again;
use HOSC::again 'HOSC::Base';
use HOSC::again 'HOSC::Tools';

%IRSSI = HOSC::Base::ho_get_IRSSI(
    name        => 'EasyKline',
    description => 'Makes K-lining drones as easy as cake.',
);

# Master switch to prevent accidents.
my $enabled = 0;

my $klineuseronly = 1;

# ---------------------------------------------------------------------

# catch a line typed in the easykline window, and process it.
sub event_send_text {
    my ($data, $server, $witem) = @_;
    my $active_window = Irssi::active_win();

    return unless $active_window->{name} eq "easykline";

    if ($data =~ /^on$/i || $data =~ /^enable$/i) {
        ho_print_active("Enabling easy K-lines.");
        $enabled = 1;
        Irssi::signal_stop();
        return;
    }

    if ($data =~ /^off$/i || $data =~ /^disable$/i) {
        ho_print_active("Disabling easy K-lines.");
        $enabled = 0;
        Irssi::signal_stop();
        return;
    }

    if ($data =~ /^help$/i) {
        print_help();
        Irssi::signal_stop();
        return;
    }

    if ($data =~ /^time ([0-9]+)$/i) {
        set_kline_time($1);
        ho_print_active("Setting K-line time to $1.");
        Irssi::signal_stop();
        return;
    }

    if ($data =~ /^reason (.+)$/i) {
        ho_print_active("Setting K-line reason to $1.");
        set_kline_reason($1);
        Irssi::signal_stop();
        return;
    }

    if ($data =~ /^klineuser ?(.*)$/i) {
        if ($1 =~ /on/i || $1 == 1) {
            Irssi::settings_set_bool('ho_easykline_useronly', 1);
            ho_print_active('K-lining *user@host.');
        } else {
            Irssi::settings_set_bool('ho_easykline_useronly', 0);
            ho_print_active('K-lining *@host.');
        }

        Irssi::signal_stop();
        return;
    }

    if ($data =~ /^status$/i) {
        show_status();
        Irssi::signal_stop();
        return;
    }

    if ($enabled == 0) {
        ho_print_active("Easy K-lines disabled. Type 'help' for help and 'on' to enable.");
        Irssi::signal_stop();
        return;
    }

  kline_from_line($server, $data);
}


sub am_i_opered {
    return 0 unless Irssi::active_server();
    return 1 if Irssi::active_server()->{server_operator}
             or Irssi::active_server()->{'usermode'} =~ /o/i;

    return 0;
}


sub set_kline_time {
    my ($time) = @_;
    Irssi::settings_set_int('ho_easykline_time', $time);
}

sub set_kline_reason {
    my ($reason) = @_;
    Irssi::settings_set_str('ho_easykline_reason', $reason);
}


sub show_status {
    my $klineuseronly = Irssi::settings_get_bool('ho_easykline_useronly');
    my $klinetime     = Irssi::settings_get_int('ho_easykline_time');
    my $klinereason   = Irssi::settings_get_str('ho_easykline_reason');
    ho_print_active("Enabled is $enabled. Time is $klinetime.");
    if ($klineuseronly) {
        ho_print_active('K-lining *user@host.');
    } else {
        ho_print_active('K-lining *@host.');
    }

    ho_print_active("Reason is $klinereason.");
}

sub print_help {
    ho_print_active("Short help for now.");
    ho_print_active('Anything you paste in this window gets searched for '.
        'user@host and those hostnames get K-lined.');
    ho_print_active("Available settings: enable/disable, time, reason, ".
             "klineuseronly.");
    ho_print_active("Typing the following into this window will change settings:");
    ho_print_active("on|off: turns the script on or off.");
    ho_print_active("time <time>: sets the k-line time. 0 for perm kline.");
    ho_print_active("reason <reason>: sets the k-line reason.");
    ho_print_active('klineuser <on|off>: toggles the k-lining of '.
        '*user@host and *@host.');
    ho_print_active("Type 'status' to get the current status of easykline.");
}

sub kline_from_line {
    my ($server, $line) = @_;

    if (!am_i_opered()) {
        ho_print_active("Please oper up before using this script.");
        return;
    }

    if ($line =~ /\b~?([a-zA-Z0-9._-]{1,10})@([a-zA-Z0-9_.-]+)\b/) {
        my ($user, $host) = ($1, $2);
        my $klineuseronly = Irssi::settings_get_bool('ho_easykline_useronly');
        my $klinetime     = Irssi::settings_get_int('ho_easykline_time');
        my $klinereason   = Irssi::settings_get_str('ho_easykline_reason');
        if ($klineuseronly == 1) {
            $user = "*" . $1;
        } else {
            $user = "*";
        }
        if ($klinetime == 0) {
            ho_print_active("K-lined $user\@$host :$klinereason");
            $server->command("quote kline $user\@$host :$klinereason");
        } else {
            ho_print_active("K-lined $klinetime $user\@$host :$klinereason");
            $server->command("quote kline $klinetime $user\@$host :$klinereason");
        }
    }
}

# ---------------------------------------------------------------------

ho_print_init_begin();

Irssi::signal_add('send text', 'event_send_text');

Irssi::settings_add_int('ho', 'ho_easykline_time', 1440);
Irssi::settings_add_str('ho', 'ho_easykline_reason', 'drones/flooding');
Irssi::settings_add_bool('ho', 'ho_easykline_useronly', 1);

my $win = Irssi::window_find_name('easykline');
if (!defined($win)) {
    ho_print_warning("You are missing the easykline window. Use /WINDOW ".
        "NEW HIDDEN and /WINDOW NAME easykline to create it.\n".
        "Easy K-lines are only available when typing in that window.");
}

ho_print("For help, switch to the window named easykline and type 'help' there.");

if (!am_i_opered()) {
    ho_print("You'll need to oper up to use this script.");
}

ho_print_init_end();

# ---------------------------------------------------------------------

