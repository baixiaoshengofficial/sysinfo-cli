#!/bin/bash

# sysinfo-cli Banner Script for SSH Login
# Displays a lightweight one-shot dashboard when a user logs in.
#
# This file is installed to /etc/profile.d/ and sourced by /etc/profile on
# login. Guards keep it safe:
#   1. Only render for real login/terminal sessions (skip scp/rsync/ssh cmd).
#   2. Only render under bash (the script uses bashisms); when sourced by a
#      non-bash login shell (e.g. dash), bail out cleanly instead of emitting
#      syntax errors that would abort the rest of /etc/profile.d.
#
# Note: during /etc/profile.d sourcing, login shells often lack 'i' in $- yet.
# Use shopt login_shell / SSH_TTY instead of $- alone.

# When executed directly (e.g. `./sysinfo_banner.sh` or `sysinfo-banner`),
# always render — no guards. The guards below only apply when this file is
# sourced by /etc/profile on login, where we must avoid breaking non-bash or
# non-interactive login shells (scp/rsync/dash).
#
# Detect "sourced" portably: under bash, BASH_SOURCE differs from $0; under
# a non-bash shell (dash) we cannot use [[ or array subscripts, so bail out
# first with POSIX-only syntax.
if [ -z "${BASH_VERSION:-}" ]; then
    # Non-bash login shell (e.g. dash) sourcing this file: skip cleanly.
    return 0 2>/dev/null || exit 0
fi

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Once per session (profile may source us before .bashrc runs).
    if [ -n "${SYSINFO_BANNER_SHOWN:-}" ]; then
        return 0 2>/dev/null || exit 0
    fi

    # scp / sftp / `ssh host command` — SSH session without an allocated tty.
    if [[ -n "${SSH_CONNECTION:-}${SSH_CLIENT:-}" ]] && [[ -z "${SSH_TTY:-}" ]]; then
        return 0 2>/dev/null || exit 0
    fi

    # SSH/login shells are not interactive yet when /etc/profile.d runs ($- lacks i).
    if shopt -q login_shell 2>/dev/null || [[ -n "${SSH_TTY:-}" ]]; then
        :
    elif case "$-" in *i*) true ;; *) false ;; esac; then
        :
    else
        return 0 2>/dev/null || exit 0
    fi

    export SYSINFO_BANNER_SHOWN=1
fi

# Language priority: /etc/sysinfo-lang (set via display.language) > system locale.
_banner_lang=""
if [ -f /etc/sysinfo-lang ]; then
    _banner_lang=$(tr -d ' \t\r\n' < /etc/sysinfo-lang 2>/dev/null)
fi
if [ -z "$_banner_lang" ]; then
    case "${LC_ALL:-${LANG:-}}" in
        zh*|ZH*) _banner_lang="zh" ;;
        *) _banner_lang="en" ;;
    esac
fi

if [ "$_banner_lang" = "zh" ]; then
    L_TITLE="系统实时监控"
    L_CORE="[核心信息]"
    L_RES="[资源使用]"
    L_CPU="CPU 型号"
    L_IPV4="IPv4 地址"
    L_UPTIME="运行时间"
    L_LOAD="CPU 负载"
    L_PROCS="进程数"
    L_MEM="内存使用"
    L_USERS="登录用户"
    L_SWAP="交换分区"
    L_NET="[网络状态]"
    L_DOWNLOAD="下载速度"
    L_UPLOAD="上传速度"
    L_DISK="[磁盘状态]"
    L_MNT="挂载点"
    L_SIZE="总大小"
    L_USED="已用"
    L_PERC="百分比"
    L_PROG="进度"
else
    L_TITLE="System Information Dashboard"
    L_CORE="[Core Info]"
    L_RES="[Resource Usage]"
    L_CPU="CPU Model"
    L_IPV4="IPv4 Addr"
    L_UPTIME="Uptime"
    L_LOAD="CPU Load"
    L_PROCS="Processes"
    L_MEM="Memory"
    L_USERS="Users"
    L_SWAP="Swap"
    L_NET="[Network]"
    L_DOWNLOAD="Download Speed"
    L_UPLOAD="Upload Speed"
    L_DISK="[Disk Status]"
    L_MNT="Mount Point"
    L_SIZE="Size"
    L_USED="Used"
    L_PERC="Percent"
    L_PROG="Progress"
fi

draw_bar() {
    local percent=${1:-0}
    [[ "$percent" =~ ^[0-9]+$ ]] || percent=0
    [ "$percent" -gt 100 ] && percent=100
    local filled=$((percent / 10))
    local empty=$((10 - filled))
    local i
    # Solid blocks: white (used) + black (free).
    for ((i=0; i<filled; i++)); do printf '\033[97m█\033[0m'; done
    for ((i=0; i<empty; i++)); do printf '\033[30m█\033[0m'; done
}

CPU_MODEL=$(timeout 1 awk -F': ' '/model name/{print $2; exit}' /proc/cpuinfo 2>/dev/null)
CPU_MODEL=${CPU_MODEL:-N/A}

IP_V4=$(timeout 1 hostname -I 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i !~ /:/) {print $i; exit}}')
IP_V4=${IP_V4:-N/A}

UPTIME=$(timeout 1 uptime -p 2>/dev/null | sed 's/^up //')
UPTIME=${UPTIME:-N/A}

LOAD_AVG=$(timeout 1 awk '{print $1}' /proc/loadavg 2>/dev/null)
LOAD_AVG=${LOAD_AVG:-N/A}

PROCESSES=$(timeout 1 sh -c 'ps ax 2>/dev/null | wc -l' | tr -d ' ')
PROCESSES=${PROCESSES:-N/A}

USERS_LOGGED=$(timeout 1 sh -c 'who 2>/dev/null | wc -l' | tr -d ' ')
USERS_LOGGED=${USERS_LOGGED:-N/A}

MEM_USED=$(timeout 1 free -h 2>/dev/null | awk 'NR==2{print $3 " / " $2}')
MEM_USED=${MEM_USED:-N/A}

SWAP_USAGE=$(timeout 1 free -h 2>/dev/null | awk 'NR==3{if ($2 == "0B" || $2 == "0") print "None"; else print $3 " / " $2}')
SWAP_USAGE=${SWAP_USAGE:-N/A}

NET_STATS_FILE="/var/tmp/sysinfo_banner_net_stats_${USER:-root}"
RX_BYTES=0
TX_BYTES=0
while read -r _ rx tx; do
    [[ "$rx" =~ ^[0-9]+$ ]] || rx=0
    [[ "$tx" =~ ^[0-9]+$ ]] || tx=0
    RX_BYTES=$((RX_BYTES + rx))
    TX_BYTES=$((TX_BYTES + tx))
done < <(awk -F'[: ]+' 'NR>2 && $2 != "lo" {print $2, $3, $11}' /proc/net/dev 2>/dev/null)

CURRENT_TIME=$(date +%s)
if [ -f "$NET_STATS_FILE" ]; then
    read -r PREV_RX PREV_TX PREV_TIME < "$NET_STATS_FILE" 2>/dev/null || true
fi
printf '%s %s %s\n' "$RX_BYTES" "$TX_BYTES" "$CURRENT_TIME" > "$NET_STATS_FILE" 2>/dev/null || true

PREV_RX=${PREV_RX:-0}
PREV_TX=${PREV_TX:-0}
PREV_TIME=${PREV_TIME:-0}
if [[ "$PREV_TIME" =~ ^[0-9]+$ ]] && [ "$PREV_TIME" -gt 0 ] && [ $((CURRENT_TIME - PREV_TIME)) -ge 1 ]; then
    TIME_DIFF=$((CURRENT_TIME - PREV_TIME))
    RX_DIFF=$((RX_BYTES - PREV_RX))
    TX_DIFF=$((TX_BYTES - PREV_TX))
    [ "$RX_DIFF" -lt 0 ] && RX_DIFF=0
    [ "$TX_DIFF" -lt 0 ] && TX_DIFF=0
    RX_SPEED_FMT=$(awk "BEGIN {v=$RX_DIFF/1024/$TIME_DIFF; if (v>1024) printf \"%.1f MB/s\", v/1024; else printf \"%.1f KB/s\", v}")
    TX_SPEED_FMT=$(awk "BEGIN {v=$TX_DIFF/1024/$TIME_DIFF; if (v>1024) printf \"%.1f MB/s\", v/1024; else printf \"%.1f KB/s\", v}")
else
    RX_SPEED_FMT="0 KB/s"
    TX_SPEED_FMT="0 KB/s"
fi

echo -e "\033[1;36m================================================================\033[0m"
echo -e "  \033[1m$L_TITLE\033[0m - $(date +'%Y-%m-%d %H:%M:%S')"
echo -e "\033[1;36m================================================================\033[0m"

echo -e "\033[0;32m$L_CORE\033[0m"
printf "  %-14s : %s\n" "$L_CPU" "$CPU_MODEL"
printf "  %-14s : %s\n" "$L_IPV4" "$IP_V4"
printf "  %-14s : %s\n" "$L_UPTIME" "$UPTIME"

echo -e "\033[0;32m$L_RES\033[0m"
printf "  %-14s : %-18s %-12s : %s\n" "$L_LOAD" "$LOAD_AVG" "$L_PROCS" "$PROCESSES"
printf "  %-14s : %-18s %-12s : %s\n" "$L_MEM" "$MEM_USED" "$L_USERS" "$USERS_LOGGED"
printf "  %-14s : %s\n" "$L_SWAP" "$SWAP_USAGE"

echo -e "\033[0;32m$L_NET\033[0m"
printf "  %-14s : %-18s %-12s : %s\n" "$L_DOWNLOAD" "$RX_SPEED_FMT" "$L_UPLOAD" "$TX_SPEED_FMT"

echo -e "\033[0;32m$L_DISK\033[0m"
printf "  %-18s %-8s %-8s %-8s %-15s\n" "$L_MNT" "$L_SIZE" "$L_USED" "$L_PERC" "$L_PROG"
echo -e "  -------------------------------------------------------------"
df -h -x tmpfs -x devtmpfs -x squashfs -x debugfs -x overlay -x efivarfs 2>/dev/null | tail -n +2 | while IFS=' ' read -r _ size used _ perc mnt _; do
    [ -n "$mnt" ] || continue
    [[ "$mnt" == /* ]] || continue
    [[ "$mnt" == /boot/efi || "$mnt" == /boot ]] && continue
    [ ${#mnt} -gt 18 ] && mnt="${mnt:0:15}..."
    PERC_NUM=$(echo "$perc" | tr -d '%')
    printf "  %-18s %-8s %-8s %-8s [" "$mnt" "$size" "$used" "$perc"
    draw_bar "$PERC_NUM"
    printf "]\n"
done
echo -e "\033[1;36m================================================================\033[0m\n"

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit 0
fi
return 0
