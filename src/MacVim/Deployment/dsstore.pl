#!/usr/bin/perl -w

use Mac::Finder::DSStore qw( writeDSDBEntries makeEntries );
use Mac::Memory qw( );
use Mac::Files qw( NewAliasMinimal );

&writeDSDBEntries("DS_Store",
    &makeEntries(".",
        BKGD_alias => NewAliasMinimal("/Volumes/MacVim-KaoriYa/background.png"),
        ICVO => 1,
        fwi0_flds => [ 57, 10, 557, 510, "icnv", 0, 0 ],
        fwsw => 184,
        fwvh => 460,
        icgo => "\0\0\0\4\0\0\0\4",
        icvo => pack('A4 n A4 A4 n*', "icv4", 96, "none", "botm", 0, 0, 4, 0, 4, 0, 0, 100, 1),
        icvt => 13,
        vstl => "icnv"
    ),
    &makeEntries("KaoriYa", Iloc_xy => [ 322, 404 ]),
    &makeEntries("MacVim.app", Iloc_xy => [ 116, 208 ]),
    &makeEntries("README.txt", Iloc_xy => [ 178, 404 ]),
    &makeEntries("background.png", Iloc_xy => [ 0, 0 ]),
    &makeEntries("\x{306f}\x{3057}\x{3099}\x{3081}\x{306b}\x{304a}\x{8aad}\x{307f}\x{304f}\x{305f}\x{3099}\x{3055}\x{3044}.rtfd", Iloc_xy => [ 240, 66 ]),
    &makeEntries("\x{30a2}\x{30d5}\x{309a}\x{30ea}\x{30b1}\x{30fc}\x{30b7}\x{30e7}\x{30f3}", Iloc_xy => [ 384, 208 ])
);

