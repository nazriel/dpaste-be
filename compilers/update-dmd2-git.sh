#!/bin/sh

CONTACT_MAIL=""
UPDATE_DPASTE_FRONTEND=0

START_DIR=$(pwd)
BASE_PATH="${START_DIR}/link/dmd2git"
REPO_PATH="${BASE_PATH}/repo"
DMD_PATH="${REPO_PATH}/dmd"
DRUNTIME_PATH="${REPO_PATH}/druntime"
PHOBOS_PATH="${REPO_PATH}/phobos"
PREP_DIR="${REPO_PATH}/prep"

if [ ! -d "${REPO_PATH}" ]; then
	mkdir -p "${REPO_PATH}"
fi
cd $BASE_PATH

errorOut() {
	if [ ! -z "${CONTACT_MAIL}" ]; then
		echo "Failed to update DMD git version" | mail -s "Dpaste update failed" "${CONTACT_MAIL}"
	fi

	echo "Failed to update DMD git version" >> $START_DIR/update.log
	exit 1
}

#
## Build DMD
#
cd "${REPO_PATH}"
if [ ! -d "${DMD_PATH}" ]; then
	git clone --depth 1 https://github.com/D-Programming-Language/dmd.git 
fi

cd "${DMD_PATH}"
git clean -fd  &> /dev/null
git pull --rebase origin master

make -f posix.mak clean AUTO_BOOTSTRAP=1
make -f posix.mak -j8 AUTO_BOOTSTRAP=1

if [ ! -f "${DMD_PATH}/src/dmd" ]; then
	errorOut
fi

#
## Build druntime
#
cd "${REPO_PATH}"
if [ ! -d "${DRUNTIME_PATH}" ]; then
        git clone --depth 1 https://github.com/D-Programming-Language/druntime.git druntime
fi

cd "${DRUNTIME_PATH}"
git clean -fd
git pull --rebase origin master

make -f posix.mak clean
make -f posix.mak -j8 DMD="${DMD_PATH}/src/dmd"

if [ ! -f "${DRUNTIME_PATH}/generated/linux/release/64/libdruntime.a" ]; then
	errorOut
fi

#
## Build phobos
#
cd "${REPO_PATH}"
if [ ! -d "${PHOBOS_PATH}" ]; then
        git clone --depth 1 https://github.com/D-Programming-Language/phobos.git phobos   
fi

cd "${PHOBOS_PATH}"
git clean -fd
git pull --rebase origin master   

make -f posix.mak clean   
make -f posix.mak -j8 DMD="${DMD_PATH}/src/dmd" DRUNTIME_PATH="${DRUNTIME_PATH}" CUSTOM_DRUNTIME="1"   

if [ ! -f "${PHOBOS_PATH}/generated/linux/release/64/libphobos2.a" ]; then
	errorOut
fi

cd "${REPO_PATH}"
rm -rf "${PREP_DIR}"

mkdir -p "${PREP_DIR}/bin"
mkdir -p "${PREP_DIR}/lib64"
mkdir -p "${PREP_DIR}/include"

cp "${DMD_PATH}/src/dmd" "${PREP_DIR}/bin/"
cp -r ${DRUNTIME_PATH}/import/* "${PREP_DIR}/include/"
cp -r ${PHOBOS_PATH}/std "${PREP_DIR}/include/"
cp -r ${PHOBOS_PATH}/etc "${PREP_DIR}/include/"
cp "${PHOBOS_PATH}/generated/linux/release/64/libphobos2.a" "${PREP_DIR}/lib64/"

rm -rf ${BASE_PATH}/bin
rm -rf ${BASE_PATH}/lib32
rm -rf ${BASE_PATH}/lib64
rm -rf ${BASE_PATH}/include
cp -r ${PREP_DIR}/* ${BASE_PATH}/

cd ${DMD_PATH}
git rev-parse HEAD > "${REPO_PATH}/VERSION"

DMD_GIT_VERSION=$(cat "${REPO_PATH}/VERSION")

if [ "x${UPDATE_DPASTE_FRONTEND}" = "x1" ]; then
	curl -s "http://dpaste.dzfl.pl/request/updatedmd2git/?ver=${DMD_GIT_VERSION}"
fi

if [ ! -z "${CONTACT_MAIL}" ]; then
	echo "Update of dmd trunk to ${DMD_GIT_VERSION} successful!" | mail -s "Dpaste update successful" "${CONTACT_MAIL}"
fi
echo "Update of dmd trunk to ${DMD_GIT_VERSION} successful!" >> $START_DIR/update.log
