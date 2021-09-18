#!/bin/sh

if [ ! $1 ] ; then
	echo Enter the zpool name:
	read pool
else
	pool="$1"
fi

zpool list -H -o name | grep $pool || \
	{ echo zpool $pool not found ; exit 1 ; }

zfs get all $pool/b && zfs destroy -f -r $pool/b

echo creating $pool/b with a mountpoint of /b
zfs create -o mountpoint=/b $pool/b ||
	{ echo zfs create failed ; exit 1 ; }

echo creating $pool/b/MAIN/src.git
zfs create -p $pool/b/MAIN/src.git || \
	{ echo zfs create failed ; exit 1 ; }
zfs snap $pool/b/MAIN/src.git@empty

echo Mirroring git.freebsd.org/src.git to /b/MAIN
git -C /b/MAIN clone --mirror https://git.freebsd.org/src.git || \
	{ echo git clone --mirror failed ; exit 1 ; }

ehco Snapshotting /b/MAIN/src.git dataset
zfs snap $pool/b/MAIN/src.git@mirror || \
	{ echo zfs snapshot failed ; exit 1 ; }

echo Listing banches
git --no-pager -C /b/MAIN/src.git branch

echo To update the MAIN mirror:
echo git -C /b/MAIN/src.git remote update


