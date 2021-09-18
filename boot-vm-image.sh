#!/bin/sh

build_root="/b"

while getopts b: opts ; do
	case $opts in
		b)
			branch=$OPTARG
		;;
	esac
done

[ $branch ] || { echo branch not specified with -b ; exit 1 ; }

[ -f $build_root/$branch/vm-$branch.img ] || \
	{ echo $build_root/$branch/vm-$branch.img not found ; exit 1 ; }

echo Exporiting vm-$branch if imported
zpool get -H name vm-$branch > /dev/null 2>&1 && \
        zpool export -f vm-$branch

echo Destroying /dev/ggate1 if present
[ -e /dev/ggate1 ] && ggatel destroy -f -u 1

bhyveload -d $build_root/$branch/vm-$branch.img -m 1024 occambsd || \
	{ echo $build_root/$branch/vm-$branch.img failed to load ; exit 1 ; }

echo Sleeping 2 seconds... ; sleep 2

bhyve -m 1024 -H -A -s 0,hostbridge \
	-s 2,virtio-blk,$build_root/$branch/vm-$branch.img \
	-s 31,lpc -l com1,stdio occambsd

