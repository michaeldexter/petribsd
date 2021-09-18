#!/bin/sh

# Copyright 2021 Michael Dexter. All rights reserved

echo Importing lib_occambsd.sh library
[ -f ./lib_occambsd.sh ] || { echo lib_occambsd.sh not found ; exit 1 ; }
. ./lib_occambsd.sh || { echo lib_occambsd.sh failed to source ; exit 1 ; }

while getopts p:b: opts ; do
	case $opts in
	p)
		pool=$OPTARG
		zpool get -H name $pool > /dev/null 2>&1 || \
			{ echo zpool $pool not found ; exit 1 ; }
		;;
	b)
		branch=$OPTARG
		;;
	esac
done

[ $pool ] || { echo zpool not specified with -p ; exit 1 ; }
[ $branch ] || { echo branch not specified with -b ; exit 1 ; }

zpool get name $pool > /dev/null 2>&1 || \
	{ echo zpool $pool not found ; exit 1 ; }

# Variables that could be command line flags
with_occam=1
num_builds=10
#branch=""
golden_image="gi-${branch}"
git_server="file:///$build_root/MAIN/src.git" # Varify that it works local/remote
buildjobs="$(sysctl -n hw.ncpu)"	# Calculated
build_root="/b"				# -B build_root
work_dir="$build_root/$branch"		# Calculated
src_dir="$work_dir/src"			# Hard-coded
obj_dir="$work_dir/obj"			# Hard-coded
root_dir="$work_dir/gi-root"		# Hard-coded
kern_conf="OCCAMBSD"

enabled_options="WITHOUT_AUTO_OBJ WITHOUT_UNIFIED_OBJDIR WITHOUT_INSTALLLIB WITHOUT_BOOT WITHOUT_LOADER_LUA WITHOUT_LOCALES WITHOUT_ZONEINFO WITHOUT_EFI WITHOUT_VI WITHOUT_LOADER_ZFS WITHOUT_ZFS WITHOUT_CDDL WITHOUT_CRYPT WITHOUT_OPENSSL"

# ZFS: WITHOUT_LOADER_ZFS WITHOUT_ZFS WITHOUT_CDDL WITHOUT_CRYPT WITHOUT_OPENSSL
# WITHOUT_RADIUS_SUPPORT for static builds, fails on cddl ctfdump

# Directory layout, source checkout, and KERCONF are all handled by prep scripts

[ -d $src_dir/.git ] || { echo $src_dir missing! ; exit 1 ; }
[ -d $obj_dir ] || { echo $obj_dir missing! ; exit 1 ; }
[ -d $root_dir ] || { echo $root_dir missing! ; exit 1 ; }

echo ; echo Cleaning up logs directory
# Is there any reason for a logs dataset which would allow rollback?
[ -d $work_dir/logs ] && rm -rf $work_dir/logs
[ -d $work_dir/logs ] || mkdir -p $work_dir/logs
[ -d $work_dir/logs ] || mkdir $work_dir/logs

echo Rolling back source and work datasets
zfs rollback -r $pool$work_dir/src@cloned || \
	{ echo src rollback failed ; exit 1 ; }


zpool get -H name $golden_image > /dev/null 2>&1 || \
	{ echo $golden_image zpool missing! Run prep script ; exit 1 ; }

# "To completely roll back a recursive snapshot, you must roll back the individual child snapshots."

# Roll back the object (and other?) datasets
zfs list -t snap -H -o name | grep $work_dir | grep empty \
        | xargs -n1 zfs rollback -R


zfs list -t snap -H -o name | grep $golden_image | grep -v empty \
	| xargs -n1 zfs destroy

zfs list -t snap -H -o name | grep $golden_image | grep empty \
	| xargs -n1 zfs rollback -R

#echo ; zfs list -t snap |grep $work_dir
#echo ; echo Have we achieved cloned, empty, and no pNs?
#read foo


echo Initializing Git repo in $root_dir
git -C $root_dir init -b main
#git -C $root_dir config --global user.email "mando@razercrest.com"
git -C $root_dir config user.email "mando@razercrest.com"
#git -C $root_dir config --global user.name "Mando"
git -C $root_dir config user.name "Mando"


if [ "$with_occam" = 1 ] ; then

	echo Copying in OCCAMBSD KERNCONF
	cp OCCAMBSD $work_dir/ || { echo OCCAMBSD copy failed ; exit 1 ; }

	echo Generating $work_dir/src.conf with f_occam_options

	f_occam_options $src_dir "$enabled_options" > $work_dir/src.conf
else
	echo > $work_dir/src.conf
fi

# Removed from the individual make commands

echo "WITHOUT_CLEAN=YES" >> $work_dir/src.conf
echo "WITH_REPRODUCIBLE_BUILD=YES" >> $work_dir/src.conf


#cat $work_dir/src.conf
#echo look good? ; read foo


echo Loading filemon kernel module for use with meta mode
kldstat | grep -q filemon || kldload filemon || \
	{ echo filemon kernel module load failed ; exit 1 ; }


echo ; echo --------- ENTERING MAIN LOOP -------- ; echo

echo --------------------------------------------------------------

build_count=1

# How will this behave with a missing description or a tab in the description?
IFS="	"
#cat $work_dir/src.log | while IFS="  " read _count _epoch _hash _summary ; do
cat $work_dir/src.log | while read _count _epoch _hash _summary ; do

	touch_date=$( date -r $_epoch -j +%Y-%m-%dT%H:%M:%S )

	echo Commit: $_count
	echo Epoch Date: $_epoch
	echo Touch Date: $touch_date
	echo Hash: $_hash
	echo Summary: "$_summary"

	# Use the epoch time from the first commit for reproducible builds
# WHAT EXACTLY DOES THIS DO IN A REPRODUCIBLE BUILD?
	if [ "$build_count" = "1" ] ; then
		echo Using the epoch date of the first commit for the reproducible builds
		start_epoch=$_epoch
	fi


# Put in single quotes, and it does not evalauate, yet eval still does not like
	git_checkout_string="/usr/local/bin/git -C $src_dir checkout $_hash"

# TRY WITH = but no env
	buildworld_string="env WITH_META_MODE=YES \
		env MAKEOBJDIRPREFIX=$obj_dir \
		env SOURCE_DATE_EPOCH=$start_epoch env BUILD_UTC=$start_epoch \
		make -C $src_dir -j$buildjobs buildworld \
		SRCCONF=$work_dir/src.conf"

	buildkernel_string="env WITH_META_MODE=YES \
		env MAKEOBJDIRPREFIX=$obj_dir \
		env SOURCE_DATE_EPOCH=$start_epoch env BUILD_UTC=$start_epoch \
		make -C $src_dir -j$buildjobs buildkernel \
		SRCCONF=$work_dir/src.conf \
		KERNCONFDIR=$work_dir KERNCONF=OCCAMBSD"

	installworld_string="env WITH_META_MODE=YES \
		env INSTALL_CMD=\"install -p\" \
		env MAKEOBJDIRPREFIX=$obj_dir \
		env SOURCE_DATE_EPOCH=$start_epoch env BUILD_UTC=$start_epoch \
		make -C $src_dir installworld \
		SRCCONF=$work_dir/src.conf \
		DESTDIR=$root_dir"

	installkernel_string="env WITH_META_MODE=YES \
		env INSTALL_CMD=\"install -p\" \
		env MAKEOBJDIRPREFIX=$obj_dir \
		env SOURCE_DATE_EPOCH=$start_epoch env BUILD_UTC=$start_epoch \
		make -C $src_dir installkernel \
		SRCCONF=$work_dir/src.conf \
		KERNCONFDIR=$work_dir KERNCONF=OCCAMBSD \
		DESTDIR=$root_dir"

	distribution_string="env WITH_META_MODE=YES \
		env INSTALL_CMD=\"install -p\" \
		env MAKEOBJDIRPREFIX=$obj_dir \
		env SOURCE_DATE_EPOCH=$start_epoch env BUILD_UTC=$start_epoch \
		make -C $src_dir distribution \
		SRCCONF=$work_dir/src.conf \
		DESTDIR=$root_dir"

	release_string="env INSTALL_CMD=\"install -p\" \
		env MAKEOBJDIRPREFIX=$obj_dir \
		env SOURCE_DATE_EPOCH=$start_epoch env BUILD_UTC=$start_epoch \
		KERNCONFDIR=$work_dir KERNCONF=OCCAMBSD \
		make -C $src_dir/release release \
		SRCCONF=$work_dir/src.conf"

	vmimage_string="env INSTALL_CMD=\"install -p\" \
		env MAKEOBJDIRPREFIX=$obj_dir \
		env SOURCE_DATE_EPOCH=$start_epoch env BUILD_UTC=$start_epoch \
		make -C $src_dir/release vm-image \
		WITH_VMIMAGES=yes VMFORMATS=raw \
		KERNCONFDIR=$work_dir KERNCONF=OCCAMBSD \
		SRCCONF=$work_dir/src.conf \
		DESTDIR=$root_dir"

#	echo ; echo Exporting build scripts to $work_dir/logs/
	echo $git_checkout_string > $work_dir/logs/git_checkout-p$_count.sh
	echo $buildworld_string > $work_dir/logs/buildworld-p$_count.sh
	echo $buildkernel_string > $work_dir/logs/buildkernel-p$_count.sh
	echo $installworld_string > $work_dir/logs/installworld-p$_count.sh
	echo $installkernel_string > $work_dir/logs/installkernel-p$_count.sh
	echo $distribution_string > $work_dir/logs/distribution-p$_count.sh
	echo $release_string > $work_dir/logs/release-p$_count.sh
	echo $vmimage_string > $work_dir/logs/vmimage-p$_count.sh

	echo Checking out sources with
	echo $git_checkout_string ; echo
	echo Logging to $work_dir/logs/log-git-checkout-p$_count

# This dance appears to be necessary inside the loop
# Note that the p$ and .sh allow for no parens

#	\time -h eval $git_checkout_string \
#	\time -h echo $git_checkout_string | sh \
	\time -h sh $work_dir/logs/git_checkout-p$_count.sh \
		> $work_dir/logs/log-git-checkout-p$_count 2>&1 || \
		{ echo git checkout failed ; exit 1 ; }


# newvers.sh and bsdinstall manging would take place here...
# kernel env BRANCH_OVERRIDE=${BRANCH}${upd_rev_string}${build_name}"
# 14.0-HEAD-266586

# This is a workaround for the fact taht chown is symlinked between
# two directories, should they be datasets
#mv $work_dir/src/usr.sbin/chown/Makefile \
#	$work_dir/src/usr.sbin/chown/Makefile.bak

#sed -e '/^LINK/ s/./#&/' $work_dir/src/usr.sbin/chown/Makefile.bak \
#        > $work_dir/src/usr.sbin/chown/Makefile


	echo Building p$_count world with ; echo
	echo $buildworld_string
	echo Logging to $work_dir/logs/log-buildworld-p$_count ; echo

#	\time -h echo $buildworld_string | sh \
	\time -h sh $work_dir/logs/buildworld-p$_count.sh \
		> $work_dir/logs/log-buildworld-p$_count 2>&1

	if [ $? -ne 0 ] ; then
	echo "$_count	$_epoch	$_hash	buildworld_failed	"$_summary"" \
		>> $work_dir/logs/build.log
		echo p$_count buildworld failed!
		continue
# return 1
	fi

echo ; tail -5 $work_dir/logs/log-buildworld-p$_count ; echo
echo --------------------------------------------------------------


	echo Building p$_count kernel with ; echo
	echo $buildkernel_string ; echo
	echo Logging to $work_dir/logs/log-buildkernel-p$_count

#	\time -h echo $buildkernel_string | sh \
	\time -h sh $work_dir/logs/buildkernel-p$_count.sh \
		> $work_dir/logs/log-buildkernel-p$_count 2>&1

	if [ $? -ne 0 ] ; then
	echo "$_count	$_epoch	$_hash	buildkernel_failed	"$_summary"" \
		>> $work_dir/logs/build.log
		echo p$_count buildkernel failed!
		continue
	fi


echo Reproducible Build smoke test - generating sha512 for the kernel

sha512 -q $work_dir/obj$work_dir/src/amd64.amd64/sys/OCCAMBSD/kernel > \
	$work_dir/logs/log-kernel-sha512-p$_count || \
	{ echo kernel checksum generation failed ; exit 1 ; }

echo ; tail -6 $work_dir/logs/log-buildkernel-p$_count ; echo
echo --------------------------------------------------------------


	echo Installing world with ; echo
	echo $installworld_string ; echo
	echo Logging to $work_dir/logs/log-installworld-p$_count

#	\time -h echo $installworld_string | sh \
	\time -h sh $work_dir/logs/installworld-p$_count.sh \
		> $work_dir/logs/log-installworld-p$_count 2>&1

	if [ $? -ne 0 ] ; then
	echo "$_count	$_epoch	$_hash	installworld_failed	"$_summary"" \
		>> $work_dir/logs/build.log
		echo p$_count installworld failed!
		continue
	fi

	zfs snap $golden_image/ROOT/default@installworld-p$_count

echo ; tail -6 $work_dir/logs/log-installworld-p$_count ; echo
echo --------------------------------------------------------------


	echo Installing kernel with ; echo
	echo $installkernel_string ; echo
	echo Logging to $work_dir/logs/log-installkernel-p$_count

#	\time -h echo $installkernel_string | sh \
	\time -h sh $work_dir/logs/installkernel-p$_count.sh \
		> $work_dir/logs/log-installkernel-p$_count 2>&1

#	[ -f $work_dir/root/boot/kernel/kernel ] || \
#		{ echo Kernel not found! ; exit 1 ; }

# release and vmimage steps for the first build
	if [ $? -ne 0 ] ; then

	echo "$_count	$_epoch	$_hash	installkernel_failed	"$_summary"" \
		>> $work_dir/logs/build.log
		echo p$_count installkernel failed!
		continue
	fi

	zfs snap $golden_image/ROOT/default@installkernel-p$_count

echo ; tail -6 $work_dir/logs/log-installkernel-p$_count ; echo
echo --------------------------------------------------------------


	echo making distribution with ; echo
	echo $distribution_string ; echo
	echo Logging to $work_dir/logs/log-distribution-p$_count

#	\time -h echo $distribution_string | sh \
	\time -h sh $work_dir/logs/distribution-p$_count.sh \
		> $work_dir/logs/log-distribution-p$_count 2>&1

	if [ $? -ne 0 ] ; then
	echo "$_count	$_epoch	$_hash	distribution_failed "$_summary"" \
		>> $work_dir/logs/build.log
		echo p$_count distribution failed!
		continue
	fi

# Only for first run?
	zfs snap $golden_image/ROOT/default@distribution-p$_count

echo ; tail -6 $work_dir/logs/log-distribution-p$_count ; echo
echo --------------------------------------------------------------

#	if [ "$with_occam" = 1 ] ; then

	# Insert post-distribution OccamBSD adjustments here

#	fi # End if with_occam

# snap @distribution now rather than above?

        if [ "$build_count" = "1" ] ; then

		echo Adding all first build files to date to the Git repo
		git -C $root_dir add --all

                echo making release with ; echo
		echo $release_string ; echo
                echo Logging to $work_dir/logs/log-release-p$_count

echo DEBUG SKIPPING MAKE RELEASE
#		echo \time -h echo $release_string | sh \
		echo \time -h sh $work_dir/logs/release-p$_count.sh \
        	        > $work_dir/logs/log-release-p$_count 2>&1
                if [ $? -ne 0 ] ; then
                echo "$_count   $_epoch $_hash  release_failed "$_summary"" \
                        >> $work_dir/logs/build.log
                        echo p$_count release failed!
                        continue
                fi
        echo ; tail -6 $work_dir/logs/log-release-p$_count ; echo
	echo --------------------------------------------------------------


		echo making vmimage with ; echo
		echo $vmimage_string ; echo
		echo Logging to $work_dir/logs/log-vmimage-p$_count

echo DEBUG SKIPPING VM-IMAGE
#		echo \time -h echo $vmimage_string | sh \
		echo \time -h sh $work_dir/logs/vmimage-p$_count.sh \
			> $work_dir/logs/log-vmimage-p$_count 2>&1
		if [ $? -ne 0 ] ; then
		echo "$_count	$_epoch	$_hash	vmimage_failed	"$_summary"" \
			>> $work_dir/logs/build.log
			echo p$_count vmimage failed!
			continue
		fi

	echo ; tail -6 $work_dir/logs/log-vmimage-p$_count ; echo
	echo --------------------------------------------------------------

echo all builds succeeded! Logging to $work_dir/logs/build.log
echo "$_count   $_epoch $_hash  builds_succeeded  "$_summary"" \
	>> $work_dir/logs/build.log

# INCLUDING THESE IN THE FIRST RUN AS THEY SHOULD PERSIST

# Golden Image RE zone

# Note that the installation VM has a different pool name
#zpool set cachefile=$root_dir/boot/zfs/zpool.cache $golden_image || \
#        { echo zpool set cachefile failed ; exit 1 ; }

# REMEMBER: > first >> second
echo Enabling cryptodev module that ZFS barked about or will maybe autoload
echo "cryptodev_load=\"YES\"" > $root_dir/boot/loader.conf || \
        { echo cryptodev_load failed ; exit 1 ; }

echo Enabling zfs module
echo "zfs_load=\"YES\"" >> $root_dir/boot/loader.conf || \
        { echo zfs_load failed ; exit 1 ; }

echo Enabling verbose boot
echo "boot_verbose=\"YES\"" >> $root_dir/boot/loader.conf || \
        { echo boot_verbose failed ; exit 1 ; }

echo Shorteing boot time to three seconds
echo "autoboot_delay=\"3\"" >> $root_dir/boot/loader.conf || \
	{ echo autoboot_delay failed ; exit 1 ; }

echo Enabling zfs service, if you can call it that
echo "zfs_enable=\"YES\"" > $root_dir/etc/rc.conf || \
        { echo zfs_enable failed ; exit 1 ; }

echo Setting hostname
echo "hostname=\"occambsd\"" >> $root_dir/etc/rc.conf

echo Touching an fstab
touch $root_dir/etc/fstab

echo Setting timezone to UTC
tzsetup -s -C $root_dir UTC || \
	{ echo tzsetup failed ; exit 1 ; }

echo Disabling nearly everything else in rc.conf
cat rc.conf.disable_all.sh >> $root_dir/etc/rc.conf || \
	{ echo rc.conf.disble_all failed ; exit 1 ; }

# NOTE THAT IT IS A TERRIBLE IDEA TO HAVE THE SAME ENTROPY IN ALL INSTALLATIONS
		echo Initializing entropy
		umask 077
		for i in /entropy /boot/entropy; do
			i="$root_dir/$i"
			dd if=/dev/random of="$i" bs=4096 count=1
			chown 0:0 "$i"
		done

	fi # End extra steps for the first build

# KLUGE ZONE WITH SEPARATE /usr/bin and /usr/sbin datasets

# Have a test?
#	cp $root_dir/usr/sbin/chown $root_dir/usr/bin/chgrp || \
#		{ echo /usr/sbin/chown /usr/bin/chgrp copy failed ; exit 1 ; }

# KLUGE WARNING! Disabling sticky bits to allow touch to work!
# Correct would be to unset and reset them!

	echo Performing chflags kluge for recursive datestamp touch
	chflags -R 0 $root_dir

	if [ "$build_count" = "1" ] ; then
		echo Setting $root_dir atime/mtime to $touch_date
		find $root_dir  -exec touch -d $touch_date {} +
	fi 

# If we do not unset and reset sticky bits...

#touch: /b/13-MFM/gi-root/usr/bin/opieinfo: Operation not permitted
#touch: /b/13-MFM/gi-root/usr/bin/crontab: Operation not permitted
#touch: /b/13-MFM/gi-root/usr/bin/chfn: Operation not permitted
#touch: /b/13-MFM/gi-root/usr/bin/su: Operation not permitted
#touch: /b/13-MFM/gi-root/usr/bin/chsh: Operation not permitted
#touch: /b/13-MFM/gi-root/usr/bin/chpass: Operation not permitted
#touch: /b/13-MFM/gi-root/usr/bin/passwd: Operation not permitted
#touch: /b/13-MFM/gi-root/usr/bin/opiepasswd: Operation not permitted
#touch: /b/13-MFM/gi-root/usr/lib/librt.so: Operation not permitted
#touch: /b/13-MFM/gi-root/usr/lib/librt.so.1: Operation not permitted
#touch: /b/13-MFM/gi-root/usr/lib/libpthread.so: Operation not permitted
#touch: /b/13-MFM/gi-root/usr/lib/libthr.so: Operation not permitted
#touch: /b/13-MFM/gi-root/usr/lib/libcrypt.so: Operation not permitted
#touch: /b/13-MFM/gi-root/usr/libexec/ld-elf.so.1: Operation not permitted
#touch: /b/13-MFM/gi-root/sbin/init: Operation not permitted
#touch: /b/13-MFM/gi-root/lib/libc.so.7: Operation not permitted
#touch: /b/13-MFM/gi-root/lib/libcrypt.so.5: Operation not permitted
#touch: /b/13-MFM/gi-root/lib/libthr.so.3: Operation not permitted
#touch: /b/13-MFM/gi-root/libexec/ld-elf.so.1: Operation not permitted
#touch: /b/13-MFM/gi-root/var/empty: Operation not permitted

if [ $( zfs get name $golden_image/ROOT/default/up > /dev/null 2>&1 ) ] ; then
	echo Setting the immutable up managed datasets to readonly=on
	zfs set readonly=on $golden_image/ROOT/default/up
fi

	echo Snapshotting the p$_count root dataset with
	echo zfs snap -r $golden_image/ROOT/default@p$_count
	zfs snap -r $golden_image/ROOT/default@p$_count || \
		{ echo p$_count snapshot failed ; exit 1 ; }

if [ $( zfs get name $golden_image/ROOT/default/up > /dev/null 2>&1 ) ] ; then
	# Want it in readonly=off state for the next cycle to succeed
	echo Setting the immutable up datasets to readonly=off
	zfs set readonly=off $golden_image/ROOT/default/up

	zfs get readonly | grep $golden_image
	echo Did that work? ; sleep 5
	# If that fails, the next installworld will fail
fi

	build_count=$(( $build_count + 1 ))
	[ $build_count = $num_builds ] && exit 0
done

exit 0
