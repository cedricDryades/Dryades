#!/bin/bash
# 
# CLUTCH - Remote Save
#
# This script copys every file from finished torrents to a remote server.
# The script can be run after each download via transmission itself or via cron/cli.
# 
# To make this easy it requires to be run as root (sudoers file)
# cat 'debian-transmission ALL = (root) NOPASSWD: /etc/transmission-daemon/clutch.sh' >> /etc/sudoers
# 
# You also need passwordless ssh connection between the servers 
# EX TUTO: https://donjajo.com/set-ssh-keys-servers/#.W2-wdy-ZMuQ
#
# Script is not intended for "out of the box" use, so please email me if you have any issues
# My contact information can be found on http://www.dryades.org
#





# SETTINGS
# ---------------------------------------------------------------------------------------------------------------------------------
# User and password to the LOCAL transmission-remote
USER="YOUR_TRANSMISSION_USER"
PASSWORD="YOUR_TRANSMISSION_PASSWORD"
# SSH LOGIN TO REMOTE SERVER (MUST BE automatic login)
REMOTELOGIN="USER@REMOTE_SERVER"
REMOTEPATH="/WHERE/YOU/WANT/THE/FILES"
REMOTEPORT="SSH_REMOTE_PORT"
# Email infos
EMAILTO="you@you.com"
EMAILSUBJECT="[CLUTCH] - "
EMAILFROM="you@you.com"
EMAILNAME="You"
# ---------------------------------------------------------------------------------------------------------------------------------
# SCRIPT CORE BELOW - NO MODIFICATIONS ARE NECESSARY FOR NORMAL USE





# ensure running as root
if [ "$(id -u)" != "0" ]; then
  exec sudo "$0" "$@"
fi

#working files
LOGFILE="/tmp/clutch.log";
echo ""  > $LOGFILE;
TRANSFERLOG="/tmp/clutch_transfer.log";
echo ""  > $TRANSFERLOG;
TRANSFER_ERR="/tmp/clutch_transfer_err.log";
echo ""  > $TRANSFER_ERR;

# Copy of the finished torrents to demeter + deletion from artemis

# port, username, password
TR_ARGS="127.0.0.1 -p 9091 -n $USER:$PASSWORD";

# use transmission-remote to get torrent list from transmission-remote list
# use sed to delete first / last line of output, and remove leading spaces
# use cut to get first field from each line
# TORRENTLIST=`transmission-remote $TR_ARGS --list | sed -e '1d;$d;s/^ *//' | cut --only-delimited --delimiter=" " --fields=1`
TORRENTLIST=`transmission-remote $TR_ARGS --list | sed -e '1d;$d;s/^ *//' | cut -s -d " " -f1 | head -n -1`;


# for each torrent in the list
for TORRENTID in $TORRENTLIST ; do

	#Init
	echo "0"  > $TRANSFER_ERR;
	cd /srv/clutch/


	#Gathering Torrent information
	TR_NAME=`transmission-remote $TR_ARGS --torrent $TORRENTID --info | grep "Name" | cut -c 9-`;
	TR_ETA=`transmission-remote $TR_ARGS --torrent $TORRENTID --info | grep "ETA" | cut -c 8-`;
	TR_PERCENT=`transmission-remote $TR_ARGS --torrent $TORRENTID --info | grep "Percent Done" | cut -c 17-`;
	DL_COMPLETED=`transmission-remote $TR_ARGS --torrent $TORRENTID --info | grep "Percent Done: 100%"`;
	TR_TORRENT_FILES=`transmission-remote $TR_ARGS --torrent $TORRENTID -f | sed -e '1,2d;$d' | cut -c 35-`
	echo "$TR_TORRENT_FILES" > /srv/clutch/tmp.txt

	# if the torrent is "Stopped", "Finished", or "Idle after downloading 100%"
	if [[ "$DL_COMPLETED" ]]; then

		echo "${TR_NAME^^}"  >> $LOGFILE 2>&1
		echo " " >> $LOGFILE 2>&1

		echo "----------------------------------"  >> $LOGFILE 2>&1
		echo "FILE LIST" >> $LOGFILE 2>&1
		echo "----------------------------------"  >> $LOGFILE 2>&1

		while IFS= read -r FILE
		do
			# adding filename to log
			echo "    $FILE" >> $LOGFILE 2>&1

			# File Transfer (automatic ssh connection must be setup between the two hosts)
			rsync -R --protect-args -e "ssh -p $REMOTEPORT" "$FILE" $REMOTELOGIN:$REMOTEPATH >> $TRANSFERLOG 2>&1

			# if unsuccesful - log error
			if [[ $? -ne 0 ]]; then
				echo "1"  > $TRANSFER_ERR;
				#break;
			fi

			# Changing file permissions on the remote server PER FILE (Other global version below)
			#ssh -p $REMOTEPORT -n $REMOTELOGIN chown -R cedric:users "$REMOTEPATH${FILE}" >> $TRANSFERLOG 2>&1
			#ssh -p $REMOTEPORT -n $REMOTELOGIN chmod -R 777 "$REMOTEPATH${FILE}" >> $TRANSFERLOG 2>&1
		done < /srv/clutch/tmp.txt

                # Changing file permissions on the remote server PER FILE (Other global version below)
                ssh -p $REMOTEPORT -n $REMOTELOGIN chmod -R 777 "$REMOTEPATH" >> $TRANSFERLOG 2>&1


		# echo "Torrent ID: $TORRENTID" >> $LOGFILE 2>&1
		# echo "Exit code: $?" >> $LOGFILE 2>&1
		# echo "TRANSFER_ERR: $(cat $TRANSFER_ERR)" >> $LOGFILE 2>&1
		# echo "DLCOMPLETED: $DLCOMPLETED" >> $LOGFILE 2>&1

		## Error checking
		# transfer successful - Mail + deletion
		if [[ $(cat $TRANSFER_ERR) = "0" ]]; then
			#Adding torrent name to email subject
			EMAILSUBJECT="$EMAILSUBJECT $TR_NAME"
			# echo ${TR_NAME^^}  >> $LOGFILE 2>&1
			echo "------------------------------------"  >> $LOGFILE 2>&1
			echo "Torrent transfer #$TORRENTID is completed" >> $LOGFILE 2>&1
			echo "------------------------------------"  >> $LOGFILE 2>&1
			echo ""  >> $LOGFILE 2>&1
			echo "------------------------------------" >> $LOGFILE 2>&1
			echo "DELETING TORRENT" >> $LOGFILE 2>&1
			echo "------------------------------------" >> $LOGFILE 2>&1
			echo ""  >> $LOGFILE 2>&1
			transmission-remote $TR_ARGS --torrent $TORRENTID --remove-and-delete >> $LOGFILE
			echo ""  >> $LOGFILE 2>&1
			echo "------------------------------------" >> $LOGFILE 2>&1
			echo "TRANSFER LOG"  >> $LOGFILE 2>&1
			echo "------------------------------------" >> $LOGFILE 2>&1
			cat "$TRANSFERLOG"  >> $LOGFILE 2>&1
		else
			#transfer failed
			EMAILSUBJECT="$EMAILSUBJECT Transfer failed";
			echo "\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/"  >> $LOGFILE 2>&1
			echo "Torrent #$TORRENTID -  TRANSFER FAILED" >> $LOGFILE 2>&1
			echo "\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/"  >> $LOGFILE 2>&1
			echo "------------------------------------" >> $LOGFILE 2>&1
			echo "TRANSFER LOG"  >> $LOGFILE 2>&1
			echo "------------------------------------" >> $LOGFILE 2>&1
			cat "$TRANSFERLOG"  >> $LOGFILE 2>&1
			echo ""  >> $LOGFILE 2>&1
			echo "Torrent has NOT been deleted from the server"  >> $LOGFILE 2>&1
		fi
	else
	# Keeping the imcomplete torrent information for display in the email
	TR_INPROGRESS+="Torrent #$TORRENTID - $TR_ETA ($TR_PERCENT) $TR_NAME";
   	fi
done

# Torrents in progress listing
if [[ "$TR_INPROGRESS" ]]; then
	echo ""  >> $LOGFILE 2>&1
	echo "------------------------------------" >> $LOGFILE 2>&1
	echo "Torrents still in progress" >> $LOGFILE 2>&1
	echo "------------------------------------" >> $LOGFILE 2>&1
	echo ""  >> $LOGFILE 2>&1
	echo "$TR_INPROGRESS"  >> $LOGFILE 2>&1
fi

echo -e "Subject:$EMAILSUBJECT \n\n $(cat $LOGFILE)" | /usr/sbin/sendmail -f "$EMAILFROM" -F "$EMAILNAME" "$EMAILTO" # ADD -v for debugging

#removing working file
rm $TRANSFER_ERR;
rm $TRANSFERLOG;
rm $LOGFILE;
rm /srv/clutch/tmp.txt;
