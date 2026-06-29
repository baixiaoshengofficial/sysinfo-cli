#!/bin/sh
# sysinfo-cli login banner shim (POSIX — safe for bash/zsh/dash profile sourcing).
# Installed as /etc/profile.d/sysinfo-banner.sh; also sourced from /etc/zsh/zprofile.

if [ -n "${SYSINFO_BANNER_SHOWN:-}" ]; then
    return 0 2>/dev/null || exit 0
fi

# scp / sftp / `ssh host command`
if [ -n "${SSH_CONNECTION:-}${SSH_CLIENT:-}" ] && [ -z "${SSH_TTY:-}" ]; then
    return 0 2>/dev/null || exit 0
fi

_show=0
if [ -n "${SSH_TTY:-}" ]; then
    _show=1
elif [ -n "${ZSH_VERSION:-}" ]; then
    # zsh: 'l' = login shell, 'i' = interactive
    case "$-" in *l*|*i*) _show=1 ;; esac
elif [ -n "${BASH_VERSION:-}" ]; then
    # bash: login shell ($0 starts with '-' OR shopt login_shell on), or interactive
    case "$0" in -*) _show=1 ;; esac
    case "$-" in *i*) _show=1 ;; esac
    if [ "$_show" -eq 0 ] && shopt -q login_shell 2>/dev/null; then
        _show=1
    fi
else
    case "$-" in *i*) _show=1 ;; esac
fi

[ "$_show" -eq 1 ] || return 0 2>/dev/null || exit 0

SYSINFO_BANNER_SHOWN=1
export SYSINFO_BANNER_SHOWN

_banner=""
if [ -n "${SYSINFO_BANNER_SCRIPT:-}" ] && [ -r "${SYSINFO_BANNER_SCRIPT}" ]; then
    _banner="${SYSINFO_BANNER_SCRIPT}"
else
    for _candidate in \
        /usr/local/lib/sysinfo/sysinfo_banner.sh \
        /etc/profile.d/sysinfo-banner-bash.sh; do
        if [ -r "$_candidate" ]; then
            _banner="$_candidate"
            break
        fi
    done
fi

if [ -n "$_banner" ]; then
    /bin/bash "$_banner"
fi

return 0 2>/dev/null || exit 0
