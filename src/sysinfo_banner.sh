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

load_core_helpers() {
    local script_dir core
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    for core in \
        "${SYSINFO_CORE_SCRIPT:-}" \
        "$script_dir/sysinfo_core.sh" \
        "/usr/local/bin/sysinfo_core.sh" \
        "/etc/profile.d/sysinfo_core.sh"; do
        [ -n "$core" ] && [ -r "$core" ] || continue
        # Source only helper/function definitions. sysinfo_core.sh renders only
        # when executed directly, so sourcing it is safe for the login banner.
        source "$core"
        return 0
    done
    return 1
}

load_core_helpers 2>/dev/null || true

if ! declare -f display_width >/dev/null 2>&1; then
    display_width() {
        local text="$1" bytes ascii_bytes non_ascii_bytes
        bytes=$(printf '%s' "$text" | wc -c)
        ascii_bytes=$(printf '%s' "$text" | LC_ALL=C tr -cd ' -~' | wc -c)
        bytes=${bytes//[^0-9]/}; ascii_bytes=${ascii_bytes//[^0-9]/}
        [ -n "$bytes" ] || bytes=0
        [ -n "$ascii_bytes" ] || ascii_bytes=0
        non_ascii_bytes=$((bytes - ascii_bytes))
        [ "$non_ascii_bytes" -lt 0 ] && non_ascii_bytes=0
        echo $((ascii_bytes + (non_ascii_bytes / 3) * 2))
    }
fi

if ! declare -f pad_label >/dev/null 2>&1; then
    pad_label() {
        local text="$1" target=${2:-14} width spaces i
        width=$(display_width "$text")
        spaces=$((target - width))
        [ "$spaces" -lt 0 ] && spaces=0
        printf "%s" "$text"
        for ((i = 0; i < spaces; i++)); do printf ' '; done
    }
fi

if ! declare -f pad_label_right >/dev/null 2>&1; then
    pad_label_right() {
        local text="$1" target=${2:-8} width spaces i
        width=$(display_width "$text")
        spaces=$((target - width))
        [ "$spaces" -lt 0 ] && spaces=0
        for ((i = 0; i < spaces; i++)); do printf ' '; done
        printf "%s" "$text"
    }
fi

if ! declare -f calc_label_width >/dev/null 2>&1; then
    calc_label_width() {
        local max=0 w item
        for item in "$@"; do
            w=$(display_width "$item")
            [ "$w" -gt "$max" ] && max=$w
        done
        echo "$max"
    }
fi

if ! declare -f dash_kv >/dev/null 2>&1; then
    dash_kv() {
        local label=$1 value=$2 label_w=$3
        printf "  %s : %b\n" "$(pad_label "$label" "$label_w")" "$value"
    }
fi

if ! declare -f dash_kv2 >/dev/null 2>&1; then
    : "${SYSINFO_VAL_W:=32}"
    dash_kv2() {
        local l1=$1 v1=$2 l2=$3 v2=$4 label_w=$5
        local vw=${6:-$SYSINFO_VAL_W}
        printf "  %s : %-${vw}s  %s : %s\n" \
            "$(pad_label "$l1" "$label_w")" "$v1" \
            "$(pad_label "$l2" "$label_w")" "$v2"
    }
fi

if ! declare -f sysinfo_tmp_dir >/dev/null 2>&1; then
    sysinfo_tmp_dir() {
        local dir="${SYSINFO_TMP_DIR:-/var/tmp}"
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir" 2>/dev/null || dir="/tmp"
        fi
        echo "$dir"
    }
fi

run_quick() {
    if command -v timeout >/dev/null 2>&1; then
        timeout 1 "$@"
    else
        "$@"
    fi
}

# Language priority: explicit env > /etc/sysinfo-lang > system locale.
_banner_lang="${SYSINFO_LANG:-}"
if [ -f /etc/sysinfo-lang ]; then
    [ -n "$_banner_lang" ] || _banner_lang=$(tr -d ' \t\r\n' < /etc/sysinfo-lang 2>/dev/null)
fi
if [ -z "$_banner_lang" ]; then
    case "${LC_ALL:-${LANG:-}}" in
        zh*|ZH*) _banner_lang="zh" ;;
        *) _banner_lang="en" ;;
    esac
fi
case "$(printf '%s' "$_banner_lang" | tr 'A-Z' 'a-z')" in
    zh|zh-cn|cn|chinese) _banner_lang="zh" ;;
    *) _banner_lang="en" ;;
esac

if [ "$_banner_lang" = "zh" ]; then
    L_TITLE="系统实时监控"
    L_CORE="核心信息"
    L_RES="资源使用"
    L_CPU="CPU 型号"
    L_IPV4="IPv4 地址"
    L_UPTIME="运行时间"
    L_LOAD="CPU 负载"
    L_PROCS="进程数"
    L_MEM="内存使用"
    L_USERS="登录用户"
    L_SWAP="交换分区"
    L_NET="网络状态"
    L_DOWNLOAD="下载速度"
    L_UPLOAD="上传速度"
    L_DISK="磁盘状态"
    L_MNT="挂载点"
    L_SIZE="总大小"
    L_USED="已用"
    L_PERC="百分比"
    L_PROG="进度"
else
    L_TITLE="System Information Dashboard"
    L_CORE="Core Information"
    L_RES="Resource Usage"
    L_CPU="CPU Model"
    L_IPV4="IPv4 Addr"
    L_UPTIME="Uptime"
    L_LOAD="CPU Load"
    L_PROCS="Processes"
    L_MEM="Memory"
    L_USERS="Users"
    L_SWAP="Swap"
    L_NET="Network"
    L_DOWNLOAD="Download Speed"
    L_UPLOAD="Upload Speed"
    L_DISK="Disk"
    L_MNT="Mount Point"
    L_SIZE="Size"
    L_USED="Used"
    L_PERC="Percent"
    L_PROG="Progress"
fi

if ! declare -f draw_bar >/dev/null 2>&1; then
draw_bar() {
    local percent=${1:-0}
    local width=${2:-10}
    [[ "$percent" =~ ^[0-9]+$ ]] || percent=0
    [ "$percent" -gt 100 ] && percent=100
    local filled=$((percent * width / 100))
    local empty=$((width - filled))
    local i
    # Solid blocks: white (used) + gray (free).
    for ((i=0; i<filled; i++)); do printf '\033[97m█\033[0m'; done
    for ((i=0; i<empty; i++)); do printf '\033[90m█\033[0m'; done
}
fi

if ! declare -f get_cpu_core_count >/dev/null 2>&1; then
get_cpu_core_count() {
    local cores=""
    local cpuinfo_file="${SYSINFO_CPUINFO_FILE:-/proc/cpuinfo}"

    if [ -f "$cpuinfo_file" ]; then
        cores=$(awk -F: '/^[[:space:]]*processor[[:space:]]*:/{count++} END{if(count>0) print count}' "$cpuinfo_file" 2>/dev/null)
    fi

    if ! [[ "$cores" =~ ^[0-9]+$ ]] || [ "$cores" -le 0 ]; then
        cores=$(awk -F, '
            {
                for (i = 1; i <= NF; i++) {
                    split($i, r, "-")
                    if (r[1] ~ /^[0-9]+$/ && r[2] ~ /^[0-9]+$/ && r[2] >= r[1]) {
                        total += r[2] - r[1] + 1
                    } else if ($i ~ /^[0-9]+$/) {
                        total++
                    }
                }
            }
            END{if(total>0) print total}
        ' /sys/devices/system/cpu/online 2>/dev/null)
    fi

    if ! [[ "$cores" =~ ^[0-9]+$ ]] || [ "$cores" -le 0 ]; then
        cores=$(lscpu 2>/dev/null | awk -F: '/^CPU\(s\)/ && $1 !~ /NUMA/ {gsub(/[ \t]/, "", $2); print $2; exit}')
    fi

    if ! [[ "$cores" =~ ^[0-9]+$ ]] || [ "$cores" -le 0 ]; then
        cores=$(getconf _NPROCESSORS_ONLN 2>/dev/null)
    fi

    if ! [[ "$cores" =~ ^[0-9]+$ ]] || [ "$cores" -le 0 ]; then
        cores=$(nproc --all 2>/dev/null || nproc 2>/dev/null || echo "1")
    fi

    [[ "$cores" =~ ^[0-9]+$ ]] && [ "$cores" -gt 0 ] || cores="1"
    echo "$cores"
}
fi

CPU_MODEL=$(run_quick awk -F': ' '/model name/{print $2; exit}' /proc/cpuinfo 2>/dev/null)
CPU_MODEL=${CPU_MODEL:-N/A}
CPU_CORES=$(get_cpu_core_count | tr -d '\r')
if [ "$_banner_lang" = "zh" ]; then
    CPU_CORE_TEXT="${CPU_CORES} 核"
elif [ "$CPU_CORES" = "1" ]; then
    CPU_CORE_TEXT="1 core"
else
    CPU_CORE_TEXT="${CPU_CORES} cores"
fi

IP_V4=$(run_quick hostname -I 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i !~ /:/) {print $i; exit}}')
IP_V4=${IP_V4:-N/A}

UPTIME=$(run_quick uptime -p 2>/dev/null | sed 's/^up //')
UPTIME=${UPTIME:-N/A}

LOAD_AVG=$(run_quick awk '{print $1}' /proc/loadavg 2>/dev/null)
LOAD_AVG=${LOAD_AVG:-N/A}

PROCESSES=$(run_quick sh -c 'ps ax 2>/dev/null | wc -l' | tr -d ' ')
PROCESSES=${PROCESSES:-N/A}

USERS_LOGGED=$(run_quick sh -c 'who 2>/dev/null | wc -l' | tr -d ' ')
USERS_LOGGED=${USERS_LOGGED:-N/A}

MEM_USED=$(run_quick free -h 2>/dev/null | awk 'NR==2{print $3 " / " $2}')
MEM_USED=${MEM_USED:-N/A}

SWAP_USAGE=$(run_quick free -h 2>/dev/null | awk 'NR==3{if ($2 == "0B" || $2 == "0") print "None"; else print $3 " / " $2}')
SWAP_USAGE=${SWAP_USAGE:-N/A}

NET_STATS_FILE="$(sysinfo_tmp_dir)/sysinfo_banner_net_stats_${USER:-root}"
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

LBL_W=$(calc_label_width \
    "$L_CPU" "$L_IPV4" "$L_UPTIME" \
    "$L_LOAD" "$L_PROCS" "$L_MEM" "$L_USERS" "$L_SWAP" \
    "$L_DOWNLOAD" "$L_UPLOAD")

echo -e "\033[0;32m$L_CORE\033[0m"
dash_kv "$L_CPU" "$CPU_MODEL ($CPU_CORE_TEXT)" "$LBL_W"
dash_kv "$L_IPV4" "$IP_V4" "$LBL_W"
dash_kv "$L_UPTIME" "$UPTIME" "$LBL_W"

echo -e "\033[0;32m$L_RES\033[0m"
dash_kv2 "$L_LOAD" "$LOAD_AVG" "$L_PROCS" "$PROCESSES" "$LBL_W"
dash_kv2 "$L_MEM" "$MEM_USED" "$L_USERS" "$USERS_LOGGED" "$LBL_W"
dash_kv "$L_SWAP" "$SWAP_USAGE" "$LBL_W"

echo -e "\033[0;32m$L_NET\033[0m"
dash_kv2 "$L_DOWNLOAD" "$RX_SPEED_FMT" "$L_UPLOAD" "$TX_SPEED_FMT" "$LBL_W"

echo -e "\033[0;32m$L_DISK\033[0m"
DISK_MNT_W=18
DISK_NUM_W=8
printf "  %s %s %s %s  %s\n" \
    "$(pad_label "$L_MNT" "$DISK_MNT_W")" \
    "$(pad_label_right "$L_SIZE" "$DISK_NUM_W")" \
    "$(pad_label_right "$L_USED" "$DISK_NUM_W")" \
    "$(pad_label_right "$L_PERC" "$DISK_NUM_W")" \
    "$L_PROG"
echo -e "  -------------------------------------------------------------"
df -h -x tmpfs -x devtmpfs -x squashfs -x debugfs -x overlay -x efivarfs 2>/dev/null | tail -n +2 | while IFS=' ' read -r _ size used _ perc mnt _; do
    [ -n "$mnt" ] || continue
    [[ "$mnt" == /* ]] || continue
    [[ "$mnt" == /boot/efi || "$mnt" == /boot ]] && continue
    [ ${#mnt} -gt "$DISK_MNT_W" ] && mnt="${mnt:0:$((DISK_MNT_W - 3))}..."
    PERC_NUM=$(echo "$perc" | tr -d '%')
    printf "  %-${DISK_MNT_W}s %${DISK_NUM_W}s %${DISK_NUM_W}s %${DISK_NUM_W}s [" \
        "$mnt" "$size" "$used" "$perc"
    draw_bar "$PERC_NUM" 10
    printf "]\n"
done
echo -e "\033[1;36m================================================================\033[0m\n"

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit 0
fi
return 0
