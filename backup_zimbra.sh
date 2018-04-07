#!/bin/bash
# 
#    Script to backup a Zimbra installation (open source version)
#    by installing the Zimbra on a separate LVM Logical Volume,
#    taking a snapshot of that partition after stopping Zimbra,
#    restarting Zimbra services, then rsyncing the snapshot to a 
#    separate backup point.

#    This script was originally based on a script found on the Zimbra wiki
#    http://wiki.zimbra.com/index.php?title=Open_Source_Edition_Backup_Procedure
#    and totally rewritten since then.

#    Copyright (C) 2007 Serge van Ginderachter <svg@ginsys.be>
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License version 2 as 
#    published by the Free Software Foundation.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#    Or download it from http://www.gnu.org/licenses/old-licenses/gpl-2.0.html

####################################################################################

# Read config   
source backup_zimbra_config
# zm_backup_path=/opt.bak
# zm_lv=opt
# zm_lv_mount_point=
# zm_vg=data
# zm_path=
# zm_lv_fs=auto
# zm_mount_opts=ro
# LVCREATE=/sbin/lvcreate
# LVREMOVE=/sbin/lvremove
# zm_snapshot=opt-snapshot
# zm_snapshot_size=1G
# zm_snapshot_extents=
# zm_snapshot_path=/tmp/opt-snapshot
# backup_util=rsync
# obnam_tune="--lru-size=1024 --upload-queue-size=512"
# obnam_keep_policy=14d,8w,12m
# V=
# debug=

##########################################
# Do not change anything beyond this point
##########################################

pause() {
        if [ -n "$debug" ]; then
        echo "Press Enter to execute this step..";
        read input;
        fi
        }

say() { 
	MESSAGE_PREFIX="zimbra backup:"
	MESSAGE="$1"
	TIMESTAMP=$(date +"%F %T")
	echo -e "$TIMESTAMP $MESSAGE_PREFIX $MESSAGE"
	logger -t $log_tag -p $log_facility.$log_level "$MESSAGE" 
	logger -t $log_tag -p $log_facility_mail.$log_level "$MESSAGE"
	pause
	}

error ()  {
	MESSAGE_PREFIX="zimbra backup:"
        MESSAGE="$1"
	TIMESTAMP=$(date +"%F %T")
	echo -e $TIMESTAMP $MESSAGE >&2
	logger -t $log_tag -p $log_facility.$log_level_err "$MESSAGE"
	logger -t $log_tag -p $log_facility_mail.$log_level_err "$MESSAGE"
	exit 1
	}

# Check for sane lv settings
if [[ $zm_snapshot_size && $zm_snapshot_extents ]]; then
	error "cannot specify both byte size ($zm_snapshot_size) and number of extents ($zm_snapshot_extents) for snapshot; please set only one or the other"
fi

# Output date
say "backup started"

# Stop the Zimbra services
say "stopping the Zimbra services, this may take some time"
/etc/init.d/zimbra stop || error "error stopping Zimbra" 
[ "$(ps -u zimbra -o "pid=")" ] && kill -9 $(ps -u zimbra -o "pid=") #added as a workaround to zimbra bug 18653

# Unmount volume to ensure clean filesystem for snapshot
if [[ $zm_lv_mount_point ]]; then
	say "unmounting $zm_lv_mount_point"
	umount $zm_lv_mount_point || error "unable to unmount $zm_lv_mount_point"
fi

# Create a logical volume called ZimbraBackup
say "creating a LV called $zm_snapshot"
if [[ $zm_snapshot_size ]]; then
	lv_size="-L $zm_snapshot_size"
else
	lv_size="-l $zm_snapshot_extents"
fi
$LVCREATE $lv_size -s -n $zm_snapshot /dev/$zm_vg/$zm_lv  || error "error creating snapshot, exiting" 

# Remount original volume
if [[ $zm_lv_mount_point ]]; then
        say "re-mounting $zm_lv_mount_point"
        mount $zm_lv_mount_point || error "unable to re-mount $zm_lv_mount_point"
fi

# Start the Zimbra services
say "starting the Zimbra services in the background....."
(/etc/init.d/zimbra start && say "services background startup completed") || error "services background startup FAILED" &

# zmconfigd in Zimbra 8.6 seems to have a hard time getting going during heavy I/O; let's give it time to start up before the backup begins
sleep 120

# Create a mountpoint to mount the logical volume to
say "creating mountpoint for the LV"
mkdir -p $zm_snapshot_path || error "error creating snapshot mount point $zm_snapshot_path"

# Mount the logical volume snapshot to the mountpoint
say "mounting the snapshot $zm_snapshot"
mount -t $zm_lv_fs -o $zm_mount_opts /dev/$zm_vg/$zm_snapshot $zm_snapshot_path

# Create the current backup using the configured tool
case $backup_util in
	rsync)
		# Use rsync
		say "rsyncing the snapshot to the backup directory $zm_backup_path"
		rsync -aAHS$V --delete $zm_snapshot_path/$zm_path $zm_backup_path || say "error during rsync but continuing the backup script"
		;;
	obnam)
		# Use obnam
		say "backing up via obnam to the backup directory $zm_backup_path"
		[[ $V = "v" ]] && verbose="--verbose"
		obnam backup $verbose $obnam_tune --repository $zm_backup_path $zm_snapshot_path/$zm_path || error "error creating obnam backup"
		if [[ $obnam_keep_policy ]]; then
			say "forgetting old obnam backups according to policy: $obnam_keep_policy"
			obnam forget $verbose --repository $zm_backup_path --keep $obnam_keep_policy || error "error forgetting obnam backups"
		fi
		;;
esac

# Unmount $zm_snapshot from $zm_snapshot_mnt
say "unmounting the snapshot"
umount $zm_snapshot_path || error "error unmounting snapshot"

# Delete the snapshot mount dir
rmdir $zm_snapshot_path

# Remove the snapshot volume
# https://bugs.launchpad.net/ubuntu/+source/linux-source-2.6.15/+bug/71567
say "pausing 1s and syncing before removing the snapshot from LVM"
sleep 1 ; sync                 
say "removing the snapshot"
$LVREMOVE --force /dev/$zm_vg/$zm_snapshot  || say "error removing the snapshot"

# Done!
say "backup ended"
date >$zm_backup_path/lastsync
