#!/bin/bash
# Smoke-test install.sh on multiple Linux distros via Docker.
# Usage: bash tests/docker_distros.sh [distro_id ...]
#   distro_id: debian ubuntu fedora rocky alpine arch opensuse
# Requires: docker (user in 'docker' group, or DOCKER="sudo docker")
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKER="${DOCKER:-docker}"
FAIL=0
PASS=0
RUN_TIMEOUT="${RUN_TIMEOUT:-360}"
REPORT="${REPO_ROOT}/tests/docker_distros_report.md"

pick_docker() {
    if $DOCKER info >/dev/null 2>&1; then
        return 0
    fi
    if command -v pkexec >/dev/null 2>&1 && pkexec docker info >/dev/null 2>&1; then
        DOCKER="pkexec docker"
        return 0
    fi
    if sudo -n docker info >/dev/null 2>&1; then
        DOCKER="sudo docker"
        return 0
    fi
    return 1
}

# id|image|setup_commands (run as root before install.sh)
DISTROS=(
  'debian|debian:bookworm-slim|apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq bash sudo curl ca-certificates procps'
  'ubuntu|ubuntu:24.04|apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq bash sudo curl ca-certificates procps'
  'fedora|fedora:40|dnf install -y -q bash sudo curl ca-certificates procps-ng'
  'rocky|rockylinux:9|dnf install -y -q bash sudo procps-ng ca-certificates'
  'alpine|alpine:3.20|apk add --no-cache bash sudo curl ca-certificates procps'
  'arch|archlinux:latest|pacman -Sy --noconfirm --needed bash sudo curl ca-certificates procps-ng'
  'opensuse|opensuse/leap:15.6|zypper -n ref && zypper -n in -y bash sudo curl ca-certificates procps'
)

log_pass() { printf '  \033[32m[PASS]\033[0m %s\n' "$1"; PASS=$((PASS + 1)); }
log_fail() { printf '  \033[31m[FAIL]\033[0m %s\n' "$1"; FAIL=$((FAIL + 1)); }

FILTER_ARGS=("$@")

if ! command -v "${DOCKER%% *}" >/dev/null 2>&1 && [ "$DOCKER" = "docker" ]; then
    echo "Error: docker not found (set DOCKER=... if using podman or sudo docker)"
    exit 1
fi
if ! pick_docker; then
    echo "Error: cannot talk to Docker daemon."
    echo "  Hint: add user to group 'docker', or run: DOCKER='sudo docker' make docker-test-distros"
    exit 1
fi

echo "=== sysinfo-cli multi-distro Docker install test ==="
echo "Repo: $REPO_ROOT"
echo "Docker: $DOCKER"
echo "Timeout per distro: ${RUN_TIMEOUT}s"
echo ""

{
    echo "# Docker multi-distro install report"
    echo ""
    echo "- Time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "- Repo: \`$REPO_ROOT\`"
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
    local id="$1" image="$2" setup="$3"
    local logfile shell="bash"
    [ "$id" = "alpine" ] && shell="sh"
    logfile="$(mktemp "/tmp/sysinfo-docker-${id}.XXXX.log")"

    printf '>> %s (%s)\n' "$id" "$image"

    if ! timeout "$RUN_TIMEOUT" $DOCKER run --rm \
        -v "$REPO_ROOT:/opt/sysinfo-cli" \
        -w /opt/sysinfo-cli \
        "$image" "$shell" -lc "
            set -e
            $setup
            rm -f /usr/local/bin/yq
            bash install.sh --lang en
            /usr/local/bin/yq --version | grep -qi mikefarah
            command -v tc >/dev/null || [ -x /usr/sbin/tc ]
            command -v ip >/dev/null || [ -x /usr/sbin/ip ]
            sysinfo -h 2>&1 | grep -qi sysinfo
            timeout 8 sysinfo 2>&1 | grep -qiE 'CPU|System Information|系统信息'
            /usr/local/bin/yq eval '.display.language' /etc/sysinfo/config.yaml | grep -qE 'en|zh|auto'
        " >"$logfile" 2>&1; then
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
    IFS='|' read -r id image setup <<<"$entry"
    if ! want_distro "$id" "${FILTER_ARGS[@]}"; then
        continue
    fi
    if ! $DOCKER image inspect "$image" >/dev/null 2>&1; then
        printf '>> %s (%s) — pulling image...\n' "$id" "$image"
        $DOCKER pull "$image"
    fi
    run_one "$id" "$image" "$setup" || true
    echo ""
done

echo "=== Summary: pass=$PASS fail=$FAIL ==="
{
    echo ""
    echo "**Summary:** pass=$PASS fail=$FAIL"
} >>"$REPORT"
echo "Report: $REPORT"
[ "$FAIL" -eq 0 ]
