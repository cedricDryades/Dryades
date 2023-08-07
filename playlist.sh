#!/bin/bash
###
# In each folder where I want to make a playlist (m3u), create an empty trigger.txt file.
# if detected, any music files in the subfolders will be added to the playlist!
# 
# Run the script from the folder where your music files are located.
# You need ./playlists and ./playlists/plex folders in directory where you run this script 
# Based on script from https://www.reddit.com/user/leporel/
# 
# TODO A lot... this is an early script, remove the need for trigger.txt and just use each folder present
# TODO Check for the creation of the playlist folder or better take an arg on where to save the playlists
# TODO 
#
# cedric emailsign dryades.org - 2023
###

find . -type d |
while read subdir
do

	files=$(ls "$subdir" | grep "trigger.txt")
	if [ ! ${#files} -gt 0 ]
		then
			echo "Folder  "$subdir" dont have trigger, skipping"
		else
			sub_parent=${subdir%/*}
			if [[ ${sub_parent} == "." ]]
				then 
					sub_parent="Root"
			fi
			
			echo -n "" > ./playlists/"${sub_parent##*/}_${subdir##*/}.m3u"
			echo -n "" > ./playlists/plex/"${sub_parent##*/}_${subdir##*/}.m3u"
			
			find "$subdir"/* -type f |
			while read filename
			do
			if [ ${filename: -4} == ".mp3" ] || [ ${filename: -5} == ".flac" ] || [ ${filename: -4} == ".ogg" ] || [ ${filename: -4} == ".aac" ]
			then
				echo ."${filename}" >> ./playlists/"${sub_parent##*/}_${subdir##*/}.m3u"
				song=$(echo "${filename}" | sed -e 's/ /%20/g')
				song=$(echo "${song}" | sed -e 's|./|/volume1/music/|')
				echo "${song}" >> ./playlists/plex/"${sub_parent##*/}_${subdir##*/}.m3u"
			fi
			done
   fi
done