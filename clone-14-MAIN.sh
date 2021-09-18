#!/bin/sh

# TO DO: Push build_root variable down!

# NB! This tears down the whold branch dataset, golden and VM images included

git_server="file:///b/MAIN/src.git"
branch="14-MAIN"
upstream_branch="main"
git_branch="origin/$upstream_branch"
entry_point_count="262716"		#"Bump CURRENT to 14.0"
entry_point_date="1611274207"
entry_point_hash="a53ce3fc4938e37d5ec89304846203d2083c61a2"
golden_image="gi-${branch}"
vm_image="vm-${branch}"
build_root="/b"
work_dir="$build_root/$branch"
src_dir="$work_dir/src"

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

echo Destroy $pool$work_dir if present
# Not relying on rollback

if [ -d "$work_dir" ] ; then
	zfs destroy -r -f $pool$work_dir || \
		{ echo zfs destroy $work_dir failed ; exit 1 ; }
fi

echo Creating $pool$work_dir/src
zfs create -p $pool$work_dir/src || { echo zfs create src failed ; exit 1 ; }

echo Creating $pool$work_dir/obj
zfs create -p $pool$work_dir/obj || { echo zfs create obj failed ; exit 1 ; }

echo Cloning $build_root/MAIN/src.git to $build_root/$branch/src with
echo git -C $build_root/$branch/ clone -b $upstream_branch $git_server
git -C $build_root/$branch/ clone -b $upstream_branch $git_server || \
	{ echo git clone failed ; exit 1 ; }

echo Listing the branch
git -C $build_root/$branch/src branch

echo Look correct? ; read foo

echo Snapshotting $build_root/$branch/src@cloned dataset
zfs snap $pool$build_root/$branch/src@cloned || \
	{ echo zfs snapshot src failed ; exit 1 ; }

echo Snapshotting /$build_root/$branch/obj@empty dataset
zfs snap $pool$build_root/$branch/obj@empty || \
	{ echo zfs snapshot obj failed ; exit 1 ; }

#echo Setting entry point

#if [ $entry_point_count ] ; then
#	echo $entry_point_count > $work_dir/entry_point_count
#fi


echo Generating src.log.full
#	origin/stable/13 ^origin | nl -v 0 | sed 's/^ *//g' \
git -C $src_dir log --reverse --format="%at%x09%H%x09%s" \
	$git_branch | nl -v 0 | sed 's/^ *//g' > $work_dir/src.log.full

echo $work_dir/src.log.full lines:
wc -l $work_dir/src.log.full

echo SMOKE TEST: Original entry_point_count is $entry_point_count

echo Calculating branch entry point
# Decrement by one to start in the right place
entry_point_count=$(( $entry_point_count - 1 ))

echo SMOKE TEST: Revised entry_point_count is $entry_point_count

echo Decremented entry point count is $entry_point_count
awk -v var="$entry_point_count" 'NR>var' $work_dir/src.log.full > \
	$work_dir/src.log

echo $work_dir/src.log lines:
wc -l $work_dir/src.log

echo Look correct? ; read foo

echo Does this look like the correct start of the branch?
head -5 $work_dir/src.log
