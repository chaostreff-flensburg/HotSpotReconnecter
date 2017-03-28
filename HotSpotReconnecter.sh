#!/bin/bash

#set colors
LIGHTRED='\033[1;31m'
RED='\033[0;31m'
BLUE='\033[0;34m'
LIGHTGREEN='\033[1;32m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

#privilege check
if [ $(id -u) -ne 0 ]; then
  echo -e "$LIGHTRED Please run as root$NC"
  exit
fi

clear

#declare variables/ arguments
allowedbytes=200000000
checkuptime=10
confirm=false
reset=false
interface="wlan0"
lastresettimestamp="-"

#get initial rx bytes for cycle so no initial reset happens
ifconfig=$(ifconfig | tr -d '\n')
ifconfig=$(echo "$ifconfig" | grep -oP "$interface.{1,2000}RX bytes:\d{1,10240}")
#get received bytes
rxbytes=$(echo "$ifconfig" | grep -oP "(?<=RX bytes:)\d{1,10240}")

#compute received bytes / max bytes
cycle=$(( $rxbytes / $allowedbytes ))

#read arguments
while getopts 't:l:i:rhc' flag; do
  case "${flag}" in
    t) checkuptime=${OPTARG} ;;
    l) allowedbytes=$((${OPTARG} * 1000000))
       cycle=$(( $rxbytes / $allowedbytes )) ;;
    i) interface=${OPTARG} ;;
    r) reset=true ;;
    c) confirm=true ;;
    h) echo -e "				${LIGHTGREEN}HotSpotReconnecter${NC}"
       echo -e "\nThis Script periodically checks your Traffic and reconnects you with a new random MAC-Address, if you hit a previously set Data-Limit. Especially useful for public WiFis!"
       echo -e "\nArguments:\n"
       echo -e "-t [ARG]	Time between Traffic Checkups (in Seconds), Default: 10"
       echo -e "-l [ARG]	Data-Limit after which to perform reconnect (in MB), Default: 200"
       echo -e "-i [ARG]	Network Interface to check and reset, Default: wlan0"
       echo -e "-c		Ask for User Confirmation before performing a reset"
       echo -e "-r		Perform a reset with a new MAC right at the Start"
       echo -e "-h		This help.\n"
       exit ;;
    *) error "Unexpected option ${flag}" ;;
  esac
done

#main program loop
while [ true ]; do
	#set timestamp
	lastchecktimestamp=$(date '+%X')
	nextchecktimestamp=$(date '+%X' --date="$checkuptime seconds")
	
	#get ifconfig
	ifconfig=$(ifconfig | tr -d '\n')
	ifconfig=$(echo "$ifconfig" | grep -oP "$interface.{1,2000}RX bytes:\d{1,10240}")

	#get received bytes & megabytes & remaining megabytes
	rxbytes=$(echo "$ifconfig" | grep -oP "(?<=RX bytes:)\d{1,10240}")
	rxmegabytes=$(( $rxbytes / 1000000 ))
	remainingmegabytes=$(( ($allowedbytes / 1000000) - $rxmegabytes % ($allowedbytes / 1000000) ))
	
	
	#get current mac address
	iwint=$(ip link show $interface | tr -d '\n')
	macaddr=$(echo "$iwint" | grep -oP "(?<=link\/ether\s).{1,17}")

	#compute modulo of received bytes / max bytes
	newcycle=$(( $rxbytes / $allowedbytes ))
	
	#outputs
	echo -e "				${LIGHTGREEN}HotSpotReconnecter${NC}\n"
	echo -e "Received MB: 	$LIGHTGREEN$rxmegabytes$NC"
	echo -e "Remaining MB: 	$LIGHTRED$remainingmegabytes$NC"
	echo -e "MAC Address: 	$BLUE$macaddr$NC"
	echo -e "Last Reset:	$YELLOW$lastresettimestamp$NC"
	echo -e "Last Checkup:	$PURPLE$lastchecktimestamp$NC"
	echo -e "Next Checkup:	$CYAN$nextchecktimestamp$NC"

	#check if received bytes exceeds limit
	if [[ $newcycle -ne $cycle ]] || [ $reset = true ]; then
		#reset flag to false so it is only used once
		reset=false

		echo -e "\nLimit reached, switching MAC Address..."
		
		#compute random MAC address
		newmacaddr=$(hexdump -n3 -e'/3 "00:60:2F" 3/1 ":%02X"' /dev/random)
	
		echo -e "New MAC Address will be $BLUE$newmacaddr$NC"

		#if confirm flag is set, check for user confirmation before resetting connection
		if [ $confirm = true ]; then
			echo -e "\nDo you wish to reset the connection now (or always without confirmation)?"
			select input in "Yes" "Cancel" "Always"; do
			    case $input in
				Yes ) break;;
				Cancel ) exit;;
				Always ) confirm=false
					 break;;
			    esac
			done
		fi
		
		#stop network manager
		sudo service network-manager stop > /dev/null
		#take interface down
		sudo ifconfig $interface down
		#change MAC address
		sudo ip link set dev $interface address $newmacaddr
		#restart interface
		sudo ifconfig $interface up
		#restart network manager
		sudo service network-manager start > /dev/null

		#save reset timestamp
		lastresettimestamp=$(date '+%X')

		#save new cycle count
		cycle=$newcycle
	
		echo -e "\n$LIGHTGREEN$interface$NC restarted with new MAC Address!"
	fi
	
	sleep $checkuptime;
	
	#clear display
	clear
done
