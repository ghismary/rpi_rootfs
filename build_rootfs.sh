#!/bin/bash

#
function print_usage {
	echo "Usage: $0 command [options]"
	echo "  command: "
	echo "    download : download latest RaspiOS image"
	echo "    create [image file]: "
	echo "      [image file]: raspi OS image zip/img file"
	echo "    update : run apt update & full-upgrade & autoremove in rootfs"
	echo "    run [command]: run raspberry pi command in rootfs"
	echo "      [command]: should be escaped with double-quote and "
	echo "      command need to be full path of command "
	echo "      e.g. ./build_rootfs.sh run \"/usr/bin/apt -y install libpulse-dev\""
	echo "        - install libpulse-dev package in rootfs"
	echo "      e.g. ./build_rootfs.sh run \"/usr/bin/apt autoremove\""
	echo "        - run apt autoremove in rootfs"
	echo "    clean : removing rootfs"
}

# Global variables for this script
RPI_ROOTFS_BASE=./rootfs
IMAGEFILE_MOUNT_PATH=/mnt
IMAGE_MOUNTED=0
CHROOT_SYS_PATH_MOUNTED=0
QEMU_ARM_STATIC=/usr/bin/qemu-arm-static
RSYNC_OPTIONS="-hatr --delete --stats"
UPDATE_INSTALL_SCRIPT=update_upgrade_install_package.sh
CURRENT_WORKING_DIR=""

###############################################################################
#
#  Helper Functions
#
###############################################################################

function mount_chroot_syspath {
	sudo echo "Getting Sudo"
	sudo mount --bind /sys ${RPI_ROOTFS_BASE}/sys
	sudo mount --bind /proc ${RPI_ROOTFS_BASE}/proc
	sudo mount --bind /dev ${RPI_ROOTFS_BASE}/dev
	sudo mount --bind /dev/pts ${RPI_ROOTFS_BASE}/dev/pts
	# Setting mounted flag for cleanUp
	CHROOT_SYS_PATH_MOUNTED=1
}

function unmount_chroot_syspath {
	sudo umount ${RPI_ROOTFS_BASE}/sys
	sudo umount ${RPI_ROOTFS_BASE}/proc
	sudo umount ${RPI_ROOTFS_BASE}/dev/pts
	sudo umount ${RPI_ROOTFS_BASE}/dev
	# clear flag
	CHROOT_SYS_PATH_MOUNTED=0
}

function cleanUp {
	if [ ${IMAGE_MOUNTED} == 1 ]; then
		# umount before terminating this script
		echo "Unmounting ${IMAGEFILE_MOUNT_PATH}"
		sudo umount ${IMAGEFILE_MOUNT_PATH}
		# clear flag
		IMAGE_MOUNTED=0
	fi
	if [ ${CHROOT_SYS_PATH_MOUNTED} == 1 ]; then
		unmount_chroot_syspath
	fi
}

# this function will exist when the specified command is not found
function is_command_installed {
	local checking_command=$1
	if ! [ -x "$(command -v ${checking_command})" ]; then
		echo "Error: ${checking_command} command is not installed "
		echo "or could not found the command in PATH variable."
		exit 1
	fi
	return 0
}

#
function extract_zip_and_mount_image {
	local image_filename=$1
	local filename=$(basename -- "$image_filename")
	local extension="${filename##*.}"
	local filename_without_ext=$(echo "$filename" | cut -f 1 -d '.')
	local extracted_image_filename=${filename_without_ext}.img

	## Extracting RaspiOS image from zip file
	if [ ${extension} == "zip" ]; then
		# this unzip wll extract the OS image file on current directory
		unzip ${image_filename}
		ret_value=$?
		echo "Unzip Resutnr value : ${ret_value}"
		if [ ${ret_value} -ne 0 ]; then
			echo "Error: Failed to execute unzip ${image_filename}"
			exit 1
		fi
	elif [ ${extension} == "img" ]; then
		extracted_image_filename=${image_filename}
		echo "Using OS image file : ${extracted_image_filename}"
	else
		echo "Error: unsuppored RaspiOS image type ${image_filename}"
		exit 2
	fi

	## Extracting the mount offset of RaspiOS image
	if [ ! -e ${extracted_image_filename} ]; then
		echo "Raspi OS raw image file does not exist in current directory"
		exit 1
	fi

	local mount_offset=$(fdisk -l ${extracted_image_filename} | grep "Linux" | awk '{print $2 * 512}')
	sudo mount -o ro,loop,offset=${mount_offset} -t auto \
		${extracted_image_filename} ${IMAGEFILE_MOUNT_PATH}
	local ret_value=$?
	if [ ${ret_value} -ne 0 ]; then
		echo "Error: Failed to mount RaspiOS image  ${image_filename}"
		exit 3
	fi

	# mark image mounted global flag
	IMAGE_MOUNTED=1
	return 0
}

function copy_files_from_image {
	local USERID=$(id -un)
	local GROUPID=$(id -gn)
	(
		cd ${IMAGEFILE_MOUNT_PATH}
		sudo rsync ${RSYNC_OPTIONS} * ${CURRENT_WORKING_DIR}/${RPI_ROOTFS_BASE}
	)
	local ret_value=$?
	if [ ${ret_value} -ne 0 ]; then
		echo "Error: Failed to copy from RaspiOS image"
		exit 4
	fi

	# changing owner
	echo "Changing owner using : ${RSYNC_UID}:${RSYNC_GID}"
	sudo /bin/chown -R ${USERID}:${GROUPID} ${RPI_ROOTFS_BASE}

	# fixing links and hack library paths
	./rpi_rootfs.py local ${RPI_ROOTFS_BASE}
}

function update_and_install_raspi_os_imsage {
	mkdir -p ${RPI_ROOTFS_BASE}/root
	cp ./scripts/${UPDATE_INSTALL_SCRIPT} ${RPI_ROOTFS_BASE}/root

	mount_chroot_syspath
	chmod 777 ${RPI_ROOTFS_BASE}/tmp
	cp ${QEMU_ARM_STATIC} ${RPI_ROOTFS_BASE}/${QEMU_ARM_STATIC}

	sudo chroot ${RPI_ROOTFS_BASE} /usr/bin/qemu-arm-static \
		/bin/bash /root/${UPDATE_INSTALL_SCRIPT}

	# fixing links and hack library paths again
	./rpi_rootfs.py local ${RPI_ROOTFS_BASE}
}

function create_symlinks {
	local RPI_ROOTFS_BASE_ABS_PATH=$(echo "$(
		cd ${RPI_ROOTFS_BASE}
		pwd
	)")
	local CUR_USER=$(whoami)
	if [ -d "${RPI_ROOTFS_BASE_ABS_PATH}/usr/include/asm" ]; then
		sudo chmod 777 ${RPI_ROOTFS_BASE_ABS_PATH}/usr/include/asm
		ln -sf ${RPI_ROOTFS_BASE_ABS_PATH}/usr/include/arm-linux-gnueabihf/asm/* ${RPI_ROOTFS_BASE_ABS_PATH}/usr/include/asm/
	else
		ln -sf -r ${RPI_ROOTFS_BASE_ABS_PATH}/usr/include/arm-linux-gnueabihf/asm ${RPI_ROOTFS_BASE_ABS_PATH}/usr/include
	fi
	if [ -d "${RPI_ROOTFS_BASE_ABS_PATH}/usr/include/gnu" ]; then
		sudo chmod 777 ${RPI_ROOTFS_BASE_ABS_PATH}/usr/include/gnu
		ln -sf ${RPI_ROOTFS_BASE_ABS_PATH}/usr/include/arm-linux-gnueabihf/gnu/* ${RPI_ROOTFS_BASE_ABS_PATH}/usr/include/gnu/
	else
		ln -sf -r ${RPI_ROOTFS_BASE_ABS_PATH}/usr/include/arm-linux-gnueabihf/gnu ${RPI_ROOTFS_BASE_ABS_PATH}/usr/include
	fi
	if [ -d "${RPI_ROOTFS_BASE_ABS_PATH}/usr/include/bits" ]; then
		sudo chmod 777 ${RPI_ROOTFS_BASE_ABS_PATH}/usr/include/bits
		ln -sf ${RPI_ROOTFS_BASE_ABS_PATH}/usr/include/arm-linux-gnueabihf/bits/* ${RPI_ROOTFS_BASE_ABS_PATH}/usr/include/bits/
	else
		ln -sf -r ${RPI_ROOTFS_BASE_ABS_PATH}/usr/include/arm-linux-gnueabihf/bits ${RPI_ROOTFS_BASE_ABS_PATH}/usr/include
	fi
	if [ -d "${RPI_ROOTFS_BASE_ABS_PATH}/usr/include/sys" ]; then
		sudo chmod 777 ${RPI_ROOTFS_BASE_ABS_PATH}/usr/include/sys
		ln -sf ${RPI_ROOTFS_BASE_ABS_PATH}/usr/include/arm-linux-gnueabihf/sys/* ${RPI_ROOTFS_BASE_ABS_PATH}/usr/include/sys/
	else
		ln -sf -r ${RPI_ROOTFS_BASE_ABS_PATH}/usr/include/arm-linux-gnueabihf/sys ${RPI_ROOTFS_BASE_ABS_PATH}/usr/include
	fi
	if [ -d "${RPI_ROOTFS_BASE_ABS_PATH}/usr/include/openssl" ]; then
		sudo chmod 777 ${RPI_ROOTFS_BASE_ABS_PATH}/usr/include/openssl
		ln -sf ${RPI_ROOTFS_BASE_ABS_PATH}/usr/include/arm-linux-gnueabihf/openssl/* ${RPI_ROOTFS_BASE_ABS_PATH}/usr/include/openssl/
	else
		ln -sf -r ${RPI_ROOTFS_BASE_ABS_PATH}/usr/include/arm-linux-gnueabihf/openssl ${RPI_ROOTFS_BASE_ABS_PATH}/usr/include
	fi

	ln -sf ${RPI_ROOTFS_BASE_ABS_PATH}/usr/lib/arm-linux-gnueabihf/crtn.o ${RPI_ROOTFS_BASE_ABS_PATH}/usr/lib/crtn.o
	ln -sf ${RPI_ROOTFS_BASE_ABS_PATH}/usr/lib/arm-linux-gnueabihf/crt1.o ${RPI_ROOTFS_BASE_ABS_PATH}/usr/lib/crt1.o
	ln -sf ${RPI_ROOTFS_BASE_ABS_PATH}/usr/lib/arm-linux-gnueabihf/crti.o ${RPI_ROOTFS_BASE_ABS_PATH}/usr/lib/crti.o
}

#
function run_chroot_command {
	local command_string=$1
	mount_chroot_syspath
	echo "CMD: ${command_string}"
	sudo chroot ${RPI_ROOTFS_BASE} /usr/bin/qemu-arm-static ${command_string}
}

#
function run_chroot_cmd_apt_update {
	mount_chroot_syspath
	echo "CMD: Running apt update & full-upgrade & autoreove"
	sudo chroot ${RPI_ROOTFS_BASE} /usr/bin/qemu-arm-static /usr/bin/apt update
	sudo chroot ${RPI_ROOTFS_BASE} /usr/bin/qemu-arm-static /usr/bin/apt -y dist-upgrade
	sudo chroot ${RPI_ROOTFS_BASE} /usr/bin/qemu-arm-static /usr/bin/apt -y install build-essential cmake unzip pkg-config gfortran gcc g++ gperf flex texinfo gawk bison openssl pigz libncurses-dev autoconf automake tar figlet
	sudo chroot ${RPI_ROOTFS_BASE} /usr/bin/qemu-arm-static /usr/bin/apt -y autoremove
}

#
function create_rootfs {
	local image_filename=$1

	echo "RaspiOS image file name : ${image_filename}"
	if [ ! -e ${image_filename} ]; then
		echo "RaspiOS image not found"
		exit 5
	fi

	mkdir -p ${RPI_ROOTFS_BASE}
	extract_zip_and_mount_image ${image_filename}
	copy_files_from_image
	update_and_install_raspi_os_imsage
	create_symlinks
}

function rootfs_must_not_exist {
	if [ -e ${RPI_ROOTFS_BASE} ]; then
		echo "rootfs already exist, remove rootfs if you want to create new one"
		exit 1
	fi
}

function rootfs_must_exist {
	if [ ! -e ${RPI_ROOTFS_BASE} ]; then
		echo "rootfs does not exist, you need to build rootfs at first"
		exit 1
	fi
}

function clean_rootfs {
	echo "removing whole rootfs directory"
	sudo rm -fr ${RPI_ROOTFS_BASE}
	return 0
}

###############################################################################
#
#  script main
#
###############################################################################
if [ "$#" -lt 1 ]; then
	print_usage
	exit 1
fi

args=("$@")

trap cleanUp EXIT
trap cleanUp SIGTERM SIGINT SIGFPE SIGSTOP SIGSYS

is_command_installed unzip
is_command_installed awk
is_command_installed grep
is_command_installed fdisk
is_command_installed rsync
is_command_installed qemu-arm-static # qemu-user-static package

CURRENT_WORKING_DIR=${PWD}

case ${args[0]} in
download)
	is_command_installed wget
	wget --trust-server-names https://downloads.raspberrypi.org/raspios_armhf_latest
	;;
create)
	rootfs_must_not_exist # exit this script when the rootfs exists
	create_rootfs ${args[1]}
	;;
update)
	run_chroot_cmd_apt_update
	;;
clean)
	clean_rootfs
	;;
run)
	shift
	run_chroot_command "$@"
	;;
*)
	echo "command not found : ${args[0]}"
	print_usage
	;;
esac

exit 0
