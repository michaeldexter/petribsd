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
golden_image="gi-${branch}"
vm_image="vm-${branch}"
vm_root_dir="$build_root/$branch/vm-root"

# THIS ASSUMES YOU JUST CREATED THE BASIC LAYOUT
# MEGA ANNOYING ISSUE... WE NEED SOME NESTED DATASETS TO BOOT
# TERRIBLE THOUGHT: Have a skeleton of them and overmount them

# MOVED to the end becuase the zfs send will overwrite anything we d


zpool get name $vm_image > /dev/null 2>&1 || \
	{ echo zpool $vm_image not found ; exit 1 ; }

# The install source
zpool get name $golden_image > /dev/null 2>&1 || \
        { echo zpool $golden_image not found ; exit 1 ; }

# Truly needed?
echo Unmounting $vm_image/ROOT/default with zfs umount -f $vm_image/ROOT/default
# Add a test or do not fail
zfs umount -f $vm_image/ROOT/default #|| \
#	{ echo failed ; exit 1 ; }

# SIMPLY DESTROY and re-create $vm_image/ROOT/default ?

sleep 3
echo Rolling back $vm_image/ROOT/default and /up
# Test before running?
#zfs list -t snap -H -o name | grep $vm_image | grep empty \
zfs list -t snap -H -o name | grep $vm_image \
	| xargs -n1 zfs destroy -r
#	| xargs -n1 zfs rollback -R

# NB! golden image ROOT/default@N snapshots can begin at any number!

# Not that while the zfs list command gives newline-separated fields at the
# command line, the shell appears to collapse them to space-separated

snap_list=$( zfs list -t snap -H -o name grep $golden_image/ROOT/default )

first_snap=$( echo $snap_list | cut -d " " -f1 )
rev_snap_list=$( echo $snap_list | rev )
last_snap=$( echo $rev_snap_list | cut -d " " -f1 | rev )

echo Sending $first_snap replication stream to $vm_image/ROOT/default

# send -p ?
# -R only sent the first snapshot
zfs send -R $first_snap | \
	zfs recv -F $vm_image/ROOT/default || \
		{ echo $first_snap send failed ; exit 1 ; }

echo Sending the incremental snapshots
zfs send -I $first_snap $last_snap | \
	zfs recv $vm_image/ROOT/default || \
	{ echo $first_snap $last_snap incremental send failed ; exit 1 ; }



echo Exporting $vm_image
zpool export $vm_image || \
	{ echo failed ; exit 1 ; }

echo Reimporting $vm_image
zpool import -R $vm_root_dir $vm_image || \
	{ echo zpool import -R $vm_root_dir $vm_image failed ; exit 1 ; }
zfs mount $vm_image/ROOT/default || \
	{ echo mount $vm_image/ROOT/default failed ; exit 1 ; }


# BOOT CODE!

zfs list -t snap | grep $branch

# Needed?
#zfs mount -a
# AH! default is not mounting because canmount = noauto
#zfs mount $vm_image/ROOT/default
