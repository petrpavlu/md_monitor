#!/bin/bash
#
# Testcase 6: reserve DASDs w/ I/O
#

. ./monitor_testcase_functions.sh

MD_NUM="md1"
MD_NAME="testcase6"
DEVNOS_LEFT="0.0.0210 0.0.0211 0.0.0212 0.0.0213 0.0.0214 0.0.0215 0.0.0216 0.0.0217"
DEVNOS_RIGHT="0.0.0220 0.0.0221 0.0.0222 0.0.0223 0.0.0224 0.0.0225 0.0.0226 0.0.0227"
IO_TIMEOUT=10

logger "Monitor Testcase 6: Reserve DASDs w/ I/O"

stop_md $MD_NUM

activate_dasds

clear_metadata

ulimit -c unlimited
start_md $MD_NAME

MD_NUM=$(readlink /dev/md/${MD_NAME})
MD_NUM=${MD_NUM##*/}

echo "$(date) Create filesystem ..."
if ! mkfs.ext3 /dev/${MD_NUM} ; then
    error_exit "Cannot create fs"
fi

echo "$(date) Mount filesystem ..."
if ! mount /dev/${MD_NUM} /mnt ; then
    error_exit "Cannot mount MD array."
fi

echo "$(date) Run dt"
run_dt /mnt;

echo "$(date) Wait for reservation on left half ..."
num=0
while [ $num -eq 0 ] ; do
    for d in ${DASDS_LEFT[@]}; do
	state=$(tunedasd -Q /dev/$d)
	if [ "$state" = "other" ] ; then
	    (( num ++ ))
	    break;
	fi
    done
    sleep 1
done
logger "$num DASDs reserved"
echo "$(date) Ok. Waiting for MD to pick up changes ..."
# Wait for md_monitor to pick up changes
sleeptime=0
num=${#DASDS_LEFT[@]}
while [ $num -gt 0  ] ; do
    mdstat=$(cat /proc/mdstat)
    for d in ${DASDS_LEFT[@]} ; do
	device=$(echo $mdstat | sed -n "s/${MD_NUM}.* \(${d}1\[[0-9]*\]([F|T])\).*/\1/p")
	if [ "$device" ] ; then
	    (( num -- ))
	fi
    done
    [ $num -eq 0 ] && break
    num=${#DASDS_LEFT[@]}
    sleep 1
    (( sleeptime ++ ))
done
echo "$(date) MD monitor picked up changes after $sleeptime seconds"

echo "$(date) MD status"
mdadm --detail /dev/${MD_NUM}

echo "$(date) Wait for $IO_TIMEOUT seconds"
sleep $IO_TIMEOUT

echo "$(date) Wait for reservations to be cleared ..."
num=${#DASDS_LEFT[@]}
while [ $num -gt 0 ] ; do
    num=0
    for d in ${DASDS_LEFT[@]}; do
	state=$(tunedasd -Q /dev/$d)
	if [ "$state" = "other" ] ; then
	    (( num ++ ))
	fi
    done
    [ $num -eq 0 ] && break
    num=${#DASDS_LEFT[@]}
    sleep 1
done
logger "All DASDs released"

echo "$(date) Ok. Waiting for MD to pick up changes ..."
# Wait for md_monitor to pick up changes
sleeptime=0
num=${#DASDS_LEFT[@]}
while [ $num -gt 0  ] ; do
    for d in ${DASDS_LEFT[@]} ; do
	device=$(sed -n "s/${MD_NUM}.* \(${d}1\[[0-9]*\]\).*/\1/p" /proc/mdstat)
	if [ "$device" ] ; then
	    (( num -- ))
	fi
    done
    [ $num -eq 0 ] && break
    num=${#DASDS_LEFT[@]}
    sleep 1
    (( sleeptime ++ ))
done
echo "$(date) MD monitor picked up changes after $sleeptime seconds"

echo "$(date) MD status"
mdadm --detail /dev/${MD_NUM}

echo "$(date) Stop dt"
killall -KILL dt 2> /dev/null

echo "$(date) Wait for sync ..."
wait_for_sync ${MD_NUM}

mdadm --detail /dev/${MD_NUM}

echo "$(date) Umount filesystem ..."
umount /mnt

stop_md ${MD_NUM}