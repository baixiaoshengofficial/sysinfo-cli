#!/bin/bash
# Build install-test images for all supported distros.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKER="${ROOT}/scripts/docker-cmd.sh"
DF="${ROOT}/docker/Dockerfile.install-test"

DISTROS=(
  'debian|debian:bookworm-slim'
  'ubuntu|ubuntu:24.04'
  'fedora|fedora:40'
  'rocky|rockylinux:9'
  'alpine|alpine:3.20'
  'arch|archlinux:latest'
  'opensuse|opensuse/leap:15.6'
  'openwrt|openwrt/rootfs:x86_64-24.10.7'
)

echo "=== Building sysinfo-cli install-test images ==="
for entry in "${DISTROS[@]}"; do
    IFS='|' read -r id image <<<"$entry"
    tag="sysinfo-cli:test-${id}"
    printf '>> %s (%s) -> %s\n' "$id" "$image" "$tag"
    "$DOCKER" build -f "$DF" --build-arg "BASE_IMAGE=${image}" -t "$tag" "$ROOT"
done
echo "Done."
