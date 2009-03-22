#!/bin/sh
rsync -avzcP --delete --exclude="dos" --exclude="spell" ftp.nluug.nl::Vim/runtime/ runtime/
git add runtime
echo "Make sure everything is OK, then commit"
