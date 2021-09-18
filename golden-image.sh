#!/bin/sh

default_layout=0
up_layout=0

while getopts p:b:du opts ; do
	case $opts in
	p)
		pool=$OPTARG
		zpool get -H name $pool > /dev/null 2>&1 || \
		        { echo zpool $pool not found ; exit 1 ; }
		;;
	b)
		branch=$OPTARG
		;;
	d)
		default_layout=1
		;;
	u)
		default_layout=1
		up_layout=1
		;;
	esac
done

[ $pool ] || { echo zpool not specified with -p ; exit 1 ; }
[ $branch ] || { echo branch not specified with -b ; exit 1 ; }

#branch=""
golden_image="gi-${branch}"
build_root="/b"
work_dir="$build_root/$branch"
root_dir="$work_dir/gi-root"

# UNWIND THE GOLDEN IMAGE POOL FIRST OR REGRET IT

echo Destroying $golden_image zpool if present
zpool get -H name $golden_image > /dev/null 2>&1 && \
        zpool export -f $golden_image
sleep 3
zpool get -H name $golden_image > /dev/null 2>&1 && \
        zpool destroy -f $golden_image

zpool list -H
#echo Gone? ; read foo

echo Destroying ggate0
[ -e /dev/ggate0 ] && ggatel destroy -f -u 0

ggatel list

#echo Gone? ; read foo

echo Removing $golden_image.img
if [ -f $work_dir/$golden_image.img ] ; then
	rm $work_dir/$golden_image.img || \
	{ echo rm $golden_image.img failed ; exit 1 ; }
fi

echo Making $root_dir mountpoint for $golden_image zpool
[ -d $root_dir ] || mkdir $root_dir || \
	{ echo mkdir $root_dir failed ; exit 1 ; }


# GOLDEN IMAGE CREATION STEPS

echo Truncating $golden_image.img
truncate -s 10G $work_dir/$golden_image.img || { echo truncate failed ; exit 1 ; }

echo Attaching $golden_image.img
ggatel create -u 0 $work_dir/$golden_image.img
ggatel list

# Note that the golden image does not have partitioning

# -R Equivalent to -o cachefile=none -o altroot=root
zpool create -o altroot=$root_dir -O compress=lz4 -O atime=off \
	-m none $golden_image /dev/ggate0 || \
	{ echo zpool create failed ; exit 1 ; }

zpool list -H

#echo Look good? ; read foo

echo Creating Default dataset

zfs create -o mountpoint=none $golden_image/ROOT || \
	{ echo zfs create failed ; exit 1 ; }
zfs create -o mountpoint=/ $golden_image/ROOT/default
zpool set bootfs=$golden_image/ROOT/default $golden_image
#zpool set cachefile=/mnt/boot/zfs/zpool.cache $golden_image

if [ $default_layout = 1 ] ; then
	echo Creating default FreeBSD datasets
	zfs create -o mountpoint=/tmp -o exec=on -o setuid=off $golden_image/tmp
	zfs create -o mountpoint=/usr -o canmount=off $golden_image/usr
	zfs create -o mountpoint=/var -o canmount=off $golden_image/var
	zfs create -o exec=off -o setuid=off $golden_image/var/audit
	zfs create -o exec=off -o setuid=off $golden_image/var/crash
	zfs create -o exec=off -o setuid=off $golden_image/var/log
	zfs create -o atime=on $golden_image/var/mail
	zfs create -o setuid=off $golden_image/var/tmp
fi

# Is this intentionally later?
zfs set canmount=noauto $golden_image/ROOT/default
#zfs set mountpoint=/$golden_image $golden_image
#zfs create -o mountpoint=/pkg $golden_image/pkg
#zfs create $golden_image/usr/home
#zfs create -o setuid=off $golden_image/usr/ports
#zfs create $golden_image/usr/src

if [ $up_layout = 1 ] ; then
	echo Creating additional up datasets

	zfs create -o mountpoint=none $golden_image/ROOT/default/up

# Removing the kernel because the loader will not support nesting
#	zfs create -o mountpoint=/boot/kernel -p \
#		$golden_image/ROOT/default/up/kernel || \
#		{ echo zfs create failed ; exit 1 ; }
	zfs create -o mountpoint=/bin -p \
		$golden_image/ROOT/default/up/bin
	zfs create -o mountpoint=/lib -p \
		$golden_image/ROOT/default/up/lib
	zfs create -o mountpoint=/libexec -p \
		$golden_image/ROOT/default/up/libexec
# Not including rescue as we might need a directory in default
#	zfs create -o mountpoint=/root/rescue -p \
#		$golden_image/ROOT/default/up/rescue
	zfs create -o mountpoint=/sbin -p \
		$golden_image/ROOT/default/up/sbin

	zfs create -o mountpoint=/usr/bin -p \
		$golden_image/ROOT/default/up/usr.bin \
		|| { echo zfs create failed ; exit 1 ; }
	zfs create -o mountpoint=/usr/lib -p \
		$golden_image/ROOT/default/up/usr.lib
	zfs create -o mountpoint=/usr/lib32 -p \
		$golden_image/ROOT/default/up/usr.lib32
	zfs create -o mountpoint=/usr/libdata -p \
		$golden_image/ROOT/default/up/usr.libdata
	zfs create -o mountpoint=/usr/libexec -p \
		$golden_image/ROOT/default/up/usr.libexec
	zfs create -o mountpoint=/usr/sbin -p \
		$golden_image/ROOT/default/up/usr.sbin
	zfs create -o mountpoint=/usr/share -p \
		$golden_image/ROOT/default/up/usr.share
	zfs create -o mountpoint=/usr/tests -p \
		$golden_image/ROOT/default/up/usr.tests \
		 || { echo zfs create failed ; exit 1 ; }
fi

echo Recursively snapshotting $golden_image/ROOT/default@empty
zfs snap -r $golden_image/ROOT/default@empty || \
	{ echo zfs snapshot failed ; exit 1 ; }

exit 0
