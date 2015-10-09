#!/bin/sh

echo "Make sure you have following software installed on your system:"
echo "dmd, dub, make, gcc, g++, screen, kvm (qemu-kvm)"
echo "Should I continue? (y/n)"
read anw

if [ ! "x$anw" = "xy" ]; then 
	exit 0
fi

echo "Updating submodules..."
git submodule update --init
git submodule foreach git submodule update --init

echo "Building daemon..."
cd app
dub build

echo "Building worker..."
cd worker
dub build

echo "Fetching default set of compilers..."
cd ../../compilers
./update-dmd2.sh
./update-dmd2-git.sh
#./update-ldc2.sh
./update-gdc2.sh

cd ../container
echo "Fetching KVM..."
./fetch.sh

echo "Running KVM instance..."
screen ./run.sh

