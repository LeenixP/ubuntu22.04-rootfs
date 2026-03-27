#!/bin/bash -e

TARGET_ROOTFS_DIR=./binary
MOUNTPOINT=./rootfs
ROOTFSIMAGE=ubuntu-jammy.img

echo Making rootfs!

if [ -e ${ROOTFSIMAGE} ]; then
	sudo rm -f ${ROOTFSIMAGE} || true
fi
if [ -e ${MOUNTPOINT} ]; then
	sudo umount ${MOUNTPOINT} || true
	sudo rm -rf ${MOUNTPOINT} || true
fi


./ch-mount.sh -u $TARGET_ROOTFS_DIR || true

sudo ./post-build.sh $TARGET_ROOTFS_DIR

echo "Cleaning unnecessary files"
sudo rm -rf ${TARGET_ROOTFS_DIR}/var/cache/apt/archives/*
sudo rm -rf ${TARGET_ROOTFS_DIR}/var/lib/apt/lists/*
sudo rm -rf ${TARGET_ROOTFS_DIR}/tmp/*
sudo rm -rf ${TARGET_ROOTFS_DIR}/var/log/*
sudo find ${TARGET_ROOTFS_DIR} -type f \( -name "*.log" -o -name "*.tmp" \) -delete
sudo rm -f ${TARGET_ROOTFS_DIR}/root/.bash_history

# Create directories
mkdir ${MOUNTPOINT}
sudo -E dd if=/dev/zero of=${ROOTFSIMAGE} bs=1M count=0 seek=8000

finish() {
	sudo umount ${MOUNTPOINT} || true
	echo -e "\e[31m MAKE ROOTFS FAILED.\e[0m"
	exit -1
}

echo Format rootfs to ext4
sudo -E mkfs.ext4 ${ROOTFSIMAGE}

echo mount rootfs to ${MOUNTPOINT} .......
sudo -E mount ${ROOTFSIMAGE} ${MOUNTPOINT}
trap finish ERR

echo Copy rootfs to ${MOUNTPOINT}
sudo cp -rfp ${TARGET_ROOTFS_DIR}/*  ${MOUNTPOINT}

echo Umount rootfs
sudo umount ${MOUNTPOINT}

echo Resize rootfs
sudo e2fsck -p -f ${ROOTFSIMAGE}
sudo resize2fs -M ${ROOTFSIMAGE}
sudo fallocate -d ${ROOTFSIMAGE}

echo Rootfs Image: ${ROOTFSIMAGE}
