This directory contains the latest version of Vim runtime files.

To obtain those files that differ from your current files:
1. Make sure you have Python (version 1.5 or later).
2. Install Aap; see http://www.a-a-p.org/download.html
3. Change to the $VIMRUNTIME directory.  Use ":echo $VIMRUNTIME" in Vim to
   find out the right directory.
4. Run "aap" with the main.aap recipe from the ftp site.  It will download all
   the files that you don't have yet and those that are different from what's
   stored here.

For steps 3 and 4 you could type this:

        cd /usr/local/share/vim/vim70/
        aap -f ftp://ftp.vim.org/pub/vim/runtime/main.aap

You now have a complete set of the latest runtime files.

If you later want to obtain updated files, you can do:

        cd /usr/local/share/vim/vim70/
        aap update

Note: This only obtains new files, it does not delete files that are no
longer used.  It also is an effective way to erase any changes you made
to the files yourself!

The "main.aap" recipe was generated with the ":mkdownload" command in
"aap".
