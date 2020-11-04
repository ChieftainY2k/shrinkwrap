#!/bin/bash

#helper function
log_message()
{
    LOGPREFIX="[$(date '+%Y-%m-%d %H:%M:%S')][$(basename $0)]"
    MESSAGE=$1
    echo "$LOGPREFIX $MESSAGE"
}

#check for errors
check_errors()
{
    EXITCODE=$1
    if [[ ${EXITCODE} -ne 0 ]]; then
        log_message "ERROR: Exit code ${EXITCODE} , check the ouput for details."
        exit 1
    fi
}


if [ $# -eq 0 ]
  then
    log_message "No arguments supplied. Usage:"
    log_message "shrinkwrap.sh myimage.img"
    log_message "Script will shrink the image to minimal size *in place*."
    log_message "Be sure to make a copy of the image before running this script."
    exit 1
fi
set -e

sudo fdisk -l $1
check_errors $?

sudo fdisk -l $1 > /tmp/fdisk.log
check_errors $?

START=$(cat /tmp/fdisk.log | grep "83 Linux" | awk '{print $2}')

log_message "START of partition: $START"

sudo losetup -d /dev/loop0 || log_message "Good - no /dev/loop0 is already free"
check_errors $?
sudo losetup /dev/loop0 $1
check_errors $?
sudo partprobe /dev/loop0
check_errors $?
sudo lsblk /dev/loop0
check_errors $?
sudo e2fsck -f /dev/loop0p2
check_errors $?
sudo resize2fs -p /dev/loop0p2 -M
check_errors $?
sudo dumpe2fs -h /dev/loop0p2 | tee /tmp/dumpe2fs
check_errors $?
# Calculate the size of the resized filesystem in 512 blocks which we'll need
# later for fdisk to also resize the partition add 16 blocks just to be safe
NEWSIZE=$(cat /tmp/dumpe2fs |& awk -F: '/Block count/{count=$2} /Block size/{size=$2} END{print count*size/512 +  16}')
log_message "NEW SIZE of partition: $NEWSIZE  512-blocks"

# now pipe commands to fdisk
sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | sudo fdisk /dev/loop0 || log_message "Ignore that error."
  p # print the in-memory partition table
  d # delete partition
  2 # partition 2
  n # new partition
  p # primary partition
  2 # partion number 2
  $START # start where the old partition started
  +$NEWSIZE  # new size in 512 blocks
    # ok
  p # print final result
  w # write the partition table
  q # and we're done
EOF

sudo fdisk -l $1
check_errors $?
sudo fdisk -l $1 > /tmp/fdisk_new.log
check_errors $?
sudo losetup -d /dev/loop0
check_errors $?

FINALEND_BYTES=$(cat /tmp/fdisk_new.log | grep "83 Linux" | awk '{printf "%.0f",($3+1)*512}')
log_message "TRUNCATE AT: $FINALEND_BYTES bytes"

# Truncate the image file on disk
sudo truncate -s $FINALEND_BYTES $1
check_errors $?

# Fill the empty space with zeros for better compressability
sudo losetup /dev/loop0 $1
check_errors $?
sudo partprobe /dev/loop0
check_errors $?
sudo mkdir -p /tmp/mountpoint
check_errors $?
sudo mount /dev/loop0p2 /tmp/mountpoint
check_errors $?
sudo dd if=/dev/zero of=/tmp/mountpoint/zero.txt  status=progress || log_message "Expected to fail with out of space"
check_errors $?
sudo rm /tmp/mountpoint/zero.txt
check_errors $?
df -h /tmp/mountpoint
check_errors $?
sudo umount /tmp/mountpoint
check_errors $?
lsblk
check_errors $?
sudo rmdir /tmp/mountpoint
check_errors $?

log_message "We're done. Final info: "
sudo fdisk -l $1
check_errors $?
sudo dumpe2fs -h /dev/loop0p2 | tee /tmp/dumpe2fs
check_errors $?
sudo losetup -d /dev/loop0
check_errors $?
