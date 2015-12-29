#!/bin/bash

trap "" HUP

set -e

# current date/time, e.g. 2010-07-13-20-14-59
NOW=$(date +"%Y-%m-%d-%H-%M-%S")

# log both stdout/stderr to this file
# LOGFILE=logs/nyup-import-$NOW.log
LOGFILE=logs/nyup-import.log

LOGDIR=`dirname $LOGFILE`
[ ! -d "$LOGDIR" ] && mkdir -p $LOGDIR

exec >> $LOGFILE 2>&1

touch results.txt

# XML_FILE_LIST=`echo [0-9][0-9]*.xml`
# 
# for XML_FILE in $XML_FILE_LIST

ISBN_LIST="9780814706404 9780814713266 9780814718766 9780814735305 9780814737552 9780814751008 9780814754740 9780814755969 9780814757970 9780814774632"

for ISBN in $ISBN_LIST
do
# 	ISBN=`echo $XML_FILE | sed 's/\.xml$//'`
	if grep -q $ISBN results.txt; then
		echo "Skipping $ISBN, already processed."
		continue
	fi
	echo Processing $ISBN
	./nyup-import.pl $ISBN
	RETVAL=$?
	if [ $RETVAL -eq 0 ]; then
		STATUS=PASS
	else
		STATUS=FAIL
	fi
	echo "$ISBN: $STATUS" >> results.txt
	sleep 60
done

