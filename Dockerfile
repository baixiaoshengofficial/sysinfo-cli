# Dockerfile for testing sysinfo-cli
# Primary target: Debian/Ubuntu family; install.sh also supports RHEL/Fedora/Alpine/Arch/openSUSE.
FROM debian:bookworm-slim

# Avoid interactive prompts during apt install
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies required by sysinfo-cli:
# - iproute2: tc, ip (traffic control / interface introspection)
# - procps: free, ps, uptime, sysctl
# - bc: large-number math (optional but used when available)
# - curl/wget: download yq and remote install path
# - sudo: run_privileged() fallback when not root
# - ca-certificates: HTTPS for curl/wget
# - kmod: modprobe for IFB kernel module
# - coreutils, gawk, sed, grep: standard utilities
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
    && rm -rf /var/lib/apt/lists/*

# Install yq (mikefarah/yq) - required by sysinfo-cli for YAML parsing
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

# Copy project source into container
WORKDIR /opt/sysinfo-cli
COPY . /opt/sysinfo-cli/

# Ensure scripts are executable
RUN chmod +x /opt/sysinfo-cli/src/*.sh \
    /opt/sysinfo-cli/scripts/*.sh \
    /opt/sysinfo-cli/*.sh \
    /opt/sysinfo-cli/install.sh \
    /opt/sysinfo-cli/uninstall.sh \
    /opt/sysinfo-cli/tests/test_sysinfo.sh 2>/dev/null || true

# Default command: bash shell for interactive testing
CMD ["/bin/bash"]
