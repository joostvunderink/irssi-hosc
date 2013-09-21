#! perl

use lib 't/inc';
use Test::More tests => 1;

use HOSC::Constants qw(
    OPERFLAGS
);

diag("OPERFLAGS");
{
    is OPERFLAGS->{'efnet'}{'G'}, 'gline', "found efnet flag 'G'";
}
 
