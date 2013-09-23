irssi-hosc
==========

A set of oper scripts for the IRC client irssi

Introduction
------------

[Irssi](http://irssi.org) is one of the best console IRC clients ever made.
Its powerful Perl scripting interface makes it very easy to extend and improve.

This set of scripts has been made to make life easier of, initially, EFnet opers.
Some of the scripts are also functional on other IRCDs.

HOSC stands for Hybrid Oper Script Collection, Hybrid being the name of the IRCD
that was the most popular on EFnet when the scripts were written.

Installation
------------

By default, irssi scripts are stored in ~/.irssi/scripts. HOSC does not only have
scripts, but also a few modules which are shared by several scripts. This is how
you should install HOSC:

- ~/.irssi/scripts/ho_*.pl
- ~/.irssi/scripts/Irssi/HOSC/*.pm

This can be done by the following steps:

    git clone https://github.com/joostvunderink/irssi-hosc.git
    cd irssi-hosc
    bin/install.pl

