package HOSC::Tools;

# Known annoyances:
# * When adding an extra format, you must restart irssi, because you can't
#   re-register the formats in a script or so. Bah.

use strict;

use Irssi;
require Exporter;

use HOSC::Constants qw(
    OPERFLAGS
);
use HOSC::Base;

use vars qw[ 
    @ISA @EXPORT @EXPORT_OK
];

@ISA = qw[Exporter];
@EXPORT = qw[
    get_window_by_name
    ho_print
    ho_print_name
    ho_print_active
    ho_print_warning
    ho_print_error
    ho_print_crap
    ho_print_help
    ho_print_init_begin
    ho_print_init_end
    ho_print_status
];

@EXPORT_OK = qw[
    get_equality
    get_named_token
    get_operflags
    glob_to_regexp
    is_server_notice
    seconds_to_hms
    seconds_to_dhms
    test_regexps
];

BEGIN {
    # Register formats
    Irssi::theme_register( [
        'ho_crap',
        '{line_start}%Cho%n $0',

        'ho_warning',
        '{line_start}%Cho%n %Ywarning%n $0',

        'ho_error',
        '{line_start}%Cho%n %Rerror%n $0',

        'ho_message',
        '{line_start}%Cho%n $0',

        'ho_message_name',
        '{line_start}%Cho $0%n $1',

        'ho_init_begin',
        '{line_start}%CHybrid Oper Script Collection%n $0 - $1.',

        'ho_init_end',
        '{line_start}%G$0%n loaded.',

        'ho_help',
        '$0-',

        'ho_help_head',
        '%CHybrid Oper Script Collection%n' . "\n" . '%G$0-%n' . "\n",

        'ho_help_section',
        '%Y$0-%n' . "\n",

        'ho_help_setting',
        '%_$0%_' . "\n" . '$1-' . "\n",

        'ho_help_argument',
        '%_$0%_' . "\n" . '$1-' . "\n",

        'ho_help_syntax',
        '%_$0%_' . "\n",

        'ho_help_command',
        '%_$0%_' . "\n" . '$1-',
    ] );

    # We need to load ho_tools if it's not loaded already.
    no strict 'refs';
    if (!grep(/^ho_tools::$/, keys %Irssi::Script::)) {
        Irssi::print("%Cho%n ho_tools.pl not yet loaded - loading.", 
            MSGLEVEL_CRAP);
        Irssi::command("script load ho_tools");
    }
}

# ---------------------------------------------------------------------
# Returns the window object belonging to the window with name $name.

sub get_window_by_name {
    my ($name) = @_;

    # Get the reference to the window from irssi
    my $win = Irssi::window_find_name($name);

    # If not found, get the reference to window 1
    # I'm hoping that this does ALWAYS exist :)
    # But if not... how can this be improved so to ALWAYS return a valid
    # window reference?
    if (!defined($win)) {
        $win = Irssi::window_find_refnum(1);
    }

    return $win;
}

sub ho_print {
    Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'ho_message', @_);
}

# ho_print_name is like ho_print, but the name of the script is the first
# variable.

sub ho_print_name {
    my ($package, $filename, $line) = caller;
    if ($package =~ /::ho_(.+)$/) {
        $package = $1;
    }
    Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'ho_message_name', $package, @_);
}

sub ho_print_active {
    my $win = Irssi::active_win();
    $win->printformat(MSGLEVEL_CLIENTCRAP, 'ho_message', @_);
}
 
sub ho_print_warning {
    Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'ho_warning', @_);
}
 
sub ho_print_error {
    Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'ho_error', @_);
}
 
sub ho_print_crap {
    Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'ho_crap', @_);
}

# This would be useful, but alas! Calling this function from a script where
# a format has defined means that the printformat will be called from this
# scope, where the format hasn't been defined. I don't know how to fix this.
sub ho_print_format {
    my $format = shift;
    Irssi::printformat(MSGLEVEL_CLIENTCRAP, $format, @_);
}
 
sub ho_print_status {
    ho_print "HOSC Script Status:";
    ho_print "Loaded modules:";
    for my $script (sort keys %INC) {
        next unless $script =~ /^HOSC\/[A-Z]/;
        $script =~ s,/,::,;
        $script =~ s/\.pm$//;
        ho_print($script . ' ' . '.' x (20 - length $script) . ' ' .
            $script->VERSION );
    }

    ho_print "Loaded scripts:";
    no strict 'refs';
    my %scripts = %Irssi::Script::;
    for my $name (sort keys %scripts) {
        next unless $name =~ /ho_/;
        $name =~ s/:://;
        my $version = ${ "Irssi::Script::${name}::VERSION" };
        ho_print("$name " . '.' x (20 - length $name) . " $version");
    }
}

sub ho_print_help {
    my ($item, @help) = @_;

    for my $format (qw[head section setting argument syntax command]) {
        if ($item eq $format) {
            Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'ho_help_' . $item, @help);
            return;
        }
    }

    Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'ho_help', @_);
}

sub ho_print_init_begin {
    my ($package, $filename, $line) = caller;
    if ($package =~ /::ho_(.+)$/) {
        #$script_name = $1;
    } else {
        # Called from wrong location, aborting.
        return;
    }
    no strict 'refs';
    my $version     = $HOSC::Base::VERSION;
    my $script_name = ${ $package."::IRSSI" }{name};
    Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'ho_init_begin', $version, $script_name);
}

sub ho_print_init_end {
    my ($package, $filename, $line) = caller;
    if ($package =~ /::ho_(.+)$/) {
        #$script_name = $1;
    } else {
        # Called from wrong location, aborting.
        return;
    }
    no strict 'refs';
    my $script_name = ${ $package."::IRSSI" }{name};
    Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'ho_init_end', $script_name);
}

# -----------------------------------------------------------------
sub get_equality {
    my ($nick, $user, $real) = @_;

    if ($nick eq $user) {
        if ($nick eq $real) {
            return "nur";
        } else {
            return "nu";
        }
    } elsif ($nick eq $real) {
        return "nr";
    } elsif ($user eq $real) {
        return "ur";
    }

    return "n";
}


# -----------------------------------------------------------------
# Tests a number of regular expressions. If all of them are valid, 1 is
# returned. Otherwise, 0 is returned.

sub test_regexps {
    my (@regexps) = @_;

    for my $regexp (@regexps) {
        eval { /$regexp/ } ;
        return 0 if ($@);
    }

    return 1;
}

# -----------------------------------------------------------------
# A strange name but I couldn't think of anything better.
# This function splits $text into tokens separated by spaces. Each
# token can be either "value" or "name:value". The first non-named
# token is considered the main value.
# If a token with name $name is found, its value is returned.
# Otherwise, the main value is returned.
# $t = get_named_token('huk tilde:kek arf:barf', 'woot'); # $t = 'huk'
# $t = get_named_token('huk tilde:kek arf:barf', 'arf');  # $t = 'barf'
# For tokens with a value that contains spaces, you can use either
# name:"value with spaces" or name:'value with spaces'.

sub get_named_token {
    my ($text, $name) = @_;
    my %tokenhash;
    my $default_value;

    my $in_multi_token   = 0;
    my $delimiter        = undef;
    my $multi_token_name = '';
    my @tokens = split / /, $text;

    for my $token (@tokens) {
        if ($in_multi_token) {
            if ($token =~ /$delimiter$/) {
                # End of multi token argument
                $in_multi_token = 0;
                $token          =~ s/$delimiter$//;
                $tokenhash{$multi_token_name} .= " " . $token;
            } else {
                # Continue multi token argument
                $tokenhash{$multi_token_name} .= " " . $token;
            }
        } elsif ($token =~ /^([^:]+):(['"]).*[^\2]$/) {
            # New multi token argument
            $in_multi_token   = 1;
            $multi_token_name = $1;
            $delimiter        = $2;
            $token            =~ s/^[^:]+:['"]//;
            $tokenhash{$multi_token_name} = $token;
        } else {
            if ($token =~ /^([^:]+):(.+)$/) {
                $tokenhash{$1} = $2;
            } else {
                $default_value = $token unless defined $default_value;
            }
        }
    }

    if (exists $tokenhash{$name}) {
        return $tokenhash{$name};
    }

    return $default_value;
}

# ---------------------------------------------------------------------
# Returns true if $msg is a server notice.

sub is_server_notice {
    my ($server, $msg, $nick, $hostmask) = @_;

    return 0 unless $msg =~ /^NOTICE/;

    # For a server notice, the hostmask is empty.
    # If the hostmask is set, it is not a server NOTICE, so we'll ignore it
    # as well.
    return 0 if length $hostmask > 0;

    # For a server notice, the source server is stored in $nick.
    # It can happen that a server notice from a different server is sent
    # to us. This notice must not be reformatted.
    return 0 if $nick ne $server->{real_address};

    return 1;
}

# Simple glob to regexp function which only looks at ? and * wildcards.
sub glob_to_regexp {
    my ($glob) = @_;

    return '' unless length $glob;

    my $regexp = $glob;

    $regexp =~ s/\{/\\\{/g;
    $regexp =~ s/\}/\\\}/g;
    $regexp =~ s/\(/\\\(/g;
    $regexp =~ s/\)/\\\)/g;
    $regexp =~ s/\[/\\\[/g;
    $regexp =~ s/\]/\\\]/g;
    $regexp =~ s/\./\\\./g;
    $regexp =~ s/\?/./g;
    $regexp =~ s/\*/.*/g;
    $regexp = '^' . $regexp . '$';

    return $regexp;
}

# ---------------------------------------------------------------------
# Returns a list (hours, minutes, seconds) of the only argument, which
# is an amount of seconds. The minutes and seconds that are returned
# are 2 digits, so if they are below 10, a 0 is prepended.

sub seconds_to_hms {
    my ($seconds) = @_;
    my $hours = int( $seconds / 3600 );
    my $mins  = sprintf "%02d", int( ($seconds - $hours * 3600) / 60);
    my $secs  = sprintf "%02d", $seconds - $hours * 3600 - $mins * 60;
    return ($hours, $mins, $secs);
}

# ---------------------------------------------------------------------
# Returns a list (days, hours, minutes, seconds) of the only argument, which
# is an amount of seconds. The minutes and seconds that are returned
# are 2 digits, so if they are below 10, a 0 is prepended.

sub seconds_to_dhms {
    my ($seconds) = @_;
    my $days  = int( $seconds / 86400 );
    $seconds -= $days * 86400;
    my $hours = sprintf "%02d", int( $seconds / 3600 );
    my $mins  = sprintf "%02d", int( ($seconds - $hours * 3600) / 60);
    my $secs  = sprintf "%02d", $seconds - $hours * 3600 - $mins * 60;
    return ($days, $hours, $mins, $secs);
}

# ---------------------------------------------------------------------

sub get_operflags {
    my ($flagstring, $networktype) = @_;

    my $flags = { };

    if (!exists OPERFLAGS->{$networktype}) {
        return $flags;
    }

    for my $char (split //, $flagstring) {
        my $name = OPERFLAGS->{$networktype}{$char};
        if ($name) {
            $flags->{$char} = $name;
        }
    }

    return $flags;
}

1;

