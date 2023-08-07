#!/bin/bash

## @author    @tarampampam
## @project   Get torrent RSS feed, extract links and pass to Transmission
##            torrent client
## @copyright 2015 <github.com/tarampampam>
## @github
## @version   0.0.6
##
## @depends   wget|curl, tr, sed, awk, transmission-remote
# 
# # CRON
# 5 8-23 * * * / usr / bin / nice -n 15 / usr / bin / bash ~ / get_torrents.sh


# *****************************************************************************
# ***                              Settings                                  **
# *****************************************************************************

## Use 'wget' for getting feed content ('1' = true, '0' = false), and setup
## path to 'wget' binary ('curl' will be disabled automatically)
USE_WGET=1; WGET_PATH=$(which wget 2>/dev/null);

## Use 'curl' for getting feed content ('1' = true, '0' = false), and setup
## path to 'curl' binary
USE_CURL=1; CURL_PATH=$(which curl 2>/dev/null);

## Use proxy for network connection ('1' = true, '0' = false), and other proxy
## settings
USE_PROXY=0;
PROXY_SCHEME='http';
PROXY_ADDR='88.88.88.88';
PROXY_PORT='8888';
PROXY_USER='';
PROXY_PASS='';

## Array with feeds url-s (string) and download directories (string or empty)
## for each url. Remember - 1st is url, 2nd - path, 3rd - url, 4rd - path, etc.
FEED_URLS_AND_DIRS=(\
  'http://showrss.info/yourfeedhere'              '/where/to/dl' \

);

## Transmission RPC settings. First you must enable RPC in transmission config
## file ("rpc-enabled": true, "rpc-port": 9091, "rpc-whitelist": "127.0.0.1")
TRANSMISSION_REMOTE=$(which transmission-remote 2>/dev/null);
TRANSMISSION_RPC_USER='clutch';
TRANSMISSION_RPC_PASS='password';
TRANSMISSION_RPC_HOST='127.0.0.1';
TRANSMISSION_RPC_PORT='9091';

## After script work remove all completed tasks in Transmission (just tasks,
## not files)
REMOVE_TRANSMISSION_COMPLETED_TASKS=1;

## File, where we will store downloaded links
HISTORY_FILE=$(dirname $(readlink -e $0))"/history.log";

## Use color output
COLOR_OUTPUT=1;

# *****************************************************************************
# ***                          END of Settings                               **
# *****************************************************************************

cRed='\e[1;31m'; cGreen='\e[0;32m'; cNone='\e[0m'; cYel='\e[1;33m';
cBlue='\e[1;34m'; cGray='\e[1;30m'; fBold='\033[1m';

if [ "$COLOR_OUTPUT" -ne "1" ]; then cRed=''; cGreen=''; cNone=''; cYel='';
cBlue=''; cGray=''; fBold=''; fi;

msgOk="${cGreen}Ok${cNone}";  msgErr="${cRed}Error${cNone}";

## Switch output language to English (DO NOT CHANGE THIS)
export LC_ALL=C;

TransmissionRPC="$TRANSMISSION_REMOTE \"$TRANSMISSION_RPC_HOST:$TRANSMISSION_RPC_PORT\" -n \"$TRANSMISSION_RPC_USER:$TRANSMISSION_RPC_PASS\"";

logmessage() {
  ## $1 = (not required) '-n' flag for echo output
  ## $2 = message to output

  local flag=''; local outtext='';
  if [ "$1" == "-n" ]; then flag="-n"; outtext=$2; else outtext=$1; fi

  echo -e $flag "[$(date +%H:%M:%S)] $outtext";
}

getFeedContent() {
  local url=$1;

  local content=''; local proxy_settings='';
  local ua="Mozilla/5.0 (Macintosh; Mac OS X 10_7_3) AppleWebKit Safari";

  if [ "$USE_PROXY" == "1" ]; then
    if [ -z "$PROXY_USER" ] && [ -z "$PROXY_PASS" ]; then
      proxy_settings="${PROXY_SCHEME}://${PROXY_ADDR}:${PROXY_PORT}";
    else
      proxy_settings="${PROXY_SCHEME}://${PROXY_USER}:${PROXY_PASS}@${PROXY_ADDR}:${PROXY_PORT}";
    fi;
  fi;

  if [ "$USE_WGET" == "1" ]; then
    if [ -x "$WGET_PATH" ]; then
      if [ "$USE_PROXY" == "1" ]; then
        proxy_settings="-e use_proxy=yes -e http_proxy=${proxy_settings}";
      fi;
      content=$($WGET_PATH --user-agent="${ua}" --no-check-certificate $proxy_settings -q -O - "${url}");
    fi;
    USE_CURL=0;
  fi;

  if [ "$USE_CURL" == "1" ]; then
    if [ -x "$CURL_PATH" ]; then
      if [ "$USE_PROXY" == "1" ]; then
        proxy_settings="--proxy ${proxy_settings}";
      fi;
      content=$($CURL_PATH --user-agent "${ua}" --insecure $proxy_settings -s -L "${url}");
    fi;
    USE_WGET=0;
  fi;

  echo "$content";
}

getXMLparts() {
  local tag_name=$1; local data=$2;
  echo "$data" | tr '\n' ' ' | sed -r "s/<$tag_name/\n<$tag_name/g" | sed -n "/$tag_name/{s/.*<$tag_name>\(.*\)<\/$tag_name>.*/\1/;p}";
}

cutSubstring() {
  local string=$1; local length=$2;
  if [ "${#string}" -ge $length ]; then echo "${string:0:$length}.."; else echo "$string"; fi;
}

existsInHistory() {
  local entry=$1; local entries_count=0;
  if [ -f $HISTORY_FILE ]; then
    entries_count=$(grep -i "$entry" $HISTORY_FILE | wc -l);
    if [ "$entries_count" -ge 1 ]; then echo "1"; else echo "0"; fi;
  else
    echo "0";
  fi;
}

addToHistory() {
  local entry=$1;
  echo "$entry">>$HISTORY_FILE;
  if [ $(existsInHistory "$entry") ]; then echo "1"; else echo "0"; fi;
}

testTransmission() {
  result=$(eval "$TransmissionRPC -si 2>&1");
  if [[ $result == *"Couldn"* ]]; then echo "0"; else echo "1"; fi;
}

addToTransmission() {
  local torrent_url=$1; local download_to=$2;
  ## First step - get default download directory
  local default_download_directory=$(eval "$TransmissionRPC -si 2>&1" | grep -i "Download directory" | cut -d ":" -f2 | sed 's/^ *//');
  if [ -d "$default_download_directory" ]; then
    ## Second step - add task with overwriting default download directory (set location for single task - how?)
    if [ -z "$download_to" ]; then download_to=$default_download_directory; fi;
    local add_task_result=$(eval "$TransmissionRPC --download-dir \"$download_to\" --add \"$torrent_url\" 2>&1");
    ## Third step - restore default download location
    sleep 2;
    local restore_location_result=$(eval "$TransmissionRPC --download-dir=\"$default_download_directory\" 2>&1");
    if [[ $add_task_result == *"responded"*"success"* ]] && [[ $restore_location_result == *"responded"*"success"* ]]; then echo "1"; else echo "0"; fi;
  else
    echo "0";
  fi;
}

removeTransmissionCompletedTasks() {
  # Grep all lines with this substring:
  #   15 100% 2.3 GiB Done 0.0 0.0 0.00 Idle File.Name.Of.Movie.avi
  #      ^^^^*********^^^^
  local Finished=$(eval "$TransmissionRPC -l" | grep -i '100%.*Done');
  #echo "$Finished";
  # Get IDs list from 'grepped' list
  local IDs=$(echo "$Finished" | awk '{print $1}' | tr [:space:] "," && echo "0"); #echo "$IDs";
  if [ ! "$IDs" = ",0" ]; then
    # Say to transmission-remote for remove this torrents
    result=$(eval "$TransmissionRPC -t $IDs -r 2>&1");
    #echo "$result";
    if [[ $result == *"responded"*"success"* ]]; then echo "1"; else echo "0"; fi;
  else
    echo "-1";
  fi;
}


## Test Transmission RPC
if [ "$(testTransmission)" -ne "1" ]; then
  logmessage "Cannot connect to Transmission RPC. Please, check settings (path to binary '${cYel}$TRANSMISSION_REMOTE${cNone}', host '${cYel}$TRANSMISSION_RPC_HOST:$TRANSMISSION_RPC_PORT${cNone}', auth data '${cYel}$TRANSMISSION_RPC_USER:$TRANSMISSION_RPC_PASS${cNone}'). ${cRed}Stop working${cNone}";
  exit 1;
else
  logmessage "Connection to Transmission RPC ${cGreen}successful${cNone}";
fi;

loop_counter=0; echo -e ""; for feed_url_or_dir in "${FEED_URLS_AND_DIRS[@]}"; do
  feed_url=""; download_dir="";
  ## Check - what in array item? If item NOT begins from '/' char and NOT empty, we understand - this is directory path
  if [[ ! "${feed_url_or_dir:0:1}" == "/" ]] && [ ! -z "$feed_url_or_dir" ]; then
    ## Setup as url - ACTIVE array item, and as download directory - NEXT array item
    feed_url=$feed_url_or_dir; download_dir="${FEED_URLS_AND_DIRS[$((loop_counter+1))]}";
    if [ ! -d $download_dir ]; then
      logmessage "Download dir \"${cYel}$download_dir${cNone}\" not accessible. ${cRed}Error${cNone}.";
    else
      logmessage "Getting content from ${cYel}\""$(cutSubstring "$feed_url" 64)"\"${cNone}";
      content=$(getFeedContent "$feed_url");
      if [ "${#content}" -ge 17 ]; then
        logmessage -n "Download dir is ";
        if [ -z "$download_dir" ]; then echo -e "${cYel}default${cNone}"; else echo -e "${cYel}$download_dir${cNone}"; fi;

        logmessage "Content length is ${fBold}${#content}${cNone} characters";
        items=$(getXMLparts item "$content");
        logmessage "We found ${fBold}$(wc -l <<< "$items")${cNone} <item> feed section(s)";

        links=$(getXMLparts link "$items");
        links_count=$(wc -l <<< "$links");
        logmessage "And extract ${cGreen}$links_count${cNone} link(s) from <item> section(s)";

        if [ "$links_count" -ge 1 ]; then
          linkNum=1; addedLinks=0; ignoredLinks=0; errorLinks=0;
          while read link; do
            link=$(sed 's/\&amp;/\&/g' <<< "$link"); # Fast buffix, need a better way
            if [ $(existsInHistory "$link") -ne "1" ]; then
              logmessage "Link ${cYel}$linkNum of $links_count${cNone} <${cBlue}"$(cutSubstring "$link" 71)"${cNone}>";
              logmessage -n "Pass to Torrent Client.. ";
              if [ $(addToTransmission "$link" "$download_dir") -eq "1" ]; then
                echo -e ${msgOk};
                logmessage -n "Add to history file.. ";
                if [ $(addToHistory "$link (added $(date "+%d.%m.%Y %H:%M:%S"))") -eq "1" ]; then echo -e ${msgOk}; else echo -e ${msgErr}; fi;
                addedLinks=$((addedLinks+1));
              else
                echo -e ${msgErr};
                errorLinks=$((errorLinks+1));
              fi;
            else
              ignoredLinks=$((ignoredLinks+1));
            fi;
            linkNum=$((linkNum+1));
          done <<< "$links";
          logmessage -n "Passed to Torrent Client ${cGreen}${addedLinks}${cNone} links, ignored (already exists in history file): ${fBold}${ignoredLinks}${cNone}, errors: ";
          if [ "$errorLinks" -ne "0" ]; then echo -ne "${cRed}"; else echo -ne "${fBold}"; fi; echo -e "${errorLinks}${cNone}";
        fi;
      else
        logmessage "Content length is too low, network error or download tool error";
      fi;
    fi;
    echo -e "";
  fi;
  loop_counter=$((loop_counter+1));
done;

if [ "$REMOVE_TRANSMISSION_COMPLETED_TASKS" == "1" ]; then
  logmessage -n "Remove Transmission completed tasks.. ";
  case "$(removeTransmissionCompletedTasks)" in
    0) echo -e ${msgErr};;
    1) echo -e ${msgOk};;
   -1) echo -e "${cYel}Nothing to remove${cNone}";;
  esac;
fi;
