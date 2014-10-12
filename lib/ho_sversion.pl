
# Provides an easy way to get the version of all linked servers.
# NOTE: This server only works well for opered clients on a
# hybrid-compatible network, since it uses the flooding capabilities
# of opers on such servers.
# Known bugs:
# * Doing /VERSION <server> while the script is doing its thing doesn't
#   give any output.

use strict;
use warnings;
use vars qw(%IRSSI);

use Irssi;
use Irssi::Irc;           # necessary for redirect_register()
use Irssi::HOSC::again;
use Irssi::HOSC::again 'Irssi::HOSC::Base';
use Irssi::HOSC::again 'Irssi::HOSC::Tools';

# ---------------------------------------------------------------------

%IRSSI = Irssi::HOSC::Base::ho_get_IRSSI(
    name        => 'Server Versions',
    description => 'Checks the version of all linked servers.',
);

# Hashtable with server versions.
# Key is the server name.
# Value is the version.
my %server_versions;

my %data = (
    currently_busy       => 0,
    servers_linked       => 0,
    servers_processed    => 0,
    my_server_tag        => undef,
    timer_gather_id      => undef,
    timer_gather_done_id => undef,
);

# ---------------------------------------------------------------------

sub cmd_sversion {
    my ($data, $server, $item) = @_;
    if ($data =~ m/^[(help)]/i ) {
        Irssi::command_runsub ('sversion', $data, $server, $item);
        return;
    }

    if ($data{currently_busy}) {
        ho_print_error("Sorry, already performing a version check.");
        return;
    }

    ho_print("Checking version of all linked servers.");
    ho_print("Please wait up to " . 
        Irssi::settings_get_int('ho_sversion_max_time') . " seconds.");
    $server->redirect_event('command cmd_sversion', 1, undef, 0, undef,
        {
            'event 364' => 'redir event_links_line',
            'event 365' => 'redir event_links_end',
        }
    );
    delete $server_versions{$_} for keys %server_versions;
    $data{currently_busy}    = 1;
    $data{servers_linked}    = 0;
    $data{servers_processed} = 0;
    $data{my_server_tag}     = $server->{tag};

    # Now send LINKS to obtain a list of all linked servers. Then we can
    # send a VERSION for each server.
     $server->send_raw_now('LINKS');
}

# ---------------------------------------------------------------------

sub cmd_sversion_help {
    print_help();
}

# ---------------------------------------------------------------------

sub event_links_line {
    my ($server, $args, $nick, $address) = @_;
    if ($args =~ /^\S+\s+(\S+)\s/) {
        $server_versions{$1} = undef;
    }
    Irssi::signal_stop();
    $data{servers_linked}++;
}

# ---------------------------------------------------------------------

sub event_links_end {
    my ($server, $args, $nick, $address) = @_;
    
    # We've obtained the complete list of servers. Now go send a VERSION
    # for each one.
    get_versions($server);
    Irssi::signal_stop();
}

# ---------------------------------------------------------------------

sub get_versions {
    my ($server) = @_;

    # Here we'll just issue a VERSION $servername for each server.
    # Then we wait until the last version gets back, or up to
    # sversion_max_time seconds, whichever occurs first. During this
    # time we will steal all 351 (version) and 005 (isupport) numerics
    # and signal_stop them.
    for my $sname (keys %server_versions) {
        $server->command("QUOTE VERSION $sname");
    }

    # We -must- have a timeout on this version gathering in case one or
    # more servers fail to reply. The version gathering is considered to
    # be complete as soon as all version replies have been received, or
    # this timer is executed, whichever occurs first.
    my $time = Irssi::settings_get_int('ho_sversion_max_time');
    $time = 10 if $time < 10;
    $data{timer_gather_id} = 
       Irssi::timeout_add($time * 1000, 'gather_completed', undef);
}

# ---------------------------------------------------------------------
# The 351 numeric.
# :towel.carnique.nl 351 Garion hybrid-7.0(20030611_2). towel.carnique.nl :egGHIKMpZ6 TS5ow

sub event_server_version {
    my ($server, $args, $nick, $address, $target) = @_;

    # We always stop this signal.
    Irssi::signal_stop();

    # But if we're not busy with gathering a version list, we'll have to
    # re-emit this signal.
    if (!$data{currently_busy}) {
        # For some reason I do not comprehend, Irssi does not display
        # the first word of $args when re-emitting this signal. Hence
        # the 'dummy_data' addition.
        # Perhaps the number of the numeric should be here.
        # Perhaps there is a rational explanation.
        # I do not know, but this seems to work properly.
        Irssi::signal_emit("default event numeric", 
            $server, "dummy_data " . $args, $nick, $address);
        return;
    }
    
    # RFC dictates that there should be four fields. The first is the
    # version, the second is the server name. Any ircd doing it in a 
    # different way is not RFC compliant.
    if ($args =~ /^\S+\s(\S+)\s(\S+)\s:/) {
        $server_versions{$2} = $1;
        $data{servers_processed}++;
        if ($data{servers_processed} == $data{servers_linked}) {
            # The gathering is complete. However, don't print the list
            # of servers immediately, because it could be that we're
            # still about to receive a few 105 numerics. We want those
            # to be suppressed as well. So, wait 3 seconds before
            # printing the list.
            $data{timer_gather_done_id} = 
               Irssi::timeout_add(3000, 'gather_completed', undef);
        }
    }
}

# ---------------------------------------------------------------------
# The 005 numeric.

sub event_server_isupport_local {
    my ($server, $args, $nick, $address) = @_;

    # We don't do anything with the isupport numeric (yet), but we want
    # to stop it anyway. Otherwise you'd get a lot of scroll.
    Irssi::signal_stop();

    if (!$data{currently_busy}) {
        # See event_server_version for 'dummy_data' explanation.
        Irssi::signal_emit("default event numeric", 
            $server, "dummy_data " . $args, $nick, $address);
        return;
    }
}

# ---------------------------------------------------------------------
# The 105 numeric.

sub event_server_isupport_remote {
    my ($server, $args, $nick, $address) = @_;

    # We don't do anything with the isupport numeric (yet), but we want
    # to stop it anyway. Otherwise you'd get a lot of scroll.
    Irssi::signal_stop();

    if (!$data{currently_busy}) {
        # See event_server_version for 'dummy_data' explanation.
        Irssi::signal_emit("default event numeric", 
            $server, "dummy_data " . $args, $nick, $address);
        return;
    }
}

# ---------------------------------------------------------------------

sub gather_completed {
    if ($data{timer_gather_id}) {
        Irssi::timeout_remove($data{timer_gather_id});
        undef $data{timer_gather_id};
    }
    if ($data{timer_gather_done_id}) {
        Irssi::timeout_remove($data{timer_gather_done_id});
        undef $data{timer_gather_done_id};
    }
    $data{currently_busy} = 0;
    print_versions();
}

# ---------------------------------------------------------------------

sub print_versions {
    my ($server) = @_;

    ho_print('Server versions:');
    for my $sname (sort keys %server_versions) {
        Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'ho_sversion_line',
            $sname, $server_versions{$sname});
    }
    ho_print("Total servers linked: $data{servers_linked}.");
}

# ---------------------------------------------------------------------

ho_print_init_begin();

# The redirect for LINKS output.
Irssi::Irc::Server::redirect_register('command cmd_sversion', 0, 0, 
    {
        'event 364' => 1,
    },
    {
        'event 365' => 1,
    },
    undef
);

Irssi::signal_add('redir event_links_line', 'event_links_line');
Irssi::signal_add('redir event_links_end',  'event_links_end');

Irssi::signal_add_first('event 351', 'event_server_version');
Irssi::signal_add_first('event 005', 'event_server_isupport_local');
Irssi::signal_add_first('event 105', 'event_server_isupport_remote');

Irssi::command_bind('sversion',      'cmd_sversion');
Irssi::command_bind('sversion help', 'cmd_sversion_help');

Irssi::settings_add_int('ho', 'ho_sversion_max_time', 60);

Irssi::theme_register([
    'ho_sversion_line',
    '$[25]0 - $1',
]);

ho_print_init_end();
ho_print("Use /SVERSION HELP for help.");

# ---------------------------------------------------------------------

sub print_help {
    ho_print_help('head', $IRSSI{name});

    ho_print_help('section', 'Description');
    ho_print_help("This script displays a list of the server versions ".
        "of all servers on the network.");
    ho_print_help("It does so by first issuing /LINKS and then doing a ".
        "/VERSION <server> for each server.");
    ho_print_help("Make sure your settings 'cmds_max_at_once' and ".
        "'cmd_queue_speed' are set to proper values so this script can ".
        "issue the /VERSION commands as quickly as possible without ".
        "being disconnected for excess flood.\n");

    ho_print_help('section', 'Syntax');
    ho_print_help('syntax', 'SVERSION [HELP]');

    ho_print_help('section', 'Settings');
    ho_print_help('setting', 'ho_sversion_max_time', 
        'Maximum time to wait for VERSION replies.');
}

# ---------------------------------------------------------------------
