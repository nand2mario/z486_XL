FROM ubuntu:22.04
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates git curl wget gawk diffstat unzip texinfo gcc g++ make \
    build-essential chrpath socat cpio python3 python3-pip python3-pexpect \
    xz-utils debianutils iputils-ping python3-git python3-jinja2 \
    libegl1-mesa libsdl1.2-dev pylint xterm python3-subunit mesa-common-dev \
    zstd liblz4-tool file locales rsync bc bison flex libssl-dev libncurses-dev \
    lzop device-tree-compiler && locale-gen en_US.UTF-8
ARG BUILD_UID=1000
ARG BUILD_GID=1000
RUN groupadd -g ${BUILD_GID} builder && useradd -m -u ${BUILD_UID} -g builder -s /bin/bash builder
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
USER builder
WORKDIR /work
CMD ["bash"]
