#!/bin/sh
# Install minimal host prerequisites so install.sh can run (bash/sudo/curl/procps).
# Used by tests/docker_distros.sh and docker/Dockerfile.install-test.
set -e

if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        bash sudo curl ca-certificates procps
elif command -v dnf >/dev/null 2>&1; then
    if rpm -q curl-minimal >/dev/null 2>&1; then
        dnf install -y -q bash sudo procps-ng ca-certificates
    else
        dnf install -y -q bash sudo curl ca-certificates procps-ng
    fi
elif command -v yum >/dev/null 2>&1; then
    if rpm -q curl-minimal >/dev/null 2>&1; then
        yum install -y -q bash sudo procps-ng ca-certificates
    else
        yum install -y -q bash sudo curl ca-certificates procps-ng
    fi
elif command -v opkg >/dev/null 2>&1; then
    mkdir -p /var/lock
    opkg update
    opkg install bash curl ca-certificates procps-ng
elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache bash sudo curl ca-certificates procps
elif command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm --needed bash sudo curl ca-certificates procps-ng
elif command -v zypper >/dev/null 2>&1; then
    zypper -n ref
    zypper -n in -y bash sudo curl ca-certificates procps
else
    echo "bootstrap-test.sh: no supported package manager found" >&2
    exit 1
fi
