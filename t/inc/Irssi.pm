package Irssi;

require Exporter;
use vars qw(@ISA @EXPORT @EXPORT_OK);

@ISA = qw(Exporter);

our @EXPORT = qw(
    MSGLEVEL_CLIENTCRAP
    MSGLEVEL_CRAP
);

use constant MSGLEVEL_CRAP => 1;
use constant MSGLEVEL_CLIENTCRAP => 1;

sub theme_register {
    return 1;
}

sub print {
    return 1;
}

sub command {
    return 1;
}

1;
