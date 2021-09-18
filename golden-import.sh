#!/bin/sh

branch="13-MFM"
image="gi-${branch}"
build_root="/b"                         # -B build_root
work_dir="$build_root/$branch"          # Calculated
root_dir="$work_dir/gi-root"            # Hard-coded

# Note that ZFS will create the lowest directory of $gi-root on import
# Not sure about the parent ones


echo Attaching $image.img
ggatel create -u 0 $work_dir/$image.img
ggatel list


zpool import -R $root_dir -f $image
zfs mount $image/ROOT/default
zfs mount -a
