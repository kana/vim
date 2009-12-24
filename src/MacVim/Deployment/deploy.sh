#!/bin/sh
DESTDIR=MacVim-KaoriYa
mkdir -p $DESTDIR/KaoriYa
cp DS_Store $DESTDIR/.DS_Store
cp ../../../README.txt $DESTDIR
cp ../../../README_w32j.txt $DESTDIR/KaoriYa
cp ../../../CHANGES_w32j.txt $DESTDIR/KaoriYa
cp background.png $DESTDIR
SetFile -a V $DESTDIR/background.png
cp -r readme.rtfd "$DESTDIR/はじめにお読みください.rtfd"
SetFile -a E "$DESTDIR/はじめにお読みください.rtfd"
ln -s /Applications "$DESTDIR/アプリケーション"
cp -r /Applications/MacPorts/MacVim.app $DESTDIR
hdiutil create -srcfolder MacVim-KaoriYa -format UDBZ macvim-kaoriya-`date +'%Y%m%d'`.dmg
