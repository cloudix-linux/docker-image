#!/bin/bash
fs_file="cloudix-linux-fs.tar.bz2"

if [ -f "$fs_file" ] ; then
        checksum_prev=$(md5sum "$fs_file" |awk '{print $1}')
fi

./mkimage.sh sark/cloudix latest true

checksum=$(md5sum "$fs_file" |awk '{print $1}')

printf "\n"
if [ -z "checksum_prev" ] ; then
  echo "New $fs_file checksum is $checksum"
else
  echo "Previous $fs_file checksum was $checksum_prev"
  echo "New $fs_file checksum is $checksum"
fi
exit 0
