
# Based on BlackJac's /TFIND and morrow's stat.pl script.
#
# Known bugs:
# * If the output window is closed halfway, the script crashes.

use strict;
use warnings;
use vars qw(%IRSSI);

use Irssi;
use Irssi::Irc;
use Irssi::HOSC::again;
use Irssi::HOSC::again 'Irssi::HOSC::Base';
use Irssi::HOSC::again 'Irssi::HOSC::Tools';
import Irssi::HOSC::Tools qw(test_regexps get_equality glob_to_regexp);
use Getopt::Long;

%IRSSI = Irssi::HOSC::Base::ho_get_IRSSI(
    name        => 'Trace Find',
    description => 'Provides extended search functionality for the /TRACE command.',
);

my ($stats, $args);
my @found_clients; # Storage place for found clients in case of sorting
my @cache;
my $cache_time;
my $cache_tag;  # the network tag for which the cache is active.

# ---------------------------------------------------------------------
# /TFIND

sub cmd_tfind {
    my ($arguments, $server, $item) = @_;

    $args = parse_arguments($arguments);

    if ($args->{help}) {
        Irssi::command_runsub ('tfind', 'help', $server, $item);
        return;
    }

    if ($args->{error} || length $arguments == 0) {
        return print_usage();
    }

    if (!$server) {
        return ho_print_error("No server in this window.");
    }

    $stats->{num_clients} = 0;
    $stats->{num_found}   = 0;
    $stats->{window}      = Irssi::active_win();
    @found_clients        = ();

    if ($stats->{busy}) {
        ho_print_error("Sorry, already performing a TFIND. Please wait.");
        return;
    }

    if ($args->{equality} && $args->{equality} !~ /^(n|nu|nr|ur|nur)$/) {
        ho_print_error("TFIND: Invalid equality " . $args->{equality} . ".");
        return;
    }

    for my $property (qw[ rnick ruser rhost rgecos ]) {
        if (defined $args->{$property} && !test_regexps($args->{$property})) {
            return ho_print_error("TFIND: Invalid regexp in $property.");
        }
    }

    my $search_param_text = get_param_text($args);
    ho_print("Searching TRACE output with params $search_param_text");

    my $use_cache = Irssi::settings_get_bool('ho_tfind_use_cache');
    if ($use_cache && !$args->{nocache}) {
        my $cache_expiry_time =
            Irssi::settings_get_int('ho_tfind_cache_expiry_time');
        my $cache_age = time() - $cache_time;

        if (!$use_cache) {
            ho_print_warning('Cache is not enabled. Use "/set ' .
                'ho_tfind_use_cache ON" to enable it.');
        } elsif (@cache == 0) {
            ho_print_warning('Cache empty. Not using it.');
        } elsif ($cache_age > $cache_expiry_time) {
            ho_print_warning('Cache expired. Not using it.');
        } elsif ($cache_tag ne $server->{tag}) {
            ho_print_warning('Cache contents are for diffent tag. Replacing cache.');
            undef @cache;
        } else {
            # Phew, can use the cache.
            ho_print("Using cache: " . scalar @cache . " clients. ".
                "Age is $cache_age/$cache_expiry_time.");
            trace_from_cache($server);
            return;
        }
    }

    $server->redirect_event(
        'command cmd_tfind', 0, '', (split(/\s+/, $arguments) > 2), undef, {
                "event 203", "redir event_trace_line",
                "event 204", "redir event_trace_line",
                "event 205", "redir event_trace_line",
                "event 709", "redir event_trace_line",
                "event 206", "redir event_stop",
                "event 207", "redir event_stop",
                "event 208", "redir event_stop",
                "event 209", "redir event_stop",
                "event 262", "redir event_trace_end",
                "event 421", "redir event_unknown_command",
        }
    );

    $stats->{busy} = 1;
    $cache_tag = $server->{tag};
    undef @cache;
    $cache_time = time;
    if ($args->{etrace} || $server->{version} =~ /ircd-ratbox/) {
        $server->send_raw("ETRACE");
    } else {
        $server->send_raw("TRACE");
    }
}

# ---------------------------------------------------------------------

sub cmd_tfind_help {
    my ($arguments, $server, $item) = @_;
    print_help();
}

# ---------------------------------------------------------------------

sub parse_arguments {
    my ($arguments) = @_;
    my $opt;

    # Irssi works with -argument, Getopt::Long expects --argument. Fix.
    $arguments =~ s/-/--/g;

    # Smart splitting of $arguments: understands "multi word argument".
    local @ARGV;
    my @tempargv = split / /, $arguments;
    my ($in_multi_token, $delimiter, $index) = (0, undef, 0);
    while (@tempargv) {
        my $token = shift @tempargv;
        if ($in_multi_token) {
            if ($token =~ /$delimiter$/) {
                # End of multi token argument
                $token =~ s/$delimiter$//;
                $ARGV[$index] .= " " . $token;
                $in_multi_token = 0;
                $index++;
            } else {
                # Continue multi token argument
                $ARGV[$index] .= " " . $token;
            }
        } elsif ($token =~ /^(['"])/ && $token !~ /['"]$/) {
            # New multi token argument
            $delimiter = $1;
            $token =~ s/^['"]//;
            $ARGV[$index] = $token;
            $in_multi_token = 1;
        } else {
            # Single token argument
            $ARGV[$index] = $token;
            $index++;
        }
    }

    # Prevent GetOptions frow screwing up the layout in case of errors.
    # Thanks xmath. :)
    local $SIG{__WARN__} = sub {
        my ($msg) = @_;
        $msg = '/TFIND: ' . $msg;
        ho_print_error($msg);
    };

    my $res = GetOptions(
        'nocache'   => \$opt->{nocache},
        'sort=s'    => \$opt->{sort},
        'nick=s'    => \$opt->{nick},
        'user=s'    => \$opt->{user},
        'host=s'    => \$opt->{host},
        'ip=s'      => \$opt->{ip},
        'gecos=s'   => \$opt->{gecos},
        'rnick=s'   => \$opt->{rnick},
        'ruser=s'   => \$opt->{ruser},
        'rhost=s'   => \$opt->{rhost},
        'rip=s'     => \$opt->{rip},
        'rgecos=s'  => \$opt->{rgecos},
        'equality=s'=> \$opt->{equality},
        'spoof'     => \$opt->{spoof},
        'nospoof'   => \$opt->{nospoof},
        'oper'      => \$opt->{oper},
        'nooper'    => \$opt->{nooper},
        'etrace'    => \$opt->{etrace},
        'help'      => \$opt->{help},
        '4'         => \$opt->{ipv4},
        '6'         => \$opt->{ipv6},
        'rawcmd=s'  => \$opt->{rawcmd},
    );

    $opt->{error} = 1 unless $res;

    for my $arg (@ARGV) {
        # If any args left, read them.
        if ($arg eq "help") {
            $opt->{help} = 1;
        } else {
            $opt->{error} = 1;
        }
    }

    # Change glob patterns into regexp patterns.
    for my $var (qw[ nick user host gecos ip ]) {
        if (defined $opt->{$var}) {
            # Store the original glob request for displaying later on.
            $opt->{"glob$var"} = $opt->{$var};
            # Convert glob to regexp for matching later on.
            $opt->{$var}       = glob_to_regexp($opt->{$var});
        }
    }

    # Now restore any -- in the values back to -.
    for my $key (keys %$opt) {
        $opt->{$key} =~ s/--/-/g;
    }

    return $opt;
}

# ---------------------------------------------------------------------

sub get_param_text {
    my ($args) = @_;
    my $text;

    for my $var (qw[ nick user host gecos ip ]) {
        if (defined $args->{$var} && length $args->{$var}) {
            $text .= "($var is " . $args->{"glob$var"} . ") ";
        }
        if (defined $args->{"r$var"} && length $args->{"r$var"}) {
            $text .= "($var regexp " . $args->{"r$var"} . ") ";
        }
    }

    $text .= "(spoof) "     if $args->{spoof};
    $text .= "(not spoof) " if $args->{nospoof};
    $text .= "(oper) "      if $args->{oper};
    $text .= "(not oper) "  if $args->{nooper};
    $text .= "(only ipv4) " if $args->{ipv4};
    $text .= "(only ipv6) " if $args->{ipv6};
    $text .= "(equality " . $args->{equality} . ") " if $args->{equality};

    $text .= "using ETRACE " if $args->{etrace};

    $text =~ s/\) \(/) and (/g;
    $text =~ s/ $//;
    return $text;
}

# ---------------------------------------------------------------------
# Catching and processing output of the ircd.

sub event_trace_line {
    my ($server, $data, $nick, $address) = @_;
    my ($ownnick, $line) = $data =~ /^(\S*)\s+(.*)$/;

    my $details = get_trace_line_details($line);
    return if $details->{crap};

    if (Irssi::settings_get_bool('ho_tfind_use_cache')) {
        push @cache, $details;
    }
    process_line($details, $server);
}

# ---------------------------------------------------------------------

sub trace_from_cache {
    my ($server) = @_;
    for my $details (@cache) {
        process_line($details, $server);
    }
    trace_end();
}

# ---------------------------------------------------------------------
# Processes one line of TRACE output, whether retrieved from TRACE output
# or from the cache.

sub process_line {
    my ($details, $server) = @_;

    $stats->{num_clients}++;

    for my $check (qw[ nick user host gecos ip ]) {
        # Glob check
        return if defined $args->{$check} && length $args->{$check} &&
            $details->{$check} !~ /$args->{$check}/i;

        # Regexp check
        return if defined $args->{"r$check"} && length $args->{"r$check"} &&
            $details->{$check} !~ /$args->{"r$check"}/;
    }

    return if $args->{spoof}   && $details->{ip} ne "255.255.255.255";
    return if $args->{nospoof} && $details->{ip} eq "255.255.255.255";
    return if $args->{oper}    && !$details->{is_oper};
    return if $args->{nooper}  && $details->{is_oper};
    return if $args->{ipv4}    && !$details->{ipv4};
    return if $args->{ipv6}    && !$details->{ipv6};

    if ($args->{equality}) {
        my $eq = get_equality($details->{nick}, $details->{user},
            $details->{gecos});
        return if $eq ne $args->{equality};
    }

    if (defined $args->{rawcmd}) {
        execute_raw_command($details, $server);
    } elsif (defined $args->{sort}) {
        push @found_clients, $details;
    } else {
        print_client($details);
    }
    $stats->{num_found}++;
}

# ---------------------------------------------------------------------

sub print_client {
    my ($details) = @_;

    my $format = 'ho_tfind_line';
    $format = 'ho_tfind_line_v6' if $details->{ipv6};

    $stats->{window}->printformat(MSGLEVEL_CRAP, $format,
        $details->{nick}, $details->{user}, $details->{host},
        $details->{gecos}, $details->{ip});
}

# ---------------------------------------------------------------------

sub execute_raw_command {
    my ($details, $server) = @_;

    my $cmd = $args->{rawcmd};
    for (qw[ nick user host gecos ip ]) {
        $cmd =~ s/%$_%/$details->{$_}/g;
    }
    $server->send_raw_now($cmd);
}

# ---------------------------------------------------------------------
# Processes a single /TRACE output line and returns a hashref with the
# relevant data.

sub get_trace_line_details {
    my ($line) = @_;

    my $details;

    # TRACE
    if ($line =~ /(User|Oper)\s+(\S+)\s+(\S+)\[([^@]+)@(\S+)\]\s+\(([^)]+)\)/) {
        $details->{is_user} = 1 if $1 eq "User";
        $details->{is_oper} = 1 if $1 eq "Oper";
        $details->{class}   = $2;
        $details->{nick}    = $3;
        $details->{user}    = $4;
        $details->{host}    = $5;
        $details->{ip}      = $6;
        $details->{ipv4}    = 1 if $details->{ip} !~ /:/;
        $details->{ipv6}    = 1 if $details->{ip} =~ /:/;
        return $details;
    }

    # ETRACE
    if ($line =~ /(User|Oper)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+:(.*)$/) {
        $details->{is_user} = 1 if $1 eq "User";
        $details->{is_oper} = 1 if $1 eq "Oper";
        $details->{class}   = $2;
        $details->{nick}    = $3;
        $details->{user}    = $4;
        $details->{host}    = $5;
        $details->{ip}      = $6;
        $details->{gecos}   = $7;
        $details->{ipv4}    = 1 if $details->{ip} !~ /:/;
        $details->{ipv6}    = 1 if $details->{ip} =~ /:/;
        return $details;
    }

    $details->{crap} = 1;
    return $details;
}

# ---------------------------------------------------------------------

sub signal_stop {
    my ($server, $data, $nick, $address) = @_;
    Irssi::signal_stop();
}

# ---------------------------------------------------------------------

sub event_trace_end {
    my ($server, $data, $nick, $address) = @_;

    trace_end();
}

# ---------------------------------------------------------------------

sub trace_end {
    if (defined $args->{sort}) {
        my @sorted_clients = sort_clients(@found_clients);
        print_client($_) for @sorted_clients;
    }

    ho_print("Found " . $stats->{num_found} . " match" .
        ($stats->{num_found} == 1 ? "" : "es") .
        " in " . $stats->{num_clients} . " client" .
        ($stats->{num_clients} == 1 ? "" : "s") . ".");
    $stats->{busy} = 0;
}

# ---------------------------------------------------------------------

sub sort_clients {
    my @clients = @_;

    my %sort_params = (
        n => {
            field    => 'nick',
            order    => 'normal',
        },
        N => {
            field    => 'nick',
            order    => 'reverse',
        },
        u => {
            field    => 'user',
            order    => 'normal',
        },
        U => {
            field    => 'user',
            order    => 'reverse',
        },
        h => {
            field    => 'host',
            order    => 'normal',
        },
        H => {
            field    => 'host',
            order    => 'reverse',
        },
        g => {
            field    => 'gecos',
            order    => 'normal',
        },
        G => {
            field    => 'gecos',
            order    => 'reverse',
        },
    );

    if (exists $sort_params{$args->{sort}}) {
        return
            map { $_->[0] }
            sort {
                text_compare(
                    $a->[1], $b->[1],
                    $sort_params{$args->{sort}}->{order},
                    Irssi::settings_get_bool('ho_tfind_sort_case_sensitive')
                )
            }
            map { [ $_, $_->{ $sort_params{ $args->{sort} }->{field} } ] }
            @clients;
    } elsif ($args->{sort} eq 'i') {
        return
            map { $_->[0] }
            sort { ip_compare($a->[1], $b->[1]) }
            map { [ $_, $_->{ip} ] }
            @clients;
    }

    return @clients;
}

# ---------------------------------------------------------------------

sub text_compare {
    my ($first, $second, $reverse, $case_sensitive) = @_;

    if ($reverse eq 'normal') {
        if ($case_sensitive) {
            return ($first cmp $second);
        } else {
            return ((lc $first) cmp (lc $second));
        }
    } else {
        if ($case_sensitive) {
            return ((reverse $first) cmp (reverse $second));
        } else {
            return ((reverse lc $first) cmp (reverse lc $second));
        }
    }
}

# ---------------------------------------------------------------------
# This is not an exact ip comparison, but it's Good Enough[tm].
# It treats the ip as a number and sorts that.

sub ip_compare {
    my ($first, $second) = @_;

    if ($first =~ /\./) {
        return -1 if $second =~ /:/;
        return $first <=> $second;
    } else {
        return 1 if $second =~ /\./;
        return $first <=> $second;
    }
}

# ---------------------------------------------------------------------

sub event_unknown_command {
    my ($server, $data, $nick, $address) = @_;

    ho_print_error("This server does not support ETRACE.");
    $stats->{busy} = 0;
}

# ---------------------------------------------------------------------
# Initialisation

ho_print_init_begin();

Irssi::settings_add_bool('ho', 'ho_tfind_use_cache', 0);
Irssi::settings_add_int('ho',  'ho_tfind_cache_expiry_time', 60);
Irssi::settings_add_bool('ho', 'ho_tfind_sort_case_sensitive', 0);

Irssi::command_bind('tfind',       'cmd_tfind');
Irssi::command_bind('tfind help',  'cmd_tfind_help');

Irssi::signal_add({
    "redir event_trace_line"       => \&event_trace_line,
    "redir event_trace_end"        => \&event_trace_end,
    "redir event_stop"             => \&signal_stop,
    "redir event_unknown_command"  => \&event_unknown_command,
});


# ok this is IMO realy ugly, if anyone has a suggestion please let me know
Irssi::Irc::Server::redirect_register("command cmd_tfind", 0, 0,
    {
        "event 203" => 1, # RPL_TRACEUNKNOWN
        "event 204" => 1, # RPL_TRACEOPERATOR
        "event 205" => 1, # RPL_TRACEUSER
        "event 206" => 1, # RPL_TRACESERVER
        "event 207" => 1, # RPL_TRACESERVICE
        "event 208" => 1, # RPL_TRACENEWTYPE
        "event 209" => 1, # RPL_TRACECLASS
        "event 709" => 1, # ratbox ETRACE output
    },
    {
        "event 219" => 1,  # end of stats
        "event 262" => 1,  # end of trace
        "event 263" => 1,  # tryagain
        "event 401" => 1,  # no such server
        "event 421" => 1,  # unknow command (missing ETRACE)
    },
    undef,
);

# Register format.
# nick, user, host, gecos, ip

Irssi::theme_register([
    'ho_tfind_line',
    '{nick $[-9]0}{comment %g$[!15]4}{chanhost_hilight $[-11]1@$[!38]2}{comment $3}',

    'ho_tfind_line_v6',
    '{nick $[-9]0}{comment %g$[!24]4}{chanhost_hilight $[-11]1@$[!38]2}{comment $3}',
]);

ho_print_init_end();

# ---------------------------------------------------------------------
# Help.

sub print_usage {
    ho_print_help('section', 'Syntax');
    ho_print_help('syntax', '/TFIND [-]HELP');
    ho_print_help('syntax', "/TFIND -<switch> [<arg>] -<switch> [<arg>] ..");
    #ho_print_help('syntax', "/TFIND -<switch> [<arg>] [action [arguments]]\n");
    #ho_print_help("Use /TFIND -help for help\n");
}

sub print_help {
    ho_print_help('head', $IRSSI{name});

    print_usage();

    ho_print_help('section', 'Introduction');
    ho_print_help("Script to search through /TRACE output.\n");
    ho_print_help("Glob search has * and ? as wildcards.\n");
    ho_print_help('This script has a cache built in, which is disabled by '.
        'default. It can be enabled by setting ho_tfind_use_cache to ON. '.
        'When a TRACE is sent to the server and caching is enabled, the '.
        'TRACE output is stored internally. If another /TFIND is done '.
        'shortly after the previous one, the cache data is used instead of '.
        "sending another TRACE to the server.\n");

    ho_print_help('section', 'Arguments');
    ho_print_help('argument', '-nocache',
        'Does not use cache, even if available.');

    my @args = (
        [qw(nick Glob nickname)],
        [qw(user Glob username)],
        [qw(host Glob hostname)],
        [qw(ip Glob ip)],
        [qw(gecos Glob gecos)],
        [qw(rnick Regexp nickname)],
        [qw(ruser Regexp username)],
        [qw(rhost Regexp hostname)],
        [qw(rip Regexp ip)],
        [qw(rgecos Regexp gecos)],
    );
    for my $arg (@args) {
        ho_print_help('argument', '-' . $arg->[0] . ' <pattern>',
        $arg->[1] . ' searches for <pattern> in the ' . $arg->[2] . '.');
    }

    ho_print_help('argument', '-4',       'Searches for ipv4 clients.');
    ho_print_help('argument', '-6',       'Searches for ipv6 clients.');
    ho_print_help('argument', '-oper',    'Searches for opers.');
    ho_print_help('argument', '-nooper',  'Excludes opers.');
    ho_print_help('argument', '-spoof',   'Searches for spoofs.');
    ho_print_help('argument', '-nospoof', 'Excludes spoofs.');

    ho_print_help('argument', '-equality <equality>',
        'Requires this equality. See below.');
    ho_print_help('argument', '-sort <criterium>',
        'Sorts by criterium. See below.');
    ho_print_help('argument', '-rawcmd "<cmd>"',
        'Executes the given command. See below.');

    ho_print_help('argument', '-etrace',  'Use ETRACE instead of TRACE.');

    ho_print_help('section', 'Settings');
    ho_print_help('setting', 'ho_tfind_use_cache',
        'Boolean indicating whether to cache /TRACE output.');
    ho_print_help('setting', 'ho_tfind_cache_expiry_time',
        'Time, in seconds, after which the cache becomes invalid.');
    ho_print_help('setting', 'ho_tfind_sort_case_sensitive',
        'Whether output sorting is case sensitive.');
#    ho_print_help('setting', 'ho_tfind_kline_time',
#        'Time (in minutes) for -kline option. [not functional yet]');
#    ho_print_help('setting', 'ho_tfind_kline_reason',
#        'Reason for -kline option. [not functional yet]');
#    ho_print_help('setting', 'ho_tfind_log_file',
#        'File to log found clients to. [not functional yet]');

    ho_print_help('section', 'Equality');
    ho_print_help("Equality is a term which describes the relationship ".
        "between a client's nick, user and realname (gecos). The following ".
        "equalities exist:");
    ho_print_help("  n   - all three are different");
    ho_print_help("  nu  - nick equals username, realname is different");
    ho_print_help("  nr  - nick equals realname, username is different");
    ho_print_help("  ur  - username equals realname, nick is different");
    ho_print_help("  nur - all three are equal\n");

    ho_print_help('section', 'Sorting');
    ho_print_help("The output of clients can be sorted using the -sort ".
        "option. The following search criteria are allowed:");
    ho_print_help("  n - sort by nick");
    ho_print_help("  N - sort by reversed nick");
    ho_print_help("  u - sort by username");
    ho_print_help("  U - sort by reversed username");
    ho_print_help("  h - sort by host");
    ho_print_help("  H - sort by reversed host");
    ho_print_help("  g - sort by gecos");
    ho_print_help("  G - sort by reversed gecos");
    ho_print_help("  i - sort by ip");
    ho_print_help("By default, sorting is done case insensitive. To " .
        "change this, use the setting ho_tfind_sort_case_sensitive.\n");

    ho_print_help('section', 'Raw command');
    ho_print_help("Using the -rawcmd option, you can make this script " .
        "execute a raw IRCD command on all the found clients. Do not " .
        "forget to put the double quotes around the command.");
    ho_print_help("To make this feature actually useful, several " .
        "strings are automatically replaced by the found client's " .
        "properties before the raw command is sent. These are:");
    ho_print_help("  %nick%  - the client's nick");
    ho_print_help("  %user%  - the client's username");
    ho_print_help("  %host%  - the client's hostname");
    ho_print_help("  %ip%    - the client's ip");
    ho_print_help("  %gecos% - the client's gecos");
    ho_print_help("Remember: do not forget the quotes around the command!\n");

    ho_print_help('section', 'Examples');
    ho_print_help('argument', '/tfind -spoof -nooper -sort H',
        'Finds all spoofed, non-opered clients, sorted by their '.
        'reversed hostname.');
    ho_print_help('argument', '/tfind -rnick ^\[..+\].?[0-9]+$ -equality nu',
        'Finds all clients with a [abc]-123 kind of nickname, whose ' .
        'nickname is equal to their username.');
    ho_print_help('argument', '/tfind -gecos "w3 rul3 j00r 4ss" -rawcmd '.
        '"PRIVMSG %nick% :.die"', 'Finds all clients with the "we rule" '.
        'gecos, and sends them a message ".die".');
    ho_print_help('argument', '/tfind -rnick [A-Z]{4} -rawcmd '.
        '"DLINE %ip% :drone"', 'Places a D-line on the ip of each client ' .
        'with at least 4 consecutive uppercase letters in their nick.');
}

