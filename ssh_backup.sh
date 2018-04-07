#!/bin/bash
## *** Info ***
# USAGE:    -h or --help for help & usage.
#           -f or --full for Full backup.
#           -d or --diff for Diff backup.
#           -V or --version for version info.
#           --INSTALL	 for script install and setup.
#
# This is a backup script for the FOSS version of Zimbra mail server.
# The script is free and open source and for use by anyone who can find a use for it.
#
# THIS SCRIPT IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT
# HOLDERS AND/OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
# BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED
# AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF
# THE USE OF THIS DOCUMENT, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
# CONTRIBUTORS:
# heinzg of osoffice.de (original author)
# Quentin Hartman of Concentric Sky, qhartman@concentricsky.com (refactor and cleanup)
#
# What this script does:
# 1. Makes daily off-line backups, at a service downtime of ~ < 2 min.
# 2. Weekly backup cycle - 1 full backup & 6 diffs.
# 3. Predefined archive sizes, for writing backups to CD or DVD media...
# 4. Backup archive compression.
# 5. Backup archive encryption.
# 6. Backup archive integrity checks and md5 checksums creation.
# 7. Automated DR - Off-site copy of backup archives via ssh.
# 8. Install and setup function for needed software (Ubuntu Systems only)
# 9. Weekly eMail report & eMail on error - including CC address.
#
# This script makes use of following tools:
# apt-get, cron, dar, dpkg, mailx, md5sum, rsync, ssh, uuencode, wget, zimbra mta.
#
# We have opted to use a pre-sync directory to save on "down time", but this 
# causes one to have huge additional space usage.
# But hard drives are cheep today!
#
# What is still to come or needs work on:
# 1. Recovery option
# 2. Better documentation

##------- CONFIG -------#
# Edit this part of the script to fit your needs.

#--- Directories ---#
# Please add the trailing "/" to directories!
ZM_HOME=/opt/zimbra/	# where zimbra lives
SYNC_DIR=/tmp/fakebackup/	# intermediate dir for hot/cold syncs. must have at least as much free space as ZM_HOME consumes
ARCHIVEDIR=/Backup/zimbra_dars/	# where to store final backups
TO_MEDIA_DIR=/Backup/burn/	# where to put fulls for archiving to media

#--- PROGRAM OPTIONS ---# 
RSYNC_OPTS="-aHK --delete --exclude=*.pid" # leave these unless you are sure you need something else

#--- ARCHIVE NAMES ---#
BACKUPNAME="Zimbra_Backup"	# what you want your backups called
FULL_PREFIX="FULL"	# prefix used for full backups
DIFF_PREFIX="DIFF"	# prefix used for differential backups
BACKUPDATE=`date +%d-%B-%Y`	# date format used in archive names
BACKUPWEEK=`date +%W`	# Week prefix used for backup weekly rotation and naming

#--- ARCHIVE SIZE ---#
ARCHIVESIZE="4395M"	# storage media size, for full-backup archiving
COMPRESS="9"		# valid answers are 1 - 9 ( 9 = best )

#--- Encryption Options ---#
CRYPT="yes"		# valid answers are "yes" or "no"
PASSDIR=/etc/`basename $0`/ # the directory the encryption hash is stored in. 
PASSFILE="noread"	# the file containing the password hash

#--- Log Settings ---#
EMAIL="your@mailaddress.local"	# the address to send logs to
EMAILCC=""				# another address to send to
LOG="/var/log/zim_backup.log"	# log location

#--- SSH REMOTE DR COPY ---#
# This option will secure copy your archives to a remote server via 'scp'
DRCP="no"		# valid answers are "yes" or "no" 
SSHUSER="you"	# recommend creating a user on the remote machine just for transferring backups	
SSHKEY="rsa"	# recommended answers are "rsa" or "dsa" but "rsa1" is also valid.
REMOTEHOST="remote.server.fqdn"	# can use IP too
REMOTEDIR="/tmp/"	# where you want your backups saved.

#--- Use Hacks? ---#
# Built in hacks to fix common problems
#Hack to start Stats, even run zmlogprocess if needed
STATHACK="yes" 		# valid answers are "yes" or "no"


## ~~~~~!!!! SCRIPT RUNTIME !!!!!~~~~~ ##
# Best you don't change anything from here on, 
# ONLY EDIT IF YOU KNOW WHAT YOU ARE DOING
