#! perl

package HOSC::Constants;

use strict;
use warnings;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    OPERFLAGS
);

use constant OPERFLAGS => {
    efnet => {
        G => 'gline',
        K => 'kline',
        X => 'xline',
        Q => 'resv',
        O => 'globalkill',
        C => 'localkill',
        R => 'squit',
        U => 'unkline',
        H => 'rehash',
        D => 'die',
        A => 'admin',
        N => 'nicks',
        L => 'operwall',
        S => 'operspy',
        P => 'hidden',
        B => 'remote',
    },
};

1;

