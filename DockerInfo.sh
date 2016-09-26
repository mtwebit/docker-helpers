#!/bin/bash
# Simple shell script to generate hosts entries for docker containers
# Created by Tamas Meszaros <mt+git@webit.hu>

function show_help() {
cat << EOF
Usage: ${0##*/} [-?] [-c CID] [-inh]
List information about docker hosts
  -?            display this help and exit
  -c <CID>      specify the container ID (can be specified multiple times)
  -i -n -h -s   display IP address, Name, Hostname, Status
EOF
}

if [ ! -x /usr/bin/docker ]; then
  echo "ERROR: Docker is not installed."
  exit 2
fi

if [ "$1" == "" ]; then
  show_help
  exit 0
fi

cids=""
filter=""

while getopts "hsinc:" opt; do
  case "$opt" in
    c) cids="$cids $OPTARG"
       ;;
    i) filter="$filter {{.NetworkSettings.IPAddress }}"
       ;;
    h) filter="$filter {{.Config.Hostname}}"
       ;;
    n) filter="$filter {{.Name}}"
       ;;
    s) filter="$filter {{.State.Status}}"
       ;;
    h) show_help
       exit 0
       ;;
    '?')
       echo "ERROR: Invalid or missing arguments. See -h for help."
       exit 3
       ;;
  esac
done

if [ "$cids" == "" ]; then
  cids="$(docker ps -aq)"
fi

# remove extra whitespaces
filter=$(echo $filter | xargs)

echo docker inspect --format \'$filter\' $cids | sh
