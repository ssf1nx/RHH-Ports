#!/bin/bash
set -e

# Shared Docker setup driver used by buildtools/build_port.sh for every port.
# Builds the port's per-port image (which extends rhh-base) and starts a
# long-running container for `docker exec` to target.
#
# Usage: docker-setup.sh <container-name>
#   The current working directory must contain the port's src/ files already
#   staged there by build_port.sh (Dockerfile, build.txt, retrieve-products.txt).
#   The rhh-base image must already exist; build_port.sh ensures this.

NAME=$1
ARCH=aarch64

docker build --platform linux/${ARCH} -t ${NAME} .

if tty -s; then
  echo INTERACTIVE
  docker run -it -v `realpath ..`:/root --name=${NAME} --hostname=${NAME} \
    ${NAME}
else
  echo NONINTERACTIVE
  docker run -v `realpath ..`:/root --name=${NAME} --hostname=${NAME} \
    ${NAME} /bin/bash -c "sleep infinity" &
fi
