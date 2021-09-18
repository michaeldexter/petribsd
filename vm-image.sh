#!/bin/sh

while getopts b: opts ; do
	case $opts in
	b)
		branch=$OPTARG
		;;
	esac
done

[ $branch ] || { echo branch not specified with -b ; exit 1 ; }

build_root="/b"
vm_image="vm-${branch}"
vm_root_dir="$build_root/$branch/vm-root"

echo Destroying $vm_image zpool if present
zpool get -H name $vm_image > /dev/null 2>&1 && \
	zpool export -f $vm_image
sleep 3
zpool get -H name $vm_image > /dev/null 2>&1 && \
	zpool destroy -f $vm_image

zpool list
#echo Gone? ; read foo

echo FYI destroying /dev/ggate1
[ -e /dev/ggate1 ] && ggatel destroy -f -u 1
echo FYI destroying /dev/ggate1%
[ -e /dev/ggate1% ] && ggatel destroy -f -u 1

[ -f /b/$branch/$vm_image.img ] && rm /b/$branch/$vm_image.img

echo Truncating $vm_image.img
truncate -s 10G /b/$branch/$vm_image.img || { echo truncate failed ; exit 1 ; }

echo Attaching $vm_image.img
ggatel create -u 1 /b/$branch/$vm_image.img
ggatel list

echo Making $vm_root_dir mountpoint directory
[ -d $vm_root_dir ] || mkdir $vm_root_dir || \
	{ echo make vm mountpoint $vm_root_dir failed ; exit 1 ; }

# ADDING PARTITIONING WHICH MAY BE NEEDED FOR ZFS BOOTING

echo Partitioning /dev/ggate1 with GPT layout
gpart create -s gpt /dev/ggate1 || { echo gpart create failed ; exit 1 ; }
gpart add -a 4k -s 512k -t freebsd-boot /dev/ggate1 || \
	{ echo gpart add freebsd-boot failed ; exit 1 ; }

# ADDING BOOT CODE NEEDS TO BE IN THE INSTALL SCRIPT BECAUSE WE HAVE NO BINARIES
#gpart bootcode -b $vm_root_dir/boot/pmbr \
#	-p $vm_root_dir/boot/gptzfsboot -i 1 /dev/ggate1

gpart add -a 1m -t freebsd-zfs /dev/ggate1
# -l label ...

echo Showing the partition table

gpart show /dev/ggate1

#echo Look good? ; read foo

# -R Equivalent to -o cachefile=none -o altroot=root
#zpool create -o altroot=$vm_root_dir -O compress=lz4 -O atime=off \

# !!! Adding p2 for ZFS
# removing atime to diagnose boot issues
#zpool create -O compress=lz4 -O atime=off -R $vm_root_dir \
zpool create -O compress=lz4 -R $vm_root_dir \
	-m none $vm_image /dev/ggate1p2 || \
	{ echo zpool create failed ; exit 1 ; }

zpool list

#echo Look good? ; read foo

echo Creating default datasets

zfs create -o mountpoint=none $vm_image/ROOT \
	|| { echo zfs create failed ; exit 1 ; }
zfs create -o mountpoint=/ $vm_image/ROOT/default \
	|| { echo zfs create failed ; exit 1 ; }

zpool set bootfs=$vm_image/ROOT/default $vm_image
# Will this fail because that dirctory does not exist yet?
# Or is it purely a soft attribute?
# '/b/13-MFM/vm-root/boot/zfs' is not a valid directory

zfs create -o mountpoint=/tmp -o exec=on -o setuid=off $vm_image/tmp
zfs create -o mountpoint=/usr -o canmount=off $vm_image/usr
zfs create -o mountpoint=/var -o canmount=off $vm_image/var
zfs create -o exec=off -o setuid=off $vm_image/var/audit
zfs create -o exec=off -o setuid=off $vm_image/var/crash
zfs create -o exec=off -o setuid=off $vm_image/var/log
zfs create -o atime=on $vm_image/var/mail
zfs create -o setuid=off $vm_image/var/tmp

# Is this intentionally later?
zfs set canmount=noauto $vm_image/ROOT/default
#zfs set mountpoint=/$vm_image $vm_image
#zfs create -o mountpoint=/pkg $vm_image/pkg
#zfs create $vm_image/usr/home
#zfs create -o setuid=off $vm_image/usr/ports
#zfs create $vm_image/usr/src

exit 0
