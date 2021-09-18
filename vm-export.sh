#!/bin/sh

while getopts b: opts ; do
	case $opts in
	b)
		branch=$OPTARG
	;;
	esac
done

[ $branch ] || { echo branch not specified with -b ; exit 1 ; }

vm_image="vm-${branch}"

echo Exporting $vm_image zpool
zpool get -H name $vm_image && zpool export -f $vm_image 

echo
zpool list

#echo
#echo Is export $vm_image gone? ; read foo

echo FYI destroying /dev/ggate1
[ -e /dev/ggate1 ] && ggatel destroy -f -u 1

