#!/bin/bash
#
# Compile svn version of pdfbox

cd ~/pdfbox-svn
mvn clean
svn up
mvn clean install
rm -vf ~/work/content_publishing/nyup/trunk/pdfbox/*2.0.0-SNAPSHOT.jar
find ~/pdfbox-svn -name '*2.0.0-SNAPSHOT.jar' | grep -v war | xargs -I{} cp -fv {} ~/work/content_publishing/nyup/trunk/pdfbox

