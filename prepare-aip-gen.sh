#!/bin/bash
#
# Prepare AIP generation by splitting ONIX files and copying
# content to working directory.
#
# Author: Rasan Rasch <rasan@nyu.edu>

set -e

# only works if LOGFILE is not set to 'tee'
trap "" HUP

DROPBOX_DIR=/path/to/dropbox

WORK_DIR=/path/to/work/dir

# log both stdout/stderr to this file
LOGFILE=logs/prepare.log

LOGDIR=`dirname $LOGFILE`
[ ! -d "$LOGDIR" ] && mkdir -p $LOGDIR

# exec >> $LOGFILE 2>&1
# exec 1> >(tee -a $LOGFILE) 2>&1
exec 1> >(tee $LOGFILE) 2>&1

rm -rf $WORK_DIR
mkdir -p $WORK_DIR/{tmp,valid}

for ONIX_FILE in $DROPBOX_DIR/2014-*/*_onix.xml
do
	SUBMIT_DIR=`dirname "$ONIX_FILE"`
	cp -a "$SUBMIT_DIR"/* $WORK_DIR
	./split-onix.pl -f -p "${WORK_DIR}/" "$ONIX_FILE"
done

rm -rf $WORK_DIR/NYUP*_onix.xml

# for ONIX_FILE in `cd $WORK_DIR; ls *_onix.xml`
# do
# 	ISBN=${ONIX_FILE%_onix.xml}
# 	echo $ISBN
# done

