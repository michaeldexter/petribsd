#!/bin/sh

branch="13-MFM"
_image="gi-${branch}"

echo Exporting $vm_image zpool
zpool get -H name $_image && zpool export $_image 

echo
zpool list

echo
echo Is export $vm_image gone? ; read foo

echo FYI destroying /dev/ggate0
[ -e /dev/ggate1 ] && ggatel destroy -f -u 0

