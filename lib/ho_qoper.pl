# ho_qoper.pl
#
# $Id: ho_qoper.pl,v 1.8 2004/08/21 10:56:07 jvunder REL_0_1 $
#
# Part of the Hybrid Oper Script Collection
#
# Quick Oper script - keeps your oper pass in memory and uses it to oper
# up directly after being connected.
#

use strict;
use warnings;
use Irssi;
use HOSC::again;
use HOSC::again 'HOSC::Base';
use HOSC::again 'HOSC::Tools';
import HOSC::Tools qw(get_named_token);

use vars qw[%IRSSI];

%IRSSI = HOSC::Base::ho_get_IRSSI(
    name        => 'Quick Oper',
    description => 'Automatic opering on connect.',
);

my $main_password;
my $tag_passwords;

# ----------------------------------------------------------------------

sub cmd_qoper {
    my ($args, $server, $item) = @_;

    if ($args =~ m/^(help)|(status)|(password)|(clearpass)/i ) {
        Irssi::command_runsub ('qoper', $args, $server, $item);
        return;
    }

    if ($args =~ /^\S+$/) {
        cmd_qoper_operup($args);
    } else {
        print_usage();
    }
}

# ----------------------------------------------------------------------

sub cmd_qoper_help {
    print_help();
}

# ----------------------------------------------------------------------

sub cmd_qoper_status {
    ho_print("Qoper status:");
    if (defined $main_password) {
        ho_print("Main password is set.");
    } elsif (keys %$tag_passwords == 0) {
        ho_print("No passwords set.");
        return;
    }

    if (keys %$tag_passwords == 1) {
        ho_print("Password set on tag '" . (keys %$tag_passwords)[0] . "'.");
    } else {
        ho_print("Passwords set on tags " .
            join(' ', sort keys %$tag_passwords) . ".");
    }
}

# ----------------------------------------------------------------------

sub cmd_qoper_password {
    my ($args, $server, $item) = @_;

    if ($args =~ /^(\S+)\s+(.+)$/) {
        set_password($2, $1);
    } else {
        set_password($args);
    }
}

# ----------------------------------------------------------------------

sub set_password {
    my ($password, $tag) = @_;

    if (defined $tag) {
        $tag_passwords->{$tag} = $password;
        ho_print("Password set on tag '$tag'.");

        my @networks = get_networks();
        if (!grep $tag, @networks) {
            ho_print_warning("This script is not active for tag '$tag'. Use ".
                "the setting ho_qoper_networks to enable it for '$tag'.");
        }
    } else {
        $main_password = $password;
        ho_print("Main password set.");
    }
}

# ----------------------------------------------------------------------

sub cmd_qoper_clearpass {
    my ($args, $server, $item) = @_;

    clear_password($args);
}

# ----------------------------------------------------------------------

sub clear_password {
    my ($tag) = @_;

    if (defined $tag && $tag =~ /\S/) {
        if (defined $tag_passwords->{$tag}) {
            delete $tag_passwords->{$tag};
            ho_print("Deleted password for tag '$tag'.");
        } else {
            ho_print("No password stored for tag '$tag'.");
        }
    } else {
        if (defined $main_password) {
            $main_password = undef;
            ho_print("Deleted main password.");
        } else {
            ho_print("No main password stored.");
        }
    }
}

# ----------------------------------------------------------------------

sub cmd_qoper_operup {
    my ($tag, $server, $item) = @_;

    my @networks = get_networks();
    if (!grep $tag, @networks) {
        ho_print("Qoper is not activated for tag '$tag'. Use the setting ".
            "ho_qoper_networks to set this.");
        return;
    }

    my $server = Irssi::server_find_tag($tag);
    if (!$server) {
        ho_print("You are not connected to tag '$tag'.");
        return;
    }

    if ($server->{server_operator}) {
        ho_print("You are already opered on tag '$tag'.");
        return;
    }

    my $password = get_password($tag);
    if (!defined $password) {
        ho_print("There is no password set for tag '$tag'");
        return;
    }

    ho_print("Opering up on tag '$tag'.");
    my $opernick = get_opernick($server->{tag});
    $server->send_raw_now("OPER $opernick $password");
}

# ----------------------------------------------------------------------

sub event_connected {
    my ($server) = @_;

    my @networks = get_networks();
    my $tag = lc $server->{tag};
    return unless grep /^$tag$/, @networks;

    my $password = get_password($server->{tag});
    if (defined $password) {
        ho_print("qoper - connected; sending OPER command.");
        my $opernick = get_opernick($server->{tag});
        if (!defined $opernick || length $opernick  == 0) {
            $opernick = $server->{nick};
        }

        $server->send_raw_now("OPER $opernick $password");
    } else {
        ho_print("qoper - connected to " . $server->{tag} .
            " but no password is set.");
    }
}

# ----------------------------------------------------------------------

sub event_opered {
    my ($server, $msg) = @_;

    my @networks = get_networks();
    return unless grep lc $server->{tag}, @networks;

    my $usermodes = get_usermodes($server->{tag});

    if (defined $usermodes && length $usermodes > 0) {
        ho_print("qoper - just opered up. setting user modes $usermodes");
        $server->send_raw_now('MODE ' . $server->{nick} . " $usermodes");
    } else {
        ho_print("qoper - no usermodes set for tag " . $server->{tag} . ".");
    }
}

# ----------------------------------------------------------------------

sub get_networks {
    my @networks = split / +/,
        lc Irssi::settings_get_str('ho_qoper_network_tags');
    return @networks;
}

# ----------------------------------------------------------------------

sub get_password {
    my ($tag) = @_;
    return $tag_passwords->{$tag} if defined $tag_passwords->{$tag};
    return $main_password;
}

# ----------------------------------------------------------------------

sub get_opernick {
    my ($tag) = @_;
    return get_named_token(Irssi::settings_get_str('ho_qoper_nick'), $tag);
}

# ----------------------------------------------------------------------

sub get_usermodes {
    my ($tag) = @_;
    return get_named_token(Irssi::settings_get_str('ho_qoper_usermode'), $tag);
}

# ----------------------------------------------------------------------

ho_print_init_begin();

Irssi::signal_add_first('event 001', 'event_connected');
Irssi::signal_add_first('event 381', 'event_opered');

Irssi::command_bind('qoper',           'cmd_qoper');
Irssi::command_bind('qoper help',      'cmd_qoper_help');
Irssi::command_bind('qoper status',    'cmd_qoper_status');
Irssi::command_bind('qoper password',  'cmd_qoper_password');
Irssi::command_bind('qoper clearpass', 'cmd_qoper_clearpass');

Irssi::settings_add_str('ho', 'ho_qoper_network_tags', '');
Irssi::settings_add_str('ho', 'ho_qoper_nick', '');
Irssi::settings_add_str('ho', 'ho_qoper_usermode', '+xy-c');

ho_print_init_end();

# ----------------------------------------------------------------------

sub print_usage {
    ho_print_help('section', 'Syntax');
    ho_print_help('syntax', 'QOPER help');
    ho_print_help('syntax', 'QOPER status');
    ho_print_help('syntax', 'QOPER password <password>');
    ho_print_help('syntax', 'QOPER password <tag> <password>');
    ho_print_help('syntax', 'QOPER clearpass');
    ho_print_help('syntax', 'QOPER clearpass <tag>');
    ho_print_help('syntax', 'QOPER <tag>');
}

sub print_help {
    ho_print_help('head', $IRSSI{name});

    print_usage();

    ho_print_help('section', 'Description');
    ho_print_help('This script allows your client to be opered ' .
        "automatically upon connect, and set usermodes when opered.\n");
    ho_print_help("You can store a main oper password ".
        "which will be used as default, plus one or more exceptions ".
        "for any networks that you use a different password on. The same ".
        "can be done for your oper nick.\n");
    ho_print_help("To oper up manually, use /QOPER <tag>. If the script " .
        "is active for this tag and a password has been stored for it, ".
        "the script will attempt to oper up.\n");
    ho_print_help('Why should you use this instead of -autosendcmd? ' .
        'Well, the main reason is that this script stores the oper '.
        'password(s) in memory, not in a config file. This is much '.
        'safer than -autosendcmd. The second reason is that this '.
        "setup is much more flexible.\n");

    ho_print_help('section', 'Settings');
    ho_print_help('setting', 'ho_qoper_network_tags',
        'A space separated list of the server tags of the networks that ' .
        'this script should work on.');
    ho_print_help('setting', 'ho_qoper_nick',
        'Your oper nick. If not set, your current nick is used. ' .
        'This is a multitoken. See /HO HELP MULTITOKEN');
    ho_print_help('setting', 'ho_qoper_usermodes',
        'The usermodes that are set right after you oper up. Use the '.
        'format +abc-def. '.
        'This is a multitoken. See /HO HELP MULTITOKEN');
}

