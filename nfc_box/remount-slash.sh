#!/bin/bash

function remount_rw {
	if [ "$(awk '$4 ~ "^ro[,$]" && $2 ~ "^/$" {print $0}' /proc/mounts)" ];then
		mount -o remount,rw /
	fi
}

function remount_ro {
        if [ "$(awk '$4 ~ "^rw[,$]" && $2 ~ "(^/$)" {print $0}' /proc/mounts)" ];then
                mount -o remount,ro /
	fi
}

if [[ $# -ne 1 ]] || ([[ "$1" != "ro" ]] && [[ "$1" != "rw" ]]);then
	echo "Usage:"
	echo "$0 ro for remount / read only"
	echo "$0 rw for remount / read write"
	exit 1
fi

if [[ "$1" == "ro" ]];then remount_ro; fi
if [[ "$1" == "rw" ]];then remount_rw; fi

exit 0
