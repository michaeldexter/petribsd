#!/bin/sh

branch="13-MFM"
upstream_branch="stable/13"           # -u?
entry_point_count=""
entry_point_date=""      
entry_point_hash=""
golden_image="gi-${branch}"
vm_image="vm-${branch}"
git_server="file:///b/MAIN/src.git"
build_root="/b"                          # -B build_root
work_dir="$build_root/$branch"           # Calculated
src_dir="$work_dir/src"                 # Hard-coded

if [ ! $1 ] ; then
	echo Enter the zpool name:
	read pool
else
	pool="$1"
fi

zpool get -H name $pool > /dev/null 2>&1 || \
	{ echo zpool $pool not found ; exit 1 ; }

# Would be smart, but not very separate, to clean up the GI and VM pools

echo Destroying $golden_image zpool if present
zpool get -H name $golden_image > /dev/null 2>&1 && \
	zpool export -f $golden_image
sleep 3
zpool get -H name $golden_image > /dev/null 2>&1 && \
	zpool destroy -f $golden_image

echo Destroying $vm_image zpool if present
zpool get -H name $vm_image > /dev/null 2>&1 && \
	zpool export -f $vm_image
sleep 3
zpool get -H name $vm_image > /dev/null 2>&1 && \
	zpool destroy -f $vm_image

# Moving all work_dir, src, and obj burdens to this step

echo Creating $pool$work_dir/src
zfs create -p $pool$work_dir/src || { echo zfs create src failed ; exit 1 ; }

echo Creating $pool$work_dir/obj
zfs create -p $pool$work_dir/obj || { echo zfs create obj failed ; exit 1 ; }

echo Cloning /b/MAIN/src.git to /b/$branch/src
git -C /b/$branch/ clone -b $upstream_branch $git_server || \
        { echo git clone failed ; exit 1 ; }

echo Listing the branch
git -C /b/$branch/src branch

#echo So far so good? ; read foo

echo Snapshotting /b/$branch/src@cloned dataset
zfs snap $pool/b/$branch/src@cloned || \
        { echo zfs snapshot src failed ; exit 1 ; }

echo Snapshotting /b/$branch/obj@empty dataset
zfs snap $pool/b/$branch/obj@empty || \
	{ echo zfs snapshot obj failed ; exit 1 ; }
