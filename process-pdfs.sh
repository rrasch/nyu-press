#!/bin/bash
#
# Wrapper script to pdf2pda PDF/A generation script.
#
# Author: Rasan Rasch <rasan@nyu.edu>

trap "" HUP

PDF_DIR=/path/to/pdf/files

NUM_PROC=10

# current date/time, e.g. 2010-07-13-20-14-59
NOW=$(date +"%Y-%m-%d-%H-%M-%S")

# log both stdout/stderr to this file
# LOGFILE=logs/pdfa-$NOW.log
LOGFILE=logs/pdfa.log

LOGDIR=`dirname $LOGFILE`
[ ! -d "$LOGDIR" ] && mkdir -p $LOGDIR

exec >> $LOGFILE 2>&1

echoerr() { echo "$@" 1>&2; }

SAVEIFS=$IFS
IFS=$(echo -en "\n\b")
i=0
declare -a files
declare -a pids
for f in `find "$PDF_DIR" \( ! -name '.*' \) -name '*.pdf'`
do
	if [ ! -f "${f}a" -a ! -f "${f}a.unvalidated" ]; then
		files[i++]=$f
	fi
done
IFS=$SAVEIFS

NUM_FILES=$i
echoerr "number of files $NUM_FILES"

for ((i = 0 ; i < NUM_FILES ; i += NUM_PROC)); do
	MAX_FILE_NUM=$((NUM_FILES < i + NUM_PROC ? NUM_FILES : i + NUM_PROC))
	for ((j = i ; j < MAX_FILE_NUM ; j++)); do
		set -x
		./pdf2pdfa -s "${files[$j]}" "${files[$j]}a.unvalidated" &
		set +x
		pids[j]=$!
	done
	for ((j = i ; j < MAX_FILE_NUM ; j++)); do
		echoerr "Waiting for pid[${pids[$j]}] to finish ... "
		wait ${pids[$j]}
		if [ $? -ne 0 ]; then
			echo "${files[$j]}" >> FAILED.txt
		fi
		echoerr "pid[${pids[$j]}] finished"
	done
	echoerr =================
done

