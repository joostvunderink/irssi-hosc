#!/usr/bin/perl

use strict;
use warnings;

use Getopt::Long;
use File::Copy;
use File::Basename;

use File::Path qw(make_path);

use constant MODULES_DIR => 'HOSC';

run();

# ------------------------

sub run {
    my $opt;

    GetOptions(
        'dir=s'       => \$opt->{'dir'},
        'help'        => \$opt->{'help'},
    ) or die usage();

    if ($opt->{'help'}) {
        die usage();
    }

    print "\n";
    my $install_dir = get_installdir($opt);
    my $installed_version = get_version($install_dir);
    my $new_version = get_version('lib');
    my $compare = compare_versions($installed_version, $new_version);

    if ($compare == 0) {
        print "Version $new_version already installed.\n";
        exit(0);
    }

    print "\nInstalling HOSC version $new_version in $install_dir\n";
    if ($installed_version) {
        print "  Version $installed_version is currently installed.\n";
    }
    print "\nAre you sure? [y/N] ";

    my $answer = <>;
    chomp $answer;
    
    if (not(defined $answer && $answer =~ /^y/i)) {
        print "\nNot installing HOSC.\n";
        exit(0);
    }

    install_hosc($install_dir);
}

sub get_installdir {
    my ($opt) = @_;
    if (defined $opt->{'dir'}) {
        return $opt->{'dir'};
    }

    my $default_installdir = $ENV{'HOME'} . "/.irssi/scripts";

    print "Install where? [$default_installdir] ";
    my $answer = <>;
    chomp $answer;
    if (length $answer) {
        return $answer;
    } else {
        return $default_installdir;
    }

    return $default_installdir;
}

sub get_version {
    my ($dir) = @_;

    my $hosc_base_filename = sprintf "%s/%s/Base.pm", $dir, MODULES_DIR;
    print "Reading version from $hosc_base_filename\n";
    if (!-e $hosc_base_filename) {
        print "Base.pm not found, no HOSC in $dir.\n";
        return;
    }

    my $hosc_base = open my $fh, '<', $hosc_base_filename;
    for my $line (<$fh>) {
        if ($line =~ /\$VERSION = '(\d+\.\d+)';/) {
            print "Found version $1.\n";
            return $1;
        }
    }

    return;
}

sub install_hosc {
    my ($dir) = @_;

    if (!-d $dir) {
        print "Creating $dir\n";
        make_path($dir);
    }

    my $modules_dir = sprintf "%s/%s", $dir, MODULES_DIR;
    if (!-d $modules_dir) {
        print "Creating $modules_dir\n";
        mkdir($modules_dir);
    }

    opendir my $dh, 'lib';
    while (my $filename = readdir($dh)) {
        if ($filename =~ /\.pl$/) {
            print "Installing $filename\n";
            copy("lib/$filename", $dir);
        }
    }

    opendir $dh, 'lib/HOSC';
    while (my $filename = readdir($dh)) {
        if ($filename =~ /\.pm$/) {
            print "Installing $filename\n";
            copy(sprintf("lib/%s/$filename", MODULES_DIR), $modules_dir);
        }
    }

    print "\nInstalled HOSC in $dir.\n";
}

# Returns 1  if $first > $second
# Returns 0  if $first == $second
# Returns -1 if $first < $second
sub compare_versions {
    my ($first, $second) = @_;

    # undef is considered to be version 0.
    $first  ||= "0.0";
    $second ||= "0.0";

    return 0 if "$first" eq "$second";

    my ($first_major,  $first_minor)  = $first  =~ /^(\d+)\.(\d+)$/;
    my ($second_major, $second_minor) = $second =~ /^(\d+)\.(\d+)$/;
    
    return  1 if $first_major > $second_major;
    return -1 if $first_major < $second_major;

    return  1 if $first_minor > $second_minor;
    return -1;
}
