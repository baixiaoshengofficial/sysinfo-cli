#!/bin/bash
# Docker CLI wrapper: use socket directly, or sudo -S (password from .docker-sudo / DOCKER_SUDO_PASSWORD).
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

read_sudo_pass() {
    if [ -n "${DOCKER_SUDO_PASSWORD:-}" ]; then
        printf '%s' "$DOCKER_SUDO_PASSWORD"
        return 0
    fi
    if [ -f "$REPO_ROOT/.docker-sudo" ]; then
        tr -d '\r\n' <"$REPO_ROOT/.docker-sudo"
        return 0
    fi
    return 1
}

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    exec docker "$@"
fi

if command -v sudo >/dev/null 2>&1 && sudo -n docker info >/dev/null 2>&1; then
    exec sudo docker "$@"
fi

pass=$(read_sudo_pass) || true
if [ -n "$pass" ]; then
    echo "$pass" | sudo -S docker "$@"
    exit $?
fi

echo "Error: cannot run docker." >&2
echo "  Fix: sudo usermod -aG docker \$USER  (re-login), or copy .docker-sudo.example -> .docker-sudo" >&2
exit 1
