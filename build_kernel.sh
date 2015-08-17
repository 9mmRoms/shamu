#!/bin/bash

###############################################################################
# To all DEV around the world :)                                              #
# to build this kernel you need to be ROOT and to have bash as script loader  #
# do this:                                                                    #
# cd /bin                                                                     #
# rm -f sh                                                                    #
# ln -s bash sh                                                               #
# now go back to kernel folder and run:                                       # 
#                                                         		      #
# sh clean_kernel.sh                                                          #
#                                                                             #
# Now you can build my kernel.                                                #
# using bash will make your life easy. so it's best that way.                 #
# Have fun and update me if something nice can be added to my source.         #
###############################################################################

# Time of build startup
res1=$(date +%s.%N)

echo "${bldcya}***** Setting up Environment *****${txtrst}";

. ./env_setup.sh ${1} || exit 1;


# Generate Ramdisk
echo "${bldcya}***** Generating Ramdisk *****${txtrst}"
echo "0" > $TMPFILE;


build_initramfs() {
	# remove previous initramfs files
	if [ -d $INITRAMFS_TMP ]; then
		echo "${bldcya}***** Removing old temp initramfs_source *****${txtrst}";
		rm -rf $INITRAMFS_TMP;
	fi;

	mkdir -p $INITRAMFS_TMP;
	cp -ax $INITRAMFS_SOURCE/* $INITRAMFS_TMP;
	# clear git repository from tmp-initramfs
	if [ -d $INITRAMFS_TMP/.git ]; then
		rm -rf $INITRAMFS_TMP/.git;
	fi;
	
	# remove empty directory placeholders from tmp-initramfs
	find $INITRAMFS_TMP -name EMPTY_DIRECTORY | parallel rm -rf {};

	# remove more from from tmp-initramfs ...
	rm -f $INITRAMFS_TMP/update* >> /dev/null;

	if [ $1 == 'AOSP' ]; then
		cp -f $INITRAMFS_TMP/aosp/* $INITRAMFS_TMP/
	fi;
	rm -rf $INITRAMFS_TMP/aosp

	./utilities/mkbootfs $INITRAMFS_TMP | gzip > ramdisk-$1.gz

}

(
	rm -f $KERNELDIR/ramdisk* >> /dev/null;
	build_initramfs CM
	if [ -d $INITRAMFS_SOURCE/aosp ]; then
		build_initramfs AOSP
	fi;
	echo "1" > $TMPFILE;
	echo "${bldcya}***** Ramdisk Generation Completed Successfully *****${txtrst}"
)&

if [ ! -f $KERNELDIR/.config ]; then
	echo "${bldcya}***** Clean Build Initiating *****${txtrst}";
	cp $KERNELDIR/arch/arm/configs/$KERNEL_CONFIG .config;
	make $KERNEL_CONFIG;
else
	echo "${bldcya}***** Dirty Build Initiating *****${txtrst}";	
	# remove previous files which should regenerate
	rm -f $KERNELDIR/arch/arm/boot/*.dtb >> /dev/null;
	rm -f $KERNELDIR/arch/arm/boot/*.cmd >> /dev/null;
	rm -f $KERNELDIR/arch/arm/boot/zImage >> /dev/null;
	rm -f $KERNELDIR/arch/arm/boot/zImage-dtb >> /dev/null;
	rm -f $KERNELDIR/arch/arm/boot/Image >> /dev/null;
	rm -f $KERNELDIR/zImage >> /dev/null;
	rm -f $KERNELDIR/zImage-dtb >> /dev/null;
	rm -f $KERNELDIR/boot.img >> /dev/null;
	rm -rf $KERNELDIR/out/temp >> /dev/null;
	rm -rf $KERNELDIR/out/boot >> /dev/null;
fi;

. $KERNELDIR/.config
GETVER=`grep 'Hydra-Kernel_v.*' $KERNELDIR/.config | sed 's/.*_.//g' | sed 's/".*//g'`
echo "${bldcya}Building => Hydra ${GETVER} ${txtrst}";

# wait for the successful ramdisk generation
while [ $(cat ${TMPFILE}) == 0 ]; do
	echo "${bldblu}Waiting for Ramdisk generation completion.${txtrst}";
	sleep 3;
done;

# make zImage
echo "${bldcya}***** Compiling kernel *****${txtrst}"
if [ $USER != "root" ]; then
	make -j$NUMBEROFCPUS zImage-dtb
else
	nice -n -15 make -j$NUMBEROFCPUS zImage-dtb
fi;

mkdir -p $KERNELDIR/out/boot;

finalize_build() {
	# copy all needed to out kernel folder
	./utilities/mkbootimg --kernel zImage-dtb --cmdline 'console=ttyHSL0,115200,n8 androidboot.console=ttyHSL0 androidboot.hardware=shamu msm_rtb.filter=0x37 ehci-hcd.park=3 utags.blkdev=/dev/block/platform/msm_sdcc.1/by-name/utags utags.backup=/dev/block/platform/msm_sdcc.1/by-name/utagsBackup coherent_pool=8M androidboot.selinux=permissive sched_enable_hmp=1' --base 0x00000000 --pagesize 2048 --ramdisk_offset 0x02000000 --tags_offset 0x01E00000 --ramdisk ramdisk-$1.gz --output boot-$1.img

	rm -f $KERNELDIR/out/boot.img >> /dev/null;
	rm -f $KERNELDIR/out/boot/boot-$1.img >> /dev/null;
	cp $KERNELDIR/boot-$1.img /$KERNELDIR/out/boot/
}

if [ -e $KERNELDIR/arch/arm/boot/zImage-dtb ]; then
	echo "${bldcya}***** Final Touch for Kernel *****${txtrst}"
	cp $KERNELDIR/arch/arm/boot/zImage-dtb $KERNELDIR/zImage-dtb;
	rm -f $KERNELDIR/out/Hydra_* >> /dev/null;
	
	finalize_build CM

	if [ -e $KERNELDIR/ramdisk-AOSP.gz ]; then	
		finalize_build AOSP
	fi;

	cd $KERNELDIR/out/
	zip -r Hydra_v${GETVER}-`date +"[%m-%d]-[%H-%M]"`.zip .
	echo "${bldcya}***** Ready to Roar *****${txtrst}";
	# finished? get elapsed time
	res2=$(date +%s.%N)
	echo "${bldgrn}Total time elapsed: ${txtrst}${grn}$(echo "($res2 - $res1) / 60"|bc ) minutes ($(echo "$res2 - $res1"|bc ) seconds) ${txtrst}";	
	while [ "$push_ok" != "y" ] && [ "$push_ok" != "n" ] && [ "$push_ok" != "Y" ] && [ "$push_ok" != "N" ]
	do
	      read -p "${bldblu}Do you want to push the kernel to the sdcard of your device?${txtrst}${blu} (y/n)${txtrst}" push_ok;
		sleep 1;
	done
	if [ "$push_ok" == "y" ] || [ "$push_ok" == "Y" ]; then
		STATUS=`adb get-state` >> /dev/null;
		while [ "$ADB_STATUS" != "device" ]
		do
			sleep 1;
			ADB_STATUS=`adb get-state` >> /dev/null;
		done
		adb push $KERNELDIR/out/Hydra_v*.zip /sdcard/
		while [ "$reboot_recovery" != "y" ] && [ "$reboot_recovery" != "n" ] && [ "$reboot_recovery" != "Y" ] && [ "$reboot_recovery" != "N" ]
		do
			read -p "${bldblu}Reboot to recovery?${txtrst}${blu} (y/n)${txtrst}" reboot_recovery;
			sleep 1;
		done
		if [ "$reboot_recovery" == "y" ] || [ "$reboot_recovery" == "Y" ]; then
			adb reboot recovery;
		fi;
	fi;
	exit 0;
else
	echo "${bldred}Kernel STUCK in BUILD!${txtrst}"
fi;
