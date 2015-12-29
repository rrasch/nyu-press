#!/bin/bash
#
# Wrapper script for validate-pdfa.sh
#
# Author: Rasan Rasch <rasan@nyu.edu>

trap "" HUP

PDF_DIR=/content/prod/process/rasch/nyup

# current date/time, e.g. 2010-07-13-20-14-59
NOW=$(date +"%Y-%m-%d-%H-%M-%S")

# log both stdout/stderr to this file
# LOGFILE=logs/validate-$NOW.log
LOGFILE=logs/validate.log

LOGDIR=`dirname $LOGFILE`
[ ! -d "$LOGDIR" ] && mkdir -p $LOGDIR

exec >> $LOGFILE 2>&1

SAVEIFS=$IFS
IFS=$(echo -en "\n\b")
i=0
for f in `find $PDF_DIR/[0-9]* -name '*.pdfa'`
do
	files[i++]=$f
done
IFS=$SAVEIFS

echoerr() { echo "$@" 1>&2; }

NUM_FILES=$i
echoerr "number of files $NUM_FILES"

for ((i = 0 ; i < NUM_FILES ; i += 1)); do
	echoerr ./validate-pdfa.sh "${files[$i]}"
	./validate-pdfa.sh "${files[$i]}"
	echoerr =================
done

