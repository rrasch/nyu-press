#!/bin/bash
#
# Test validity of PDF/A file.
#
# Author: Rasan Rasch <rasan@nyu.edu>

JVM_MEMORY=1024m

set -e

if [ $# -ne 1 ]; then
	echo -e "\nUsage: $0 <input_pdf>\n"
	exit 1
fi

INPUT_FILE="$1"

# Escape filename for jhove
if [[ "$INPUT_FILE" = "${INPUT_FILE% *}" ]]; then
	INPUT_FILE_ESCAPED="$INPUT_FILE"
else
	INPUT_FILE_ESCAPED="\"$INPUT_FILE\""
fi

PROG=`readlink -f $0`

BINDIR=`dirname $PROG`

tmpdir=${TMPDIR:-/tmp}/validate-pdfa.$$

ERR_FILE=$tmpdir/err.txt

trap "rm -rf $tmpdir; exit" EXIT SIGINT SIGQUIT SIGTERM
mkdir $tmpdir || exit 1

jhove -m PDF-hul -h xml $INPUT_FILE_ESCAPED | $BINDIR/verify-jhove-xml.pl

set +e
java \
	-Xmx${JVM_MEMORY} -Xms${JVM_MEMORY} \
	-Dlog4j.configuration=file://$BINDIR/log4j.xml \
	-jar $BINDIR/pdfbox/preflight-app-2.0.0-SNAPSHOT.jar \
	"$INPUT_FILE" &> $ERR_FILE

RETVAL=$?

# cat $ERR_FILE 1>&2
cat $ERR_FILE > /dev/stderr

EX='Exception in thread "main" java.awt.geom.IllegalPathStateException: missing initial moveto in path definition'

if [ $RETVAL -eq 0 ] || grep -q "^$EX" < $ERR_FILE; then
	exit 0
else
	exit 1
fi

