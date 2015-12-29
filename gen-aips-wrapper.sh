#!/bin/bash
#
# Wrapper script for gen-aips.pl
#
# Author: Rasan Rasch <rasan@nyu.edu>

trap "" HUP

WORK_DIR=/path/to/work/dir

LOGFILE=logs/aip.log

LOGDIR=`dirname $LOGFILE`
[ ! -d "$LOGDIR" ] && mkdir -p $LOGDIR

# exec >> $LOGFILE 2>&1
# exec 1> >(tee -a $LOGFILE) 2>&1
exec 1> >(tee $LOGFILE) 2>&1

for onix_file in $WORK_DIR/[0-9]*_onix.xml
do
	./gen-aips.pl "$onix_file"
done

