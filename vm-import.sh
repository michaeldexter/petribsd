#!/bin/sh

branch="13-MFM"
vm_image="vm-${branch}"

# Test if file already imported, file present...
#zpool get name $vm_image > /dev/null 2>&1 || \
#	{ echo zpool $vm_image not found ; exit 1 ; }

# TEST FIRST!

echo Attaching $vm_image.img
ggatel create -u 1 /b/$branch/$vm_image.img
ggatel list


zpool import -R /b/$branch/vm-root -f $vm_image
zfs mount $vm_image/ROOT/default
zfs mount -a
