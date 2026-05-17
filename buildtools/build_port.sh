#!/bin/bash

# Shared build driver for RHH-Ports buildtools/
# Usage: ./build_port.sh <portdir>
# where <portdir> is e.g. buildtools/sonic/rsdkv4/rsdkv4

set -e

HOSTROOT=`pwd`
DOCKERROOT=/root
BUILDTOOLS=$HOSTROOT/buildtools

PORTDIR=$1
PORTNAME=`basename $PORTDIR`
SRCDIR=$PORTDIR/src
SETUPSCRIPT=$BUILDTOOLS/docker-setup.sh
PRODUCTSCRIPT=$SRCDIR/retrieve-products.txt
BUILDSCRIPT=$SRCDIR/build.txt

BUILDDIR=build-port
CONTAINER=$PORTNAME-build

if grep -q '^FROM rhh-base' "$SRCDIR/Dockerfile"; then
    if ! docker image inspect rhh-base >/dev/null 2>&1; then
        echo "Building rhh-base image..."
        docker build --platform linux/aarch64 -t rhh-base -f $BUILDTOOLS/Dockerfile.base $BUILDTOOLS
    fi
fi

# Stop any prior container for this port, and clean the shared staging dir
# so a previous port in the same run can't leak its src/* or build outputs.
docker rm -f $CONTAINER 2>/dev/null || true
sudo rm -rf $HOSTROOT/$BUILDDIR
mkdir -p $HOSTROOT/$BUILDDIR
cd $HOSTROOT/$BUILDDIR
cp $HOSTROOT/$SRCDIR/* .

bash $SETUPSCRIPT $CONTAINER

sleep 5

docker exec -e FORCE_HEAD=${FORCE_HEAD:-false} $CONTAINER /bin/bash -c "cd $BUILDDIR && bash $DOCKERROOT/$BUILDSCRIPT"

bash $HOSTROOT/$PRODUCTSCRIPT $HOSTROOT/$BUILDDIR $HOSTROOT/$PORTDIR
