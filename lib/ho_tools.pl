# ho_tools.pl
#
# $Id: ho_tools.pl,v 1.11 2004/08/22 20:20:57 jvunder REL_0_1 $
#
# Basic HOSC tools. This script is required for the HOSC, and will be
# automatically loaded when any other HOSC script is loaded.
#
# Part of the Hybrid Oper Script Collection.
#

use strict;
use warnings;

use vars qw[ $VERSION %IRSSI];
use Irssi;

use HOSC::again;
use HOSC::again 'HOSC::Base';
use HOSC::again 'HOSC::Tools';

($VERSION) = '$Revision: 1.11 $' =~ / (\d+\.\d+) /;
%IRSSI = (
    authors    => 'Garion',
    contact    => 'garion@efnet.nl',
    name       => 'ho_tools.pl',
    description    => 'Required HOSC Tools.',
    license    => 'Public Domain',
    url        => 'http://www.garion.org/irssi/',
    changed    => '24 April 2004 22:48:36',
);

# ---------------------------------------------------------------------
# The /HO command.
# Coder note: I tried putting this in HOSC/Tools.pm but Irssi doesn't like
# it if you execute Irssi::command_bind() inside a .pm file. If you have a
# working solution that allows this code to be put in Tools.pm, please let
# me know.

our @subcommands = qw(help status reload_modules);

Irssi::command_bind('ho',     'cmd_ho');
Irssi::command_bind('ho '.$_, 'cmd_ho_'.$_) for @subcommands;

sub cmd_ho {
    my ($data, $server, $item) = @_;

    if ($data =~ /^\s*$/) {
        HOSC::Tools::ho_print("Use /HO HELP for help.");
        return;
    }
    $data =~ s/\s+$//;

    my $command = $data;
    my $args;
    if ($data =~ /^(\S+)\s+(.+)$/) {
        $command = $1;
        $args = $2;
    }

    my @subs = grep /^$command/, @subcommands;
    if (@subs > 1) {
        ho_print("Ambiguous command. Try /HO HELP for help.");
    } elsif (@subs == 0) {
        ho_print("Unknown command $command. Use /HO HELP for help.");
    } else {
        Irssi::command_runsub('ho', $data, $server, $item);
    }
}

sub cmd_ho_help {
    my ($data, $server, $item) = @_;

    if (!defined $data || length $data == 0) {
        ho_print("General help");
        return;
    }

    if (lc $data eq 'multitoken') {
        print_help_multitoken();
    } else {
        ho_print("No help available for '$data'.");
    }
}

sub cmd_ho_status {
    my ($data, $server, $item) = @_;

    HOSC::Tools::ho_print_status();
}

sub cmd_ho_reload_modules {
    my ($data, $server, $item) = @_;

    ho_reload_modules(1);
}


sub print_help_multitoken {
    ho_print('Multitoken.');
    ho_print('A multitoken is a string which has one default value ' .
        'and one or more values for specifice keys. The values are space ' .
        'separated. The specific values are given by key:value tokens.');
    ho_print('An example of this would be "def huk:tilde kek:manner", which '.
        'defines the default value of "def", and the values "tilde" for key '.
        '"huk" and "manner" for key "kek".');
}
