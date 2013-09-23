package Irssi::HOSC::Base;

use strict;
require Exporter;
use Irssi::HOSC::again;

use vars qw[
    $VERSION @ISA @EXPORT @EXPORT_OK
    $HAVE_AGAIN
];

$VERSION = '0.4';
@ISA = qw[Exporter];

my %BASE_IRSSI = (
    authors        => 'Garion',
    contact        => 'joost@vunderink.net',
    name           => 'default_name',
    description    => 'default description',
    license        => 'Public Domain',
    url            => 'https://github.com/joostvunderink/irssi-hosc/',
    changed        => '2013-09-21 10:00:00+02',
);

@EXPORT = qw[
    ho_reload_modules
    $VERSION
];

@EXPORT_OK = qw[
];

sub ho_get_IRSSI {
    my %args = @_;
    my %irssi = %BASE_IRSSI;
    for my $key (keys %args) {
        $irssi{$key} = $args{$key};
    }
    return %irssi;
}

sub ho_reload_modules {
    my ($print_progress) = @_;

    HOSC::Tools::ho_print("Reloading modules.") if $print_progress;
    my $num_modules_upgraded = 0;
    my $num_total_modules;
    for my $module (sort keys %INC) {
        next unless $module =~ /^HOSC\/[A-Z]/;
        $num_total_modules++;

        $module =~ s,/,::,;
        $module =~ s/\.pm$//;
        my $old_version = $module->VERSION;
        HOSC::again::require_again($module);
        my $new_version = $module->VERSION;
        if ($new_version ne $old_version) {
            $num_modules_upgraded++;
            HOSC::Tools::ho_print($module . ' ' . '.' x (20 - length $module) .
                     " $old_version -> $new_version")
                if $print_progress;
        }
    }
    HOSC::Tools::ho_print("Modules upgraded: $num_modules_upgraded/".
                          $num_total_modules)
        if $print_progress;
}

1;
