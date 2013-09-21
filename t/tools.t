#! perl

use lib 't/inc';
use Test::More tests => 14;

use HOSC::Tools qw(
    get_equality
    get_named_token
    get_operflags
    test_regexps
);

diag("get_equality tests");
{
    my @tests = (
        {
            nick => 'a',
            user => 'a',
            real => 'a',
            equality => 'nur',
        },
        {
            nick => 'a',
            user => 'abc',
            real => 'a',
            equality => 'nr',
        },
        {
            nick => 'a',
            user => 'a',
            real => 'abc',
            equality => 'nu',
        },
        {
            nick => 'a',
            user => 'abc',
            real => 'abc',
            equality => 'ur',
        },
        {
            nick => 'a',
            user => 'ab',
            real => 'abc',
            equality => 'n',
        },
    );

    for my $t (@tests) {
        my $eq = get_equality($t->{'nick'}, $t->{'user'}, $t->{'real'});
        is $eq, $t->{'equality'},
            sprintf("equality of nick='%s' user='%s' real='%s': '%s'",
                $t->{'nick'}, $t->{'user'}, $t->{'real'}, $t->{'equality'});
    }
}

diag("test_regexp() tests");
{
    ok test_regexps("aoeu", "[xyz]+.*huk"), "correct regexps returns true";
    ok !test_regexps("(]"), "incorrect regexp returns false";
}

diag("get_named_token() tests");
{
    my @tests = (
        {
            text => 'main',
            name => '',
            value => 'main',
        },
        {
            text => 'main extra1:one extra2:two',
            name => '',
            value => 'main',
        },
        {
            text => 'main extra1:"one two three"',
            name => '',
            value => 'main',
        },
        {
            text => 'main extra1:one',
            name => 'extra1',
            value => 'one',
        },
        {
            text => 'main extra1:"one two three"',
            name => 'extra1',
            value => 'one two three',
        },
        {
            text => 'main extra1:"one two three"',
            name => 'extra2',
            value => 'main',
        },
    );

    for my $t (@tests) {
        my $value = get_named_token($t->{'text'}, $t->{'name'});
        is $value, $t->{'value'},
            sprintf("named token text='%s' name='%s' value: '%s'",
                $t->{'text'}, $t->{'name'} || '', $t->{'value'});
    }
}

diag("get_operflags");
{
    my $flags = {
        G => 'gline',
        A => 'admin',
    };

    my $result = get_operflags((join '', keys %$flags), 'efnet');
    is_deeply $result, $flags, "got the right flags";
}

