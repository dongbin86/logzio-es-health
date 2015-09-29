#!/bin/bash

##############################################
#
# Nagios plugin that monitors the cache that the go.py generated and exit with certin codes as nagios knows and loves.
#
# Exit codes are:
#	0 - Everything is a-ok!
#	1 - Warning
#	2 - Critial
#	3 - Unknown (Should be also conciders as a problem in most cases)
#
# Written by Roi Rav-Hon @ Logz.io
#
# Usage:
#
# docker exec CONTAINER /root/nagios.sh COMPONENT -c CRITICAL -w WARNING
#
#	Components:
#
#		initializing_shards 		(e.g initializing_shards -c 10 -w 5)
#		number_of_pending_tasks		(e.g number_of_pending_tasks -c 100 -w 50)
#		relocating_shards			(e.g relocating_shards -c 10 -w 5)
#		unassigned_shards			(e.g unassigned_shards -c 2 -w 1)
#		status						(e.g -c yellow / -c red -w yellow)
#		mapping_size				(e.g -c 4000000 -w 3000000 (this one is tricky, tune it carefully))
#
##############################################
#
# A word about thread safe -
#
#	Assuming that the write from go.py is super fast so there is no real threat for this script try to read
#	a file that is in the progress of writing down.
#	But if it indeed happenes, this script will exit with exit code 3 which means unknown.
#	Nagios should query it again and everything should be awesome. If not, tell me.
#
##############################################

# Usage function
function usage() {

	echo "docker exec CONTAINER /root/nagios.sh COMPONENT -c CRITICAL -w WARNING"
	echo ""
	echo "Components:"
	echo ""
	echo "	initializing_shards (e.g initializing_shards -w 5 -c 10)"
	echo "	number_of_pending_tasks	(e.g number_of_pending_tasks -c 100 -w 50)"
	echo "	relocating_shards (e.g relocating_shards -w 5 -c 10 )"
	echo "	unassigned_shards (e.g unassigned_shards -c 2 -w 1)"
	echo "	status (e.g -c yellow / -c red -w yellow)"
	echo "	mapping_size (e.g -c 4000000 -w 3000000 (this one is tricky, tune it carefully))"
	echo ""
}

# First sanity check
if [ $# -lt 1 ]; then

	echo "You must choose component!"
	usage
	exit 3
fi

# Declare variables
declare critical=""
declare warning=""
declare component=$1 ; shift # Get the components and removes it from param list, so it will be easier to parse

# And some consts
declare -r CLUSTERSTATE_CACHE="/clusterstate.txt"
declare -r CLUSTERHEALTH_CACHE="/clusterhealth.txt"

# Regular expression to validate that the variables are numbers
re='^[0-9]+$'

# Parsing parameters. Expects all params but the component
function parse_params() {

	# Iterateing over getopts
	while getopts ":c:w:" opt; do
		case $opt in
			c)
				# Check for numerical input. in case of status, allow string (yellow, red)
				if [[ $OPTARG =~ $re || "$component" == "status" ]]; then
					
					# Set critical
					critical=$OPTARG
				else
					echo "-c Must get a number argument. $OPTARG is not valid."
					usage
					exit 3
				fi
				;;
			w)
				# Check for numerical input. in case of status, allow string (yellow, red)
				if [[ $OPTARG =~ $re || "$component" == "status" ]]; then
					
					# Set warning
					warning=$OPTARG
				else
					echo "-w Must get a number argument. $OPTARG is not valid."
					usage
					exit 3
				fi
				;;
			:) # No optarg was supplied
				echo "Option -$OPTARG requires a number argument"
				usage
				exit 3
				;;
			*) # Unknown parameter
				echo "Unknown option: -$OPTARG"
				usage
				exit 3
		esac
	done
}

function check_warning() {

	# Is the warning param set?
	if [ "$warning" == "" ]; then

		return 1
	fi
}

function check_critical() {
	
	# Is the critical param set?
	if [ "$critical" == "" ]; then

		return 1
	fi
}

function parse_cache_file() {

	# Default file
	local parsing_file="$CLUSTERHEALTH_CACHE"

	# Overriding default in case of mapping size query
	if [ "$component" == "mapping_size" ]; then

		parsing_file="$CLUSTERSTATE_CACHE"
	fi

	# Lets get the number!
	cache=$(cat $parsing_file | grep -i "$component" | cut -d: -f2)

	if [ "$cache" == "" ]; then

		echo "Did not find any cache for your component."
		echo "Either that the cache file is in writing now or there is something else bad."
		echo "Is the docker sending correct logs?"
		echo "Anyway, bailing out."
		exit 3
	fi

	# Verify that this is a number
	if ! [[ "$cache" =~ $re ]]; then

		# Cache is not a number.. must be a bug
		echo "Somehow the reading from the cache is there, but its not a number."
		echo "That is what i got: $cache"
		echo "Its probably a bug, please report that."

	fi

	# Print it out so we can catch that
	echo $cache
}

# For the sake of reuse, master function for all numerical values
function process_numerical_values() {

	# Check that both critical and warning supplied
	if ! ( check_critical && check_warning ); then

		echo "You must set both -c and -w to use $component"
		usage
		exit 3
	fi

	# We need to validate that critical is higher then warning, else it doesnt make sense
	if [ $critical -le $warning ]; then

		echo "Critical ($critical) cannot be less or equal to warning ($warning) threshold!"
		exit 3
	fi

	# Get the cached result
	local -i cached_result=$(parse_cache_file)

	# Now match it against the warning or the critical ones
	if [ $cached_result -ge $critical ]; then

		echo "CRITICAL: $component is: $cached_result, which is higher or equal to the critical threshold: $critical | $component: $cached_result"
		exit 2
	fi

	# And match the warning
	if [ $cached_result -ge $warning ]; then

		echo "WARNING: $component is: $cached_result, which is higher or equal to the warning threshold: $warning | $component: $cached_result "
		exit 1
	fi

	echo "OK: $component is $cached_result | $component: $cached_result"
	exit 0
}

function main() {
	
	# Parsing all parameters
	parse_params "$@"

	# Act as the component want
	case $component in
		"initializing_shards")
				
				# Process the alert
				process_numerical_values
			;;

		"number_of_pending_tasks")

				# Process the alert
				process_numerical_values
			;;

		"relocating_shards")
			
				# Process the alert
				process_numerical_values
			;;

		"unassigned_shards")
			
				# Process the alert
				process_numerical_values
			;;

		"status")
				
				# Get the cached result
				local cached_result="$(cat $CLUSTERHEALTH_CACHE | grep -i $component | cut -d: -f2)"

				# This case is special because of use of strings, and allow without warning
				# So lets check if the critical and warning are both set
				if ( check_critical && check_warning ); then

					# Both critical and warning are set, so only one way to run it
					if [[ "$critical" != "red" || "$warning" != "yellow" ]]; then

						echo "I know it seems like you have a choise here, but the only way it make sense is: "
						echo "-c red -w yellow"
						echo "So, fix it and run again.."
						exit 3
					fi

					if [ "$cached_result" == "yellow" ]; then

						echo "WARNING: Cluster status is yellow! | status: yellow"
						exit 1

					elif [ "$cached_result" == "red" ]; then
						echo "CRITICAL: Cluster status is red! | status: red"
						exit 2

					elif [ "$cached_result" == "green" ]; then

						echo "OK: Cluster status is green! | status: green"
						exit 0
					else

						echo "Unknown cluster status: $cached_result"
						echo "Its probably a bug, please report that."
						exit 3
					fi
				
				# Only critical is set
				elif check_critical; then

					# Check if its either red or yellow
					if ! echo "$critical" | egrep -q "^red$|^yellow$" ; then

						echo "Cluster status must be one of: red, yellow"
						echo "$critical make no sense."
						exit 3
					fi
					
					# Matching the result to the requested critical
					if [ "$critical" == "$cached_result" ]; then

						echo "CRITICAL: Cluster status is $cached_result! | status: $cached_result"
						exit 2
					else

						echo "OK: Cluster status is $cached_result! | status: $cached_result"
						exit 0
					fi
				else
				
					# No threshold! bailing..
					echo "You must set or both warning and critical, or just critical to use status component."
					usage
					exit 3
				fi
			;;

		"mapping_size")
			
				# Process the alert
				process_numerical_values
			;;
		*)
				echo "Unknown component: $component"
				usage
				exit 3
	esac
}

main "$@"