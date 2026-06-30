# Dev / interactive test image (Debian). For multi-distro install validation see:
#   docker/Dockerfile.install-test   — build per distro (ARG BASE_IMAGE)
#   make docker-build-distros        — build all 8 install-test images
#   make docker-test-distros         — runtime install smoke test (volume mount)
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# Extra dev packages (bc, kmod, …) beyond what install.sh pulls on a minimal host.
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        iproute2 \
        procps \
        bc \
        curl \
        wget \
        sudo \
        ca-certificates \
        kmod \
        coreutils \
        gawk \
        sed \
        grep \
        bash \
    && rm -rf /var/lib/apt/lists/*

ARG YQ_VERSION=v4.44.3
ARG TARGETARCH
RUN case "${TARGETARCH:-amd64}" in \
        amd64) YQ_ASSET=yq_linux_amd64 ;; \
        arm64) YQ_ASSET=yq_linux_arm64 ;; \
        arm)   YQ_ASSET=yq_linux_arm ;; \
        386)   YQ_ASSET=yq_linux_386 ;; \
        *)     YQ_ASSET=yq_linux_amd64 ;; \
    esac && \
    curl -sSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_ASSET}" \
        -o /usr/local/bin/yq && \
    chmod +x /usr/local/bin/yq

WORKDIR /opt/sysinfo-cli
COPY . /opt/sysinfo-cli/

RUN chmod +x /opt/sysinfo-cli/src/*.sh \
    /opt/sysinfo-cli/scripts/*.sh \
    /opt/sysinfo-cli/docker/*.sh \
    /opt/sysinfo-cli/*.sh \
    /opt/sysinfo-cli/install.sh \
    /opt/sysinfo-cli/uninstall.sh \
    /opt/sysinfo-cli/tests/test_sysinfo.sh 2>/dev/null || true

CMD ["/bin/bash"]
