FROM debian:bullseye

ENV DEBIAN_FRONTEND=noninteractive

RUN dpkg --add-architecture arm64 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates curl wget git \
        build-essential pkg-config make \
        binutils-aarch64-linux-gnu \
        gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
        libstdc++-10-dev-arm64-cross linux-libc-dev-arm64-cross \
        libsdl2-dev:arm64 libzip-dev:arm64 \
        python3 python3-clang \
        yasm nasm \
        squashfs-tools \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /root
CMD ["bash"]
