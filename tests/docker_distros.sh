#!/bin/bash
# Smoke-test install.sh on multiple Linux distros via Docker.
# Usage: bash tests/docker_distros.sh [distro_id ...]
#   distro_id: debian ubuntu fedora rocky alpine arch opensuse openwrt
#   REGRESSION=1 bash tests/docker_distros.sh [distro_id ...]
#
# Docker access (no pkexec prompts):
#   1) User in group 'docker' (recommended): sudo usermod -aG docker $USER
#   2) Password sudo: copy .docker-sudo.example -> .docker-sudo (gitignored)
#      or export DOCKER_SUDO_PASSWORD=...
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKER="${REPO_ROOT}/scripts/docker-cmd.sh"
FAIL=0
PASS=0
RUN_TIMEOUT="${RUN_TIMEOUT:-360}"
DOCKER_PLATFORM="${DOCKER_PLATFORM:-linux/amd64}"
REGRESSION="${REGRESSION:-0}"
REPORT="${REPO_ROOT}/tests/docker_distros_report.md"

# id|base_image
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

log_pass() { printf '  \033[32m[PASS]\033[0m %s\n' "$1"; PASS=$((PASS + 1)); }
log_fail() { printf '  \033[31m[FAIL]\033[0m %s\n' "$1"; FAIL=$((FAIL + 1)); }

FILTER_ARGS=("$@")

if [ ! -x "$DOCKER" ]; then
    chmod +x "$DOCKER" "$REPO_ROOT/docker/bootstrap-test.sh" 2>/dev/null || true
fi

if ! "$DOCKER" info >/dev/null 2>&1; then
    echo "Error: cannot talk to Docker daemon via $DOCKER"
    echo "  Hint: sudo usermod -aG docker \$USER  OR  cp .docker-sudo.example .docker-sudo"
    exit 1
fi

echo "=== sysinfo-cli multi-distro Docker install test ==="
echo "Repo: $REPO_ROOT"
echo "Docker: $DOCKER"
echo "Timeout per distro: ${RUN_TIMEOUT}s"
echo "Platform: ${DOCKER_PLATFORM}"
if [ "$REGRESSION" = "1" ] || [ "$REGRESSION" = "true" ]; then
    echo "Mode: regression"
else
    echo "Mode: smoke"
fi
echo ""

{
    echo "# Docker multi-distro install report"
    echo ""
    echo "- Time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "- Repo: \`$REPO_ROOT\`"
    echo "- Platform: \`$DOCKER_PLATFORM\`"
    if [ "$REGRESSION" = "1" ] || [ "$REGRESSION" = "true" ]; then
        echo "- Mode: \`regression\`"
    else
        echo "- Mode: \`smoke\`"
    fi
    echo ""
    echo "| Distro | Image | Result |"
    echo "|--------|-------|--------|"
} >"$REPORT"

want_distro() {
    local id="$1"
    shift
    if [ "$#" -eq 0 ]; then
        return 0
    fi
    local f
    for f in "$@"; do
        [ "$f" = "$id" ] && return 0
    done
    return 1
}

run_one() {
    local id="$1" image="$2"
    local logfile shell="bash" sysinfo_smoke
    local docker_extra_args=()
    case "$id" in alpine|openwrt) shell="sh" ;; esac
    case "$id" in arch) docker_extra_args+=(--security-opt seccomp=unconfined) ;; esac
    if [ "$id" = "openwrt" ]; then
        sysinfo_smoke='sysinfo 2>&1 | head -40 | grep -qiE '\''CPU|System Information|系统信息'\'''
    else
        sysinfo_smoke='timeout 4 sysinfo 2>&1 | grep -qiE '\''CPU|System Information|系统信息'\'''
    fi
    logfile="$(mktemp -t "sysinfo-docker-${id}.XXXXXX")"

    printf '>> %s (%s)\n' "$id" "$image"

    local regression_cmd=':'
    if [ "$REGRESSION" = "1" ] || [ "$REGRESSION" = "true" ]; then
        regression_cmd='bash /opt/sysinfo-cli/tests/docker_regression.sh'
    fi

    local docker_run=("$DOCKER" run --rm --platform "$DOCKER_PLATFORM" "${docker_extra_args[@]+"${docker_extra_args[@]}"}" \
        -v "$REPO_ROOT:/opt/sysinfo-cli" \
        -w /opt/sysinfo-cli \
        "$image" "$shell" -lc "
            set -e
            sh /opt/sysinfo-cli/docker/bootstrap-test.sh
            rm -f /usr/local/bin/yq
            bash install.sh --lang en
            /usr/local/bin/yq --version | grep -qi mikefarah
            command -v tc >/dev/null || [ -x /usr/sbin/tc ]
            command -v ip >/dev/null || [ -x /usr/sbin/ip ]
            sysinfo -h 2>&1 | grep -qi sysinfo
            ${sysinfo_smoke}
            /usr/local/bin/yq eval '.display.language' /etc/sysinfo/config.yaml | grep -qE 'en|zh|auto'
            ${regression_cmd}
        ")

    if command -v timeout >/dev/null 2>&1; then
        docker_run=(timeout "$RUN_TIMEOUT" "${docker_run[@]}")
    fi

    if ! "${docker_run[@]}" >"$logfile" 2>&1; then
        log_fail "$id — see $logfile"
        echo "| $id | \`$image\` | FAIL |" >>"$REPORT"
        tail -n 30 "$logfile" | sed 's/^/      /'
        return 1
    fi

    rm -f "$logfile"
    log_pass "$id"
    echo "| $id | \`$image\` | PASS |" >>"$REPORT"
    return 0
}

for entry in "${DISTROS[@]}"; do
    IFS='|' read -r id image <<<"$entry"
    if ! want_distro "$id" "${FILTER_ARGS[@]+"${FILTER_ARGS[@]}"}"; then
        continue
    fi
    if ! "$DOCKER" image inspect "$image" >/dev/null 2>&1; then
        printf '>> %s (%s) — pulling image...\n' "$id" "$image"
        "$DOCKER" pull --platform "$DOCKER_PLATFORM" "$image"
    fi
    run_one "$id" "$image" || true
    echo ""
done

echo "=== Summary: pass=$PASS fail=$FAIL ==="
{
    echo ""
    echo "**Summary:** pass=$PASS fail=$FAIL"
} >>"$REPORT"
echo "Report: $REPORT"
[ "$FAIL" -eq 0 ]
