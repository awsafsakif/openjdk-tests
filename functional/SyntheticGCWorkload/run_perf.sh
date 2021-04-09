#!/usr/bin/env bash
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Perf script for concurrentSlack=auto.  
# 
# The exit code will be 0 if the test passes and nonzero otherwise. 
#

DATE_TIME=`date "+%Y-%m-%dT_%H-%M-%S"`

# Source for config files 
CONFIG_DIR="config"

LOG_DIR="$1"
JDK_TEST_COMMAND="$2"
VM_OPTIONS_BASE="$3"

# Run the workload $CONFIG using $VM_OPTIONS and $HEAP sending output to $VERBOSE_FILE and $STDOUT_FILE
run_workload(){	
	STDOUT_FILE=$LOG_BASE"_stdout_"$LOG_SUFFIX".txt"	
  
	echo "Start time: "`date "+%Y-%m-%dT_%H-%M-%S"`
	echo "Workload configuration: "$CONFIG
	echo "Options: "$VM_OPTIONS
	echo "Heap: "$HEAP
	TEST_CMD=$JDK_TEST_COMMAND" "$VM_OPTIONS" -Xverbosegclog:"$VERBOSE_FILE" -cp .:SyntheticGCWorkload.jar net.adoptopenjdk.casa.workload_sessions.Main "$CONFIG" --log_file "$STDOUT_FILE" -s"
	echo "run_workload() - Command: "$TEST_CMD
	
	$TEST_CMD
}

numCompare() {
   awk -v n1="$1" -v n2="$2" 'BEGIN {printf (n1<n2?"1":"0")}'
}

parse_gclog(){
	file=$1
	size=$2

	readarray arr < <(grep "<gc-end" $file)
	declare -a gc_types

	for i in "${arr[@]}"
	do
		: 
		gc_type=`echo $i | awk '{print $3}' | cut -d '"' -f2`
		gc_duration=`echo $i | awk '{print $5}' | cut -d '"' -f2`
		gc_count=${gc_type}_count
		gc_max=${gc_type}_max
		
		if [[ " ${gc_types[@]} " =~ " ${gc_type} " ]]; then
			eval $gc_count=$((gc_count+1))
			eval $gc_type="$(awk -v a="$gc_duration" -v b="${!gc_type}" 'BEGIN{print a+b}')"
        	if [[ "$(numCompare ${!gc_max} $gc_duration)" -eq 1 ]] ; then
            	eval $gc_max=$gc_duration
        	fi
		fi

		if [[ ! " ${gc_types[@]} " =~ " ${gc_type} " ]]; then
		gc_types+=(${gc_type})
		eval $gc_count=1
		eval $gc_type=$gc_duration
		eval $gc_max=$gc_duration
		fi
	done

	echo "Config Size: $size"
	echo "No. of Total GC: ${#arr[@]}"
	echo "GC Types (separated by space): ${gc_types[@]}"

	for i in "${gc_types[@]}"
	do
		echo -n "Type: $i, sum: ${!i}, count: "
		sum=${!i}
		gc_count=${i}_count
		gc_max=${i}_max
		average="$(awk -v a="$sum" -v b="${!gc_count}" 'BEGIN{print a/b}')"
		echo "${!gc_count}, average: $average, max: ${!gc_max}"

	done
}

for a in "1k" "10k" "100k" "1M" "10M"
do 
    SIZE=$a
    # Try to list configuration versions of the requested size. 
    CONFIG_VERSIONS="`ls "$CONFIG_DIR"/"perf_config_""$SIZE""_"*".xml"`" || exit 4
    # Pick the last one. 
    CONFIG="`ls $CONFIG_VERSIONS | sort -n | tail -1`"
    # Get the name of the configuration 
    CONFIG_NAME="${CONFIG##*/}"
    #######################################

    # Prefix for all log files
    LOG_BASE=$LOG_DIR"/"$CONFIG_NAME"_"$DATE_TIME

    VM_OPTIONS=$VM_OPTIONS_BASE	
	LOG_SUFFIX="original"
	VERBOSE_FILE=$LOG_BASE"_verbose_"$LOG_SUFFIX".xml"	
	
	VERBOSE_1=$VERBOSE_FILE
	run_workload
	parse_gclog $VERBOSE_FILE $SIZE
done

exit 0
