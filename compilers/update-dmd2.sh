#!/bin/sh

CONTACT_MAIL=""
UPDATE_DPASTE_FRONTEND=0
START_DIR=$(pwd)

cd ./link

NEWEST_VERSION=$(curl -s http://ftp.digitalmars.com/LATEST)
NEWEST_VERSION_TRIMMED=$(echo $NEWEST_VERSION | tr -d '.')
CURRENT_VERSION=0

if [ -f "dmd2/VERSION" ]; then 
	CURRENT_VERSION=$(cat dmd2/VERSION | tr -d '.')
fi

errorOut() {
	if [ ! -z "${CONTACT_MAIL}" ]; then
		echo "Failed to update from $CURRENT_VERSION to $NEWEST_VERSION_TRIMMED" | mail -s "Dpaste update failed" "${CONTACT_MAIL}"  
	fi

	echo "Failed to update from $CURRENT_VERSION to $NEWEST_VERSION_TRIMMED" >> $START_DIR/update.log
	exit 1
}

if [ $CURRENT_VERSION -lt $NEWEST_VERSION_TRIMMED ]; then
# do update
	#rm -rf tmp
	mkdir tmp
	cd tmp
	wget -q "http://downloads.dlang.org/releases/2.x/${NEWEST_VERSION}/dmd.${NEWEST_VERSION}.linux.zip" -c
	if [ ! -f "dmd.${NEWEST_VERSION}.linux.zip" ]; then
		errorOut
	fi

	unzip "dmd.${NEWEST_VERSION}.linux.zip" &> /dev/null

	if [ ! -d "dmd2" ] || [ ! -d "dmd2/linux" ]; then
		errorOut
	fi
	cd dmd2
	mv linux/* ../
	mkdir ../include
	mv src/druntime/src/{core,etc,object.d} ../include
	mv src/phobos/std ../include
	mv src/phobos/etc/* ../include/etc

	cd ../../
	mv dmd2 dmd2-${CURRENT_VERSION}
	mv tmp dmd2
	echo "${NEWEST_VERSION}" > dmd2/VERSION

	if [ "x${UPDATE_DPASTE_FRONTEND}" = "x1" ]; then
		curl -s "http://dpaste.dzfl.pl/request/updatedmd2/?ver=${NEWEST_VERSION}"
	fi

	if [ ! -z "${CONTACT_MAIL}" ]; then	
		echo "Update from $CURRENT_VERSION to $NEWEST_VERSION_TRIMMED successful!" | mail -s "Dpaste update successful" "${CONTACT_MAIL}"
	fi
	echo "Update from $CURRENT_VERSION to $NEWEST_VERSION_TRIMMED successful!" | mail -s "Dpaste update successful" "${CONTACT_MAIL}" >> $START_DIR/update.log
fi
