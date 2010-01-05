#!/bin/bash

make

D='src/MacVim/build/Release/MacVim.app/Contents/Resources/vim/runtime/doc'
cp runtime/doc/*[^~] "$D"
vim -u NONE -esX -c "helptags $D" -c 'quit'

# __END__
