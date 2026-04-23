#!/bin/bash

# Shared build driver for RHH-Ports buildtools/
# Usage: ./build_port.sh <portdir>
# where <portdir> is e.g. buildtools/sonic-mania/sonic-mania

HOSTROOT=`pwd`
DOCKERROOT=/root

PORTDIR=$1
PORTNAME=`basename $PORTDIR`
SRCDIR=$PORTDIR/src
SETUPSCRIPT=$SRCDIR/docker-setup.txt
PRODUCTSCRIPT=$SRCDIR/retrieve-products.txt
BUILDSCRIPT=$SRCDIR/build.txt

BUILDDIR=build-port
CONTAINER=$PORTNAME-build

# Stop any prior container for this port, and clean the shared staging dir
# so a previous port in the same run can't leak its src/* or build outputs.
docker rm -f $CONTAINER 2>/dev/null || true
rm -rf $HOSTROOT/$BUILDDIR
mkdir -p $HOSTROOT/$BUILDDIR
cd $HOSTROOT/$BUILDDIR
cp $HOSTROOT/$SRCDIR/* .

bash $HOSTROOT/$SETUPSCRIPT $PORTNAME-build

sleep 5

docker exec -e FORCE_HEAD=${FORCE_HEAD:-false} $PORTNAME-build /bin/bash -c "cd $BUILDDIR && bash $DOCKERROOT/$BUILDSCRIPT"

bash $HOSTROOT/$PRODUCTSCRIPT $HOSTROOT/$BUILDDIR $HOSTROOT/$PORTDIR
