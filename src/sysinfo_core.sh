#!/bin/bash

# This file is a bash function library + renderer, sourced by sysinfo.sh and
# directly executable. It is also (for historical install compatibility) placed
# in /etc/profile.d/, where /etc/profile may source it under a non-bash login
# shell (e.g. dash). Bail out cleanly in that case — the bashisms below would
# otherwise emit syntax errors and abort the rest of /etc/profile.d.
if [ -z "${BASH_VERSION:-}" ]; then
    return 0 2>/dev/null || exit 0
fi

# Run command as root (directly if already root, otherwise with non-interactive sudo)
run_privileged() {
    if [ "$EUID" -eq 0 ]; then
        "$@"
    else
        if sudo -n true >/dev/null 2>&1; then
            sudo -n "$@"
        else
            sudo "$@"
        fi
    fi
}

# Case conversion helper (compatible with both bash and zsh)
tolower() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}
toupper() {
    echo "$1" | tr '[:lower:]' '[:upper:]'
}

# Sum RX/TX byte counters across all non-loopback interfaces from /proc/net/dev.
# Sets the caller-visible RX_TOTAL / TX_TOTAL variables (used by traffic stats).
read_net_counters() {
    RX_TOTAL=0
    TX_TOTAL=0
    local iface rx tx
    while read -r iface rx _ _ _ _ _ _ _ tx _; do
        [ -n "$iface" ] || continue
        [[ "$rx" =~ ^[0-9]+$ ]] || rx=0
        [[ "$tx" =~ ^[0-9]+$ ]] || tx=0
        RX_TOTAL=$((RX_TOTAL + rx))
        TX_TOTAL=$((TX_TOTAL + tx))
    done < <(awk 'NR>2 && $1 != "lo:" {print $1, $2, $10}' /proc/net/dev 2>/dev/null)
}

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

# Flat state file (/etc/sysinfo-traffic) is a single-line JSON-ish string parsed
# via grep field extraction. cfg_get <key> echoes the raw value (unquoted) or
# empty. cfg_get_num <key> echoes only the numeric portion.
SYSINFO_CFG_FILE="/etc/sysinfo-traffic"
cfg_get() {
    local key="$1"
    grep -o "\"$key\":\"[^\"]*\"" "$SYSINFO_CFG_FILE" 2>/dev/null | cut -d'"' -f4
}
cfg_get_raw() {
    local key="$1"
    grep -o "\"$key\":[^,}]*" "$SYSINFO_CFG_FILE" 2>/dev/null | cut -d: -f2 | tr -d ' "'
}
cfg_get_num() {
    local key="$1"
    grep -o "\"$key\":[0-9]*" "$SYSINFO_CFG_FILE" 2>/dev/null | grep -o '[0-9]*'
}

# Stats file (/etc/sysinfo-traffic.json) is also grep-parsed. stats_get_num
# extracts a numeric field, stats_get_str a quoted string field.
SYSINFO_STATS_FILE="/etc/sysinfo-traffic.json"
stats_get_num() {
    local key="$1"
    grep -o "\"$key\":[0-9]*" "$SYSINFO_STATS_FILE" 2>/dev/null | cut -d: -f2
}
stats_get_str() {
    local key="$1"
    grep -o "\"$key\":\"[^\"]*\"" "$SYSINFO_STATS_FILE" 2>/dev/null | cut -d'"' -f4
}

# Terminal display width for UTF-8 labels.
# ASCII/narrow = 1 column, CJK (3-byte) = 2 columns. Derived from the byte
# vs. character count so it is locale-independent (awk length() counts bytes
# on mawk and would mis-size CJK labels, breaking colon alignment).
display_width() {
    local text="$1"
    local bytes chars
    bytes=$(printf '%s' "$text" | wc -c)
    chars=$(printf '%s' "$text" | LC_ALL=C.UTF-8 wc -m)
    bytes=${bytes//[^0-9]/}
    chars=${chars//[^0-9]/}
    [ -n "$bytes" ] || bytes=0
    [ -n "$chars" ] || chars=0
    # Wide chars (3+ extra bytes over 1) add one extra column each.
    echo $(( chars + (bytes - chars) / 2 ))
}

# Pad a label to a target display width (accounting for double-width CJK).
pad_label() {
    local text="$1"
    local target=${2:-14}
    local width spaces i

    width=$(display_width "$text")
    spaces=$((target - width))
    [ "$spaces" -lt 0 ] && spaces=0

    printf "%s" "$text"
    for ((i = 0; i < spaces; i++)); do
        printf ' '
    done
}

# Right-justify a label to a target display width (CJK-aware).
pad_label_right() {
    local text="$1"
    local target=${2:-8}
    local width spaces i

    width=$(display_width "$text")
    spaces=$((target - width))
    [ "$spaces" -lt 0 ] && spaces=0

    for ((i = 0; i < spaces; i++)); do
        printf ' '
    done
    printf "%s" "$text"
}

calc_label_width() {
    local max=0
    local w=0
    local item
    for item in "$@"; do
        w=$(display_width "$item")
        [ "$w" -gt "$max" ] && max=$w
    done
    echo "$max"
}

# Dashboard layout: fixed label + value columns for aligned colons.
# VAL_W = width of the primary value column in two-column rows.
: "${SYSINFO_VAL_W:=32}"

dash_kv() {
    local label=$1 value=$2 label_w=$3
    printf "  %s : %b\n" "$(pad_label "$label" "$label_w")" "$value"
}

dash_kv2() {
    local l1=$1 v1=$2 l2=$3 v2=$4 label_w=$5
    local vw=${6:-$SYSINFO_VAL_W}
    printf "  %s : %-${vw}s  %s : %s\n" \
        "$(pad_label "$l1" "$label_w")" "$v1" \
        "$(pad_label "$l2" "$label_w")" "$v2"
}

detect_lang() {
    local cfg_lang=""
    if [ -f /etc/sysinfo-lang ]; then
        cfg_lang=$(cat /etc/sysinfo-lang 2>/dev/null | tr -d ' \t\r\n')
    fi

    if [ -z "$cfg_lang" ]; then
        local env_lang="${LC_ALL:-${LANG:-}}"
        case "$env_lang" in
            zh*|ZH*) cfg_lang="zh" ;;
            *) cfg_lang="en" ;;
        esac
    fi

    case "$(tolower "$cfg_lang")" in
        zh|zh-cn|cn|chinese) echo "zh" ;;
        *) echo "en" ;;
    esac
}

# Fallback colors (keep empty when terminal doesn't support color)
: "${NONE:=\033[0m}"
: "${BOLD:=\033[1m}"
: "${RED:=\033[31m}"
: "${GREEN:=\033[32m}"
: "${YELLOW:=\033[33m}"
: "${CYAN:=\033[36m}"
: "${SYSINFO_SHOW_TRAFFIC:=true}"
: "${SYSINFO_SHOW_NAT:=true}"
: "${SYSINFO_SHOW_THROTTLE:=true}"

# i18n labels. Priority: explicit SYSINFO_LANG env (set from display.language
# by the CLI) > /etc/sysinfo-lang > system locale.
case "$(tolower "${SYSINFO_LANG:-}")" in
    zh|zh-cn|cn|chinese) SYSINFO_LANG="zh" ;;
    en|en-us|english) SYSINFO_LANG="en" ;;
    *) SYSINFO_LANG="$(detect_lang)" ;;
esac
if [ "$SYSINFO_LANG" = "zh" ]; then
    : "${L_TITLE:=系统信息面板}"
    : "${L_CORE:=核心信息}"
    : "${L_CPU:=CPU}"
    : "${L_IPV4:=IPv4}"
    : "${L_IPV6:=IPv6}"
    : "${L_NAT:=NAT}"
    : "${L_UPTIME:=运行时间}"
    : "${L_RES:=资源使用}"
    : "${L_LOAD:=负载}"
    : "${L_PROCS:=进程数}"
    : "${L_MEM:=内存}"
    : "${L_USERS:=在线用户}"
    : "${L_SWAP:=交换分区}"
    : "${L_NET:=网络}"
    : "${L_DOWNLOAD:=下载}"
    : "${L_UPLOAD:=上传}"
    : "${L_TOTAL:=总流量}"
    : "${L_LIMIT:=配额}"
    : "${L_TRAFFIC_MODE:=流量模式}"
    : "${L_TRAFFIC_PERC:=使用率}"
    : "${L_THROTTLE_ENABLE:=限速开关}"
    : "${L_THROTTLE_STATUS:=限速状态}"
    : "${L_THROTTLE_RULE:=限速规则}"
    : "${L_DISK:=磁盘}"
    : "${L_MNT:=挂载点}"
    : "${L_SIZE:=总量}"
    : "${L_USED:=已用}"
    : "${L_PERC:=占比}"
    : "${L_PROG:=进度}"
else
    : "${L_TITLE:=System Information Dashboard}"
    : "${L_CORE:=Core Information}"
    : "${L_CPU:=CPU}"
    : "${L_IPV4:=IPv4}"
    : "${L_IPV6:=IPv6}"
    : "${L_NAT:=NAT}"
    : "${L_UPTIME:=Uptime}"
    : "${L_RES:=Resource Usage}"
    : "${L_LOAD:=Load}"
    : "${L_PROCS:=Processes}"
    : "${L_MEM:=Memory}"
    : "${L_USERS:=Users}"
    : "${L_SWAP:=Swap}"
    : "${L_NET:=Network}"
    : "${L_DOWNLOAD:=Download}"
    : "${L_UPLOAD:=Upload}"
    : "${L_TOTAL:=Total Traffic}"
    : "${L_LIMIT:=Quota}"
    : "${L_TRAFFIC_MODE:=Traffic Mode}"
    : "${L_TRAFFIC_PERC:=Usage}"
    : "${L_THROTTLE_ENABLE:=Throttle}"
    : "${L_THROTTLE_STATUS:=Throttle Status}"
    : "${L_THROTTLE_RULE:=Throttle Rule}"
    : "${L_DISK:=Disk}"
    : "${L_MNT:=Mount}"
    : "${L_SIZE:=Size}"
    : "${L_USED:=Used}"
    : "${L_PERC:=Percent}"
    : "${L_PROG:=Progress}"
fi

# Convert bytes to a human-readable value (B/KB/MB/GB/TB)
bytes_to_human() {
    local bytes=${1:-0}

    # Ensure numeric input
    if ! [[ "$bytes" =~ ^[0-9]+$ ]]; then
        bytes=0
    fi

    if [ "$bytes" -ge 1099511627776 ] 2>/dev/null; then
        awk "BEGIN {printf \"%.2f TB\", $bytes/1099511627776}"
    elif [ "$bytes" -ge 1073741824 ] 2>/dev/null; then
        awk "BEGIN {printf \"%.2f GB\", $bytes/1073741824}"
    elif [ "$bytes" -ge 1048576 ] 2>/dev/null; then
        awk "BEGIN {printf \"%.2f MB\", $bytes/1048576}"
    elif [ "$bytes" -ge 1024 ] 2>/dev/null; then
        awk "BEGIN {printf \"%.2f KB\", $bytes/1024}"
    else
        echo "${bytes} B"
    fi
}

# Draw a fixed-width progress bar.
# Usage: draw_bar <percent> <width>
draw_bar() {
    local percent=${1:-0}
    local width=${2:-10}

    [[ "$percent" =~ ^[0-9]+$ ]] || percent=0
    [[ "$width" =~ ^[0-9]+$ ]] || width=10

    if [ "$percent" -lt 0 ]; then
        percent=0
    elif [ "$percent" -gt 100 ]; then
        percent=100
    fi

    local filled=$((percent * width / 100))
    local empty=$((width - filled))
    local i

    # Solid blocks: white (used) + gray (free).
    for ((i=0; i<filled; i++)); do
        printf '\033[97m█\033[0m'
    done
    for ((i=0; i<empty; i++)); do
        printf '\033[90m█\033[0m'
    done
}

# Dedicated IFB device for download shaping (ingress redirect)
SYSINFO_IFB_DEV="ifb_sysinfo0"

normalize_traffic_limit() {
    local raw="$(toupper "$1")"
    raw="${raw// /}"

    # Use case for better compatibility
    case "$raw" in
        UNLIMIT|-1)
            echo "UNLIMITED"
            return 0
            ;;
    esac

    if [[ "$raw" =~ ^([0-9]+\.?[0-9]*)([TGM])B?$ ]]; then
        echo "${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
        return 0
    fi

    return 1
}

remove_active_tc_limit() {
    command -v tc >/dev/null 2>&1 || return 0

    local interfaces
    interfaces=$(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | cut -d@ -f1)
    [ -n "$interfaces" ] || return 0

    while read -r interface; do
        [ -n "$interface" ] || continue
        [ "$interface" = "lo" ] && continue

        # Check if HTB exists with our handle (1:)
        local root_qdisc
        root_qdisc=$(tc qdisc show dev "$interface" 2>/dev/null | awk '/qdisc htb/ {for(i=1;i<=NF;i++) if($i ~ /^1:$/) print $i}' | tr -d ':')
        if [ -n "$root_qdisc" ] && [ "$root_qdisc" = "1" ]; then
            run_privileged tc qdisc del dev "$interface" root >/dev/null 2>&1
        fi

        if tc qdisc show dev "$interface" 2>/dev/null | grep -q " ingress "; then
            run_privileged tc qdisc del dev "$interface" ingress >/dev/null 2>&1
        fi
    done <<< "$interfaces"
    if ip link show dev "$SYSINFO_IFB_DEV" >/dev/null 2>&1; then
        run_privileged tc qdisc del dev "$SYSINFO_IFB_DEV" root >/dev/null 2>&1 || true
        run_privileged ip link set dev "$SYSINFO_IFB_DEV" down >/dev/null 2>&1 || true
        run_privileged ip link del "$SYSINFO_IFB_DEV" >/dev/null 2>&1 || true
    fi
}

reset_traffic() {
    local stats_file="/etc/sysinfo-traffic.json"

    # Read traffic mode from config
    local traffic_mode
    traffic_mode=$(cfg_get "traffic_mode")
    traffic_mode=${traffic_mode:-both}

    # Get current network values as the new baseline
    read_net_counters

    # Reset stats
    printf '%s\n' "{\"start_time\":$(date +%s),\"rx_bytes\":0,\"tx_bytes\":0,\"last_rx\":$RX_TOTAL,\"last_tx\":$TX_TOTAL,\"traffic_mode\":\"$traffic_mode\",\"last_update\":$(date +%s)}" | run_privileged tee "$stats_file" >/dev/null 2>&1
    remove_active_tc_limit
    echo "Monthly traffic statistics reset"
}
init_traffic_stats() {
    local current_rx=$1
    local current_tx=$2
    local traffic_mode=${3:-both}
    local current_time=$(date +%s)
    # Save current network values as baseline for next update
    echo "{\"start_time\":$current_time,\"rx_bytes\":0,\"tx_bytes\":0,\"last_rx\":$current_rx,\"last_tx\":$current_tx,\"traffic_mode\":\"$traffic_mode\",\"last_update\":$current_time}"
}

# Perform monthly traffic reset
perform_reset() {
    local stats_file="/etc/sysinfo-traffic.json"
    local traffic_mode
    traffic_mode=$(cfg_get "traffic_mode")
    traffic_mode=${traffic_mode:-both}
    # Get current network values for baseline
    read_net_counters
    # Reset stats to zero with current network as baseline
    init_traffic_stats "$RX_TOTAL" "$TX_TOTAL" "$traffic_mode" | run_privileged tee "$stats_file" >/dev/null 2>&1
    remove_active_tc_limit
}

# Update traffic statistics
update_traffic_stats() {
    local current_rx=$1
    local current_tx=$2

    # No config -> nothing to account against.
    [ -f "$SYSINFO_CFG_FILE" ] || return 0

    local reset_day
    reset_day=$(cfg_get_num "reset_day")
    reset_day=${reset_day:-1}

    # Initialize stats file on first run with current counters as baseline.
    if [ ! -f "$SYSINFO_STATS_FILE" ]; then
        read_net_counters
        init_traffic_stats "$RX_TOTAL" "$TX_TOTAL" | run_privileged tee "$SYSINFO_STATS_FILE" >/dev/null 2>&1
    fi

    # Read current stats
    local start_time rx_bytes tx_bytes last_update
    start_time=$(stats_get_num "start_time"); start_time=${start_time:-$(date +%s)}
    rx_bytes=$(stats_get_num "rx_bytes"); rx_bytes=${rx_bytes:-0}
    tx_bytes=$(stats_get_num "tx_bytes"); tx_bytes=${tx_bytes:-0}
    last_update=$(stats_get_num "last_update"); last_update=${last_update:-$start_time}

    # Determine the most recent cycle-reset boundary at/preceding now.
    # Reset when the last update happened before that boundary.
    local now_ts=$(date +%s)
    local current_year_month=$(date +%Y-%m)
    local cycle_reset_ts
    cycle_reset_ts=$(_cycle_reset_ts "$reset_day" "$current_year_month" "$now_ts")

    if [ "$last_update" -lt "$cycle_reset_ts" ]; then
        perform_reset
        return 0
    fi

    # Normal update flow: use passed counters, or read fresh ones if absent.
    if [ -z "$current_rx" ] || [ -z "$current_tx" ]; then
        read_net_counters
        current_rx=$RX_TOTAL
        current_tx=$TX_TOTAL
    fi

    # Read last-update baseline and compute delta (guard against counter wrap).
    local last_rx_bytes last_tx_bytes rx_delta tx_delta
    last_rx_bytes=$(stats_get_num "last_rx"); last_rx_bytes=${last_rx_bytes:-0}
    last_tx_bytes=$(stats_get_num "last_tx"); last_tx_bytes=${last_tx_bytes:-0}
    rx_delta=$((current_rx - last_rx_bytes))
    tx_delta=$((current_tx - last_tx_bytes))
    # Counter wrapped or interface reset: ignore this delta, re-baseline.
    [ "$rx_delta" -lt 0 ] || [ "$rx_delta" -gt 1073741824 ] && rx_delta=0
    [ "$tx_delta" -lt 0 ] || [ "$tx_delta" -gt 1073741824 ] && tx_delta=0

    rx_bytes=$((rx_bytes + rx_delta))
    tx_bytes=$((tx_bytes + tx_delta))

    # Preserve traffic_mode across updates.
    local traffic_mode
    traffic_mode=$(stats_get_str "traffic_mode"); traffic_mode=${traffic_mode:-both}

    local current_time=$(date +%s)
    _SYSINFO_RUNTIME_RX=$rx_bytes
    _SYSINFO_RUNTIME_TX=$tx_bytes

    local persist_ts_file="/var/tmp/sysinfo_traffic_persist_ts_${USER:-root}"
    local last_persist=0
    [ -f "$persist_ts_file" ] && last_persist=$(cat "$persist_ts_file" 2>/dev/null)
    [[ "$last_persist" =~ ^[0-9]+$ ]] || last_persist=0
    if [ $((current_time - last_persist)) -lt 5 ]; then
        return 0
    fi

    printf '%s\n' "{\"start_time\":$start_time,\"rx_bytes\":$rx_bytes,\"tx_bytes\":$tx_bytes,\"last_rx\":$current_rx,\"last_tx\":$current_tx,\"traffic_mode\":\"$traffic_mode\",\"last_update\":$current_time}" | run_privileged tee "$SYSINFO_STATS_FILE" >/dev/null 2>&1
    echo "$current_time" > "$persist_ts_file" 2>/dev/null
}

# Compute the cycle reset timestamp (reset_day 00:00) for the billing cycle
# that contains "now". If now is before this month's reset, use last month's.
_cycle_reset_ts() {
    local reset_day=$1
    local current_year_month=$2
    local now_ts=$3

    local month_days effective_day this_cycle_reset_ts
    month_days=$(date -d "$current_year_month-01 +1 month -1 day" +%d)
    effective_day=$reset_day
    [ "$effective_day" -gt "$month_days" ] && effective_day=$month_days
    this_cycle_reset_ts=$(date -d "$current_year_month-$effective_day 00:00:00" +%s)

    if [ "$now_ts" -ge "$this_cycle_reset_ts" ]; then
        echo "$this_cycle_reset_ts"
        return 0
    fi

    local prev_year_month prev_month_days prev_effective_day
    prev_year_month=$(date -d "$current_year_month-01 -1 month" +%Y-%m)
    prev_month_days=$(date -d "$prev_year_month-01 +1 month -1 day" +%d)
    prev_effective_day=$reset_day
    [ "$prev_effective_day" -gt "$prev_month_days" ] && prev_effective_day=$prev_month_days
    date -d "$prev_year_month-$prev_effective_day 00:00:00" +%s
}

# Get traffic statistics for display
get_traffic_stats() {
    # No config -> no traffic accounting to show.
    [ -f "$SYSINFO_CFG_FILE" ] || return 1

    # Initialize stats file on first run.
    if [ ! -f "$SYSINFO_STATS_FILE" ]; then
        read_net_counters
        init_traffic_stats "$RX_TOTAL" "$TX_TOTAL" | run_privileged tee "$SYSINFO_STATS_FILE" >/dev/null 2>&1
    fi

    # Resolve the monthly limit (in bytes) and display label.
    local limit has_limit="false" limit_bytes=0
    limit=$(cfg_get "limit")
    if [ -n "$limit" ] && limit_bytes=$(_limit_to_bytes "$limit"); then
        has_limit="true"
    else
        limit="Unlimit"
        limit_bytes=0
    fi

    # Read accumulated counters (prefer in-memory values from recent updates).
    local rx_bytes tx_bytes
    if [[ "${_SYSINFO_RUNTIME_RX:-}" =~ ^[0-9]+$ ]] && [[ "${_SYSINFO_RUNTIME_TX:-}" =~ ^[0-9]+$ ]]; then
        rx_bytes=$_SYSINFO_RUNTIME_RX
        tx_bytes=$_SYSINFO_RUNTIME_TX
    else
        rx_bytes=$(stats_get_num "rx_bytes"); rx_bytes=${rx_bytes:-0}
        tx_bytes=$(stats_get_num "tx_bytes"); tx_bytes=${tx_bytes:-0}
    fi

    # Total depends on which direction(s) are accounted.
    local traffic_mode
    traffic_mode=$(cfg_get "traffic_mode"); traffic_mode=${traffic_mode:-both}
    local total_bytes
    case "$traffic_mode" in
        upload)   total_bytes=$tx_bytes ;;
        download) total_bytes=$rx_bytes ;;
        both|*)   total_bytes=$((rx_bytes + tx_bytes)) ;;
    esac

    # Percentage against the limit (capped at 100).
    local perc=""
    if [ "$has_limit" = "true" ] && [ "$limit_bytes" -gt 0 ]; then
        perc=$(awk "BEGIN {printf \"%.0f\", ($total_bytes * 100) / $limit_bytes}")
        [ -n "$perc" ] && [ "$perc" -gt 100 ] && perc=100
    fi

    # Format output
    TRAFFIC_UP=$(bytes_to_human $tx_bytes)
    TRAFFIC_DOWN=$(bytes_to_human $rx_bytes)
    TRAFFIC_TOTAL=$(bytes_to_human $total_bytes)
    TRAFFIC_LIMIT=$limit
    if [ -n "$perc" ]; then
        TRAFFIC_PERC="${perc}%"
    else
        TRAFFIC_PERC=""
    fi

    # Set traffic mode for display (localized)
    if [ "$SYSINFO_LANG" = "zh" ]; then
        case "$traffic_mode" in
            upload) TRAFFIC_MODE="仅上行" ;;
            download) TRAFFIC_MODE="仅下行" ;;
            both|*) TRAFFIC_MODE="双向" ;;
        esac
    else
        case "$traffic_mode" in
            upload) TRAFFIC_MODE="Upload Only" ;;
            download) TRAFFIC_MODE="Download Only" ;;
            both|*) TRAFFIC_MODE="Bi-directional" ;;
        esac
    fi

    return 0
}

# Convert a normalized limit string (e.g. "1T", "500G", "100M") to bytes.
# Uses bc when available (decimal support), awk otherwise. Echoes the byte
# count and returns 0 on success; returns 1 (no output) if the unit is unknown.
_limit_to_bytes() {
    local limit
    limit=$(normalize_traffic_limit "$1") || return 1
    local num="${limit%[TGM]}"
    local unit="${limit: -1}"
    case "$unit" in
        T) _unit_bytes=$(_math_int "$num * 1024 * 1024 * 1024 * 1024") ;;
        G) _unit_bytes=$(_math_int "$num * 1024 * 1024 * 1024") ;;
        M) _unit_bytes=$(_math_int "$num * 1024 * 1024") ;;
        *) return 1 ;;
    esac
    [ -n "$_unit_bytes" ] && [ "$_unit_bytes" -ne 0 ] || return 1
    echo "$_unit_bytes"
}

# Evaluate an integer arithmetic expression using bc (preferred) or awk.
_math_int() {
    if command -v bc >/dev/null 2>&1; then
        echo "$1 / 1" | bc -l | cut -d. -f1
    else
        awk "BEGIN {printf \"%.0f\", $1}"
    fi
}

# Format a byte-delta over a time delta as a KB/s or MB/s speed string.
_fmt_speed() {
    local diff=$1
    local time_diff=$2
    local kbps
    if command -v bc >/dev/null 2>&1; then
        kbps=$(echo "scale=1; $diff / 1024 / $time_diff" | bc -l | tr -d '\r ' || echo "0")
    else
        kbps=$(awk "BEGIN {printf \"%.1f\", $diff / 1024 / $time_diff}" | tr -d '\r ' || echo "0")
    fi
    if awk "BEGIN {exit !($kbps > 1024)}"; then
        awk "BEGIN {printf \"%.1f MB/s\", $kbps / 1024}" | tr -d '\r'
    else
        awk "BEGIN {printf \"%.1f KB/s\", $kbps}" | tr -d '\r'
    fi
}

# --- Traffic Throttling Functions ---
# Convert rate string to tc format (e.g., 1mbps -> 1Mbit)
convert_rate_to_tc() {
    local rate="$(tolower "$1")"
    local num="${rate%%[a-z]*}"
    local unit="${rate#$num}"

    # Validate number part
    if ! [[ "$num" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    case "$unit" in
        gbps|gbit|gb)
            echo "${num}Gbit"
            ;;
        mbps|mbit|mb)
            echo "${num}Mbit"
            ;;
        kbps|kbit|kb)
            echo "${num}Kbit"
            ;;
        bps|bit|b|"")
            echo "${num}bit"
            ;;
        *)
            return 1
            ;;
    esac
}

ensure_ifb_device() {
    command -v ip >/dev/null 2>&1 || return 1

    # Best-effort module load
    run_privileged modprobe ifb numifbs=1 >/dev/null 2>&1 || true

    if ! ip link show dev "$SYSINFO_IFB_DEV" >/dev/null 2>&1; then
        run_privileged ip link add "$SYSINFO_IFB_DEV" type ifb >/dev/null 2>&1 || return 1
    fi

    run_privileged ip link set dev "$SYSINFO_IFB_DEV" up >/dev/null 2>&1 || return 1
    return 0
}

apply_download_limit_ifb() {
    local interface=$1
    local tc_rate=$2

    ensure_ifb_device || return 1

    # Reset old state to ensure idempotent behavior
    run_privileged tc qdisc del dev "$interface" ingress >/dev/null 2>&1 || true
    run_privileged tc qdisc del dev "$SYSINFO_IFB_DEV" root >/dev/null 2>&1 || true

    run_privileged tc qdisc add dev "$interface" handle ffff: ingress >/dev/null 2>&1 || return 1
    run_privileged tc filter del dev "$interface" parent ffff: >/dev/null 2>&1 || true
    run_privileged tc filter add dev "$interface" parent ffff: protocol all prio 1 u32 \
        match u32 0 0 action mirred egress redirect dev "$SYSINFO_IFB_DEV" >/dev/null 2>&1 || return 1

    apply_htb_fq_limit "$SYSINFO_IFB_DEV" "2" "20" "2:20" "220" "$tc_rate" >/dev/null 2>&1 || {
        run_privileged tc qdisc del dev "$SYSINFO_IFB_DEV" root >/dev/null 2>&1 || true
        run_privileged tc qdisc del dev "$interface" ingress >/dev/null 2>&1 || true
        return 1
    }

    return 0
}

# Apply HTB + fq_codel with the same shaping profile on a device.
# This helper is shared by upload (physical NIC) and download (IFB) to keep
# implementation consistent and easier to maintain.
apply_htb_fq_limit() {
    local dev=$1
    local root_handle=$2
    local default_class=$3
    local classid=$4
    local leaf_handle=$5
    local tc_rate=$6

    run_privileged tc qdisc add dev "$dev" root handle "${root_handle}:" htb default "$default_class" >/dev/null 2>&1 || return 1
    run_privileged tc class add dev "$dev" parent "${root_handle}:" classid "$classid" htb \
        rate "$tc_rate" burst 2M cburst 2M ceil "$tc_rate" prio 0 >/dev/null 2>&1 || return 1

    run_privileged tc qdisc replace dev "$dev" parent "$classid" handle "${leaf_handle}:" fq_codel >/dev/null 2>&1 || {
        run_privileged tc qdisc del dev "$dev" root >/dev/null 2>&1 || true
        return 1
    }

    return 0
}

# Safety guard: avoid tc shaping on router/gateway nodes.
# On gateway devices, changing root qdisc may disrupt forwarding and SSH.
is_gateway_mode() {
    local ipf
    ipf=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo "0")
    [ "$ipf" = "1" ] && return 0
    return 1
}

# Detect default egress interface
get_default_interface() {
    local iface

    iface=$(ip route get 1.1.1.1 2>/dev/null | awk '/dev/ {for (i=1; i<=NF; i++) if ($i == "dev") {print $(i+1); exit}}')
    if [ -n "$iface" ]; then
        echo "$iface"
        return 0
    fi

    iface=$(ip route 2>/dev/null | awk '/^default/ {print $5; exit}')
    if [ -n "$iface" ]; then
        echo "$iface"
        return 0
    fi

    return 1
}

# Report the physical NIC link speed in Mbit/s (e.g. 1000), or nothing if it
# cannot be determined (virtual device, no carrier, missing sysfs entry).
get_nic_link_speed() {
    local iface speed
    iface=$(get_limit_interfaces 2>/dev/null | head -1)
    [ -n "$iface" ] || iface=$(get_default_interface 2>/dev/null)
    [ -n "$iface" ] || return 1
    speed=$(cat "/sys/class/net/$iface/speed" 2>/dev/null | tr -d '\r')
    [[ "$speed" =~ ^[0-9]+$ ]] && [ "$speed" -gt 0 ] || return 1
    echo "$speed"
}

# Collect candidate interfaces for shaping (use default route interface only)
get_limit_interfaces() {
    local iface

    is_safe_physical_iface() {
        local ifn="$1"
        [ -n "$ifn" ] || return 1
        case "$ifn" in
            lo|docker*|br*|veth*|virbr*|tailscale*|wg*|tun*|tap*|Meta*)
                return 1
                ;;
            en*|eth*)
                return 0
                ;;
            *)
                return 1
                ;;
        esac
    }

    # 1) Prefer default route interface only when it's a safe physical NIC.
    #    Note: `ip route get` can be hijacked by transparent proxies (e.g. a
    #    tun device like "Meta"), so the result may be a virtual device.
    iface=$(get_default_interface)
    if is_safe_physical_iface "$iface"; then
        echo "$iface"
        return 0
    fi

    # 2) Fall back to the kernel default route's device (real uplink), which
    #    is not affected by per-destination proxy routing rules.
    iface=$(ip route show default 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i == "dev") {print $(i+1); exit}}')
    if is_safe_physical_iface "$iface"; then
        echo "$iface"
        return 0
    fi

    # 3) Last resort: first UP physical NIC that has a global IPv4 address.
    while read -r ifn; do
        [ -n "$ifn" ] || continue
        is_safe_physical_iface "$ifn" || continue
        if ip -o -4 addr show dev "$ifn" scope global 2>/dev/null | grep -q inet; then
            echo "$ifn"
            return 0
        fi
    done < <(ip -o link show up 2>/dev/null | awk -F': ' '{print $2}' | cut -d@ -f1)

    # No safe interface found -> do not apply shaping.
    return 1
}

apply_rate_limit_all() {
    local rate=$1
    local mode=${2:-both}
    local force=${3:-false}
    local ok_ifaces=""

    while read -r iface; do
        [ -n "$iface" ] || continue
        if apply_rate_limit "$iface" "$rate" "$mode" "$force"; then
            ok_ifaces+="$iface "
        fi
    done < <(get_limit_interfaces)

    if [ -n "$ok_ifaces" ]; then
        echo "$ok_ifaces" | xargs
        return 0
    fi

    return 1
}

remove_rate_limit_all() {
    local mode=${1:-both}
    local ok_ifaces=""

    while read -r iface; do
        [ -n "$iface" ] || continue
        if remove_rate_limit "$iface" "$mode"; then
            ok_ifaces+="$iface "
        fi
    done < <(get_limit_interfaces)

    if [ -n "$ok_ifaces" ]; then
        echo "$ok_ifaces" | xargs
        return 0
    fi

    return 1
}

# Apply rate limiting using tc (traffic control)
# Supports upload/download/both:
# - upload: HTB + fq_codel
# - download: IFB redirect + HTB + fq_codel
apply_rate_limit() {
    local interface=$1
    local rate=$2
    local mode=${3:-both}
    local force=${4:-false}

    # Hard safety stop for router/gateway hosts (unless force is enabled)
    if is_gateway_mode && [ "$force" != "true" ]; then
        return 2
    fi

    command -v tc >/dev/null 2>&1 || return 1
    ip link show dev "$interface" >/dev/null 2>&1 || return 1

    local tc_rate
    tc_rate=$(convert_rate_to_tc "$rate") || return 1

    local apply_upload="false"
    local apply_download="false"
    case "$mode" in
        upload) apply_upload="true" ;;
        download) apply_download="true" ;;
        both|*) apply_upload="true"; apply_download="true" ;;
    esac

    # Fail-safe: extremely low rates can make SSH/session appear disconnected.
    # Reject too-small limits to avoid accidental "network outage" experience.
    local tc_rate_num tc_rate_unit tc_rate_kbit
    tc_rate_num=$(echo "$tc_rate" | sed -E 's/^([0-9]+).*/\1/')
    tc_rate_unit=$(echo "$tc_rate" | sed -E 's/^[0-9]+([A-Za-z]+)$/\1/')
    case "$tc_rate_unit" in
        Gbit) tc_rate_kbit=$((tc_rate_num * 1000 * 1000)) ;;
        Mbit) tc_rate_kbit=$((tc_rate_num * 1000)) ;;
        Kbit) tc_rate_kbit=$tc_rate_num ;;
        bit) tc_rate_kbit=$((tc_rate_num / 1000)) ;;
        *) return 1 ;;
    esac
    if [ "$tc_rate_kbit" -lt 64 ]; then
        return 3
    fi

    # Check if already rate limited (avoid re-applying upload HTB)
    local already_limited=false
    if [ "$apply_upload" = "true" ] && tc qdisc show dev "$interface" 2>/dev/null | grep -q " htb "; then
        already_limited=true
        # Check if rate needs update - delete existing HTB to reapply with new rate
        local existing_class_rate
        existing_class_rate=$(tc class show dev "$interface" 2>/dev/null | grep "htb" | sed -n 's/.*rate \([0-9][0-9]*[KMG]*bit\).*/\1/p' | head -n1 || echo "")
        if [ -n "$existing_class_rate" ]; then
            local existing_rate_kbit
            existing_rate_kbit=$(echo "$existing_class_rate" | sed -E 's/^([0-9]+).*/\1/')
            local existing_unit
            existing_unit=$(echo "$existing_class_rate" | sed -E 's/^[0-9]+([KMG]?bit)$/\1/')
            case "$existing_unit" in
                Gbit) existing_rate_kbit=$((existing_rate_kbit * 1000 * 1000)) ;;
                Mbit) existing_rate_kbit=$((existing_rate_kbit * 1000)) ;;
                Kbit) ;;
                bit) existing_rate_kbit=$((existing_rate_kbit / 1000)) ;;
            esac
            if [ "$existing_rate_kbit" -eq "$tc_rate_kbit" ]; then
                # Ensure low-latency leaf qdisc exists on our shaped class.
                # Use replace to be idempotent (older installs may miss this).
                run_privileged tc qdisc replace dev "$interface" parent 1:10 handle 110: fq_codel >/dev/null 2>&1 || true
                already_limited=true
            else
                run_privileged tc qdisc del dev "$interface" root >/dev/null 2>&1
                already_limited=false
            fi
        fi
    fi

    # CRITICAL FIX: Use HTB (Hierarchical Token Bucket) for upload shaping
    if [ "$apply_upload" = "true" ] && [ "$already_limited" = false ]; then
        # Never delete unknown root qdisc: that can disrupt connectivity.
        # Only proceed when root qdisc is known-safe/default.
        local current_qdisc
        current_qdisc=$(tc qdisc show dev "$interface" 2>/dev/null | grep -o "qdisc [a-z]*" | head -1 | awk '{print $2}')
        case "$current_qdisc" in
            ""|fq|fq_codel|pfifo_fast|noqueue)
                # Upload shaping now uses the same HTB+fq helper as IFB download shaping.
                apply_htb_fq_limit "$interface" "1" "10" "1:10" "110" "$tc_rate" >/dev/null 2>&1 || return 1
                ;;
            htb)
                already_limited=true
                ;;
            *)
                return 4
                ;;
        esac
    fi

    # Apply download limit via IFB redirect + HTB shaping.
    if [ "$apply_download" = "true" ]; then
        apply_download_limit_ifb "$interface" "$tc_rate" || return 1
    fi

    # Verify result by selected mode
    local verify_ok="true"
    if [ "$apply_upload" = "true" ] && ! tc qdisc show dev "$interface" 2>/dev/null | grep -q " htb "; then
        verify_ok="false"
    fi
    if [ "$apply_download" = "true" ] && ! tc qdisc show dev "$interface" 2>/dev/null | grep -q " ingress "; then
        verify_ok="false"
    fi

    if [ "$verify_ok" = "true" ] && [ "$apply_download" = "true" ]; then
        if ! tc qdisc show dev "$SYSINFO_IFB_DEV" 2>/dev/null | grep -q " htb "; then
            verify_ok="false"
        fi
    fi

    if [ "$verify_ok" = "true" ]; then
        return 0
    fi

    return 1
}

# Remove rate limiting
remove_rate_limit() {
    local interface=$1
    local mode=${2:-both}

    command -v tc >/dev/null 2>&1 || return 1
    ip link show dev "$interface" >/dev/null 2>&1 || return 1

    if [ "$mode" = "upload" ] || [ "$mode" = "both" ]; then
        # Check if HTB exists with our handle (1:)
        local root_qdisc
        root_qdisc=$(tc qdisc show dev "$interface" 2>/dev/null | awk '/qdisc htb/ {for(i=1;i<=NF;i++) if($i ~ /^1:$/) print $i}' | tr -d ':')
        if [ -n "$root_qdisc" ]; then
            # Only delete if it's our HTB (handle 1:)
            if [ "$root_qdisc" = "1" ]; then
                run_privileged tc qdisc del dev "$interface" root >/dev/null 2>&1
            fi
        fi
    fi

    if [ "$mode" = "download" ] || [ "$mode" = "both" ]; then
        if tc qdisc show dev "$interface" 2>/dev/null | grep -q " ingress "; then
            run_privileged tc qdisc del dev "$interface" ingress >/dev/null 2>&1
        fi
        # Tear down the IFB device entirely so no inert shim device lingers.
        if ip link show dev "$SYSINFO_IFB_DEV" >/dev/null 2>&1; then
            run_privileged tc qdisc del dev "$SYSINFO_IFB_DEV" root >/dev/null 2>&1 || true
            run_privileged ip link set dev "$SYSINFO_IFB_DEV" down >/dev/null 2>&1 || true
            run_privileged ip link del "$SYSINFO_IFB_DEV" >/dev/null 2>&1 || true
        fi
    fi

    return 0
}

# Fast running-task count from /proc/loadavg (avoids ps fork storm each refresh).
count_running_tasks() {
    local pair
    pair=$(awk '{print $4}' /proc/loadavg 2>/dev/null)
    pair=${pair#*/}
    [[ "$pair" =~ ^[0-9]+$ ]] && echo "$pair" || echo "0"
}

# Throttle/tc checks are expensive; run at most every N seconds unless near threshold.
maybe_check_and_apply_limit() {
    local perc=$1
    local interval="${SYSINFO_THROTTLE_CHECK_INTERVAL:-5}"
    local stamp_file="/var/tmp/sysinfo_throttle_check_ts_${USER:-root}"
    local cache_file="/var/tmp/sysinfo_throttle_cache_${USER:-root}"
    local now last=0 threshold

    now=$(date +%s)
    [ -f "$stamp_file" ] && last=$(cat "$stamp_file" 2>/dev/null)
    [[ "$last" =~ ^[0-9]+$ ]] || last=0

    threshold=$(cfg_get_num "throttle_threshold"); threshold=${threshold:-95}

    # Re-check immediately when usage is close to the configured threshold.
    if [[ "$perc" =~ ^[0-9]+$ ]] && [ "$perc" -ge $((threshold - 2)) ]; then
        check_and_apply_limit "$perc"
        printf '%s\n%s\n' "$THROTTLE_RUNTIME_STATUS" "$THROTTLE_RUNTIME_DETAIL" > "$cache_file" 2>/dev/null
        echo "$now" > "$stamp_file" 2>/dev/null
        return 0
    fi

    if [ $((now - last)) -lt "$interval" ] && [ -f "$cache_file" ]; then
        THROTTLE_RUNTIME_STATUS=$(sed -n '1p' "$cache_file" 2>/dev/null)
        THROTTLE_RUNTIME_DETAIL=$(sed -n '2p' "$cache_file" 2>/dev/null)
        THROTTLE_RUNTIME_STATUS=${THROTTLE_RUNTIME_STATUS:-ready}
        THROTTLE_RUNTIME_DETAIL=${THROTTLE_RUNTIME_DETAIL:-below threshold}
        return 0
    fi

    check_and_apply_limit "$perc"
    printf '%s\n%s\n' "$THROTTLE_RUNTIME_STATUS" "$THROTTLE_RUNTIME_DETAIL" > "$cache_file" 2>/dev/null
    echo "$now" > "$stamp_file" 2>/dev/null
}

# Check and apply traffic limit based on usage.
# CRITICAL: prefer maybe_check_and_apply_limit() in the render loop; this
# function may scan tc state and must not run every refresh tick.
check_and_apply_limit() {
    local perc=$1
    local state_file="/var/tmp/sysinfo_throttle_state"

    THROTTLE_RUNTIME_STATUS="disabled"
    THROTTLE_RUNTIME_DETAIL=""

    # Sync the persisted state file with the actual tc state on entry, so a
    # reboot or manual `tc qdisc del` is reflected without redundant ops.
    local current_state actual_limited
    current_state=$(cat "$state_file" 2>/dev/null)
    if _tc_has_active_limit; then
        actual_limited=true
    else
        actual_limited=false
    fi

    # Reconcile stale state file with reality.
    if [ "$actual_limited" = true ] && [ "$current_state" != "limited" ]; then
        current_state="limited"
        echo "limited" > "$state_file" 2>/dev/null
    elif [ "$actual_limited" = false ] && [ "$current_state" = "limited" ]; then
        current_state="ready"
        echo "ready" > "$state_file" 2>/dev/null
    elif [ -z "$current_state" ]; then
        current_state="ready"
        echo "ready" > "$state_file" 2>/dev/null
    fi

    # Read throttling config
    local throttle_enabled throttle_threshold throttle_rate traffic_mode force_throttle
    throttle_enabled=$(cfg_get_raw "throttle_enabled"); throttle_enabled=${throttle_enabled:-false}
    throttle_threshold=$(cfg_get_num "throttle_threshold"); throttle_threshold=${throttle_threshold:-95}
    throttle_rate=$(cfg_get "throttle_rate"); throttle_rate=${throttle_rate:-1mbps}
    traffic_mode=$(cfg_get "traffic_mode"); traffic_mode=${traffic_mode:-both}
    force_throttle=$(cfg_get_raw "force_throttle"); force_throttle=${force_throttle:-false}

    case "$traffic_mode" in
        upload|download|both) ;;
        *) traffic_mode="both" ;;
    esac

    # Apply direction follows traffic_mode from config.
    local throttle_apply_mode="$traffic_mode"
    local apply_mode_display="$traffic_mode"

    # Throttling disabled or percentage unavailable: clear any stale limit.
    if [ "$throttle_enabled" != "true" ] || ! [[ "$perc" =~ ^[0-9]+$ ]]; then
        if [ "$current_state" = "limited" ]; then
            remove_active_tc_limit
            echo "ready" > "$state_file" 2>/dev/null
        fi
        return 0
    fi

    if [ "$perc" -ge "$throttle_threshold" ]; then
        # Above threshold: gateway guard first.
        if is_gateway_mode && [ "$force_throttle" != "true" ]; then
            THROTTLE_RUNTIME_STATUS="error"
            THROTTLE_RUNTIME_DETAIL="gateway mode detected (ip_forward=1), skip tc for safety"
            return 1
        fi

        # Apply rate limiting only if not already applied.
        if [ "$current_state" != "limited" ]; then
            local applied_ifaces
            applied_ifaces=$(apply_rate_limit_all "$throttle_rate" "$throttle_apply_mode" "$force_throttle")
            if [ -n "$applied_ifaces" ]; then
                echo "limited" > "$state_file" 2>/dev/null
                THROTTLE_RUNTIME_STATUS="limited"
                THROTTLE_RUNTIME_DETAIL="$applied_ifaces @ $throttle_rate ($apply_mode_display)"
                return 0
            fi

            # Fail-safe rollback: ensure no leftover qdisc changes hurt connectivity.
            remove_active_tc_limit
            rm -f "$state_file" 2>/dev/null
            THROTTLE_RUNTIME_STATUS="error"
            THROTTLE_RUNTIME_DETAIL="apply failed on all interfaces (need tc + root/sudo -n)"
            return 1
        fi

        # Already limited, just report status.
        THROTTLE_RUNTIME_STATUS="limited"
        THROTTLE_RUNTIME_DETAIL="active ($apply_mode_display)"
        return 0
    fi

    # Below threshold: remove rate limiting if currently applied.
    if [ "$current_state" = "limited" ]; then
        local cleared_ifaces
        cleared_ifaces=$(remove_rate_limit_all "$throttle_apply_mode")
        if [ -n "$cleared_ifaces" ]; then
            echo "ready" > "$state_file" 2>/dev/null
            THROTTLE_RUNTIME_STATUS="ready"
            THROTTLE_RUNTIME_DETAIL="$cleared_ifaces"
        else
            remove_active_tc_limit
            echo "ready" > "$state_file" 2>/dev/null
            THROTTLE_RUNTIME_STATUS="ready"
            THROTTLE_RUNTIME_DETAIL="below threshold"
        fi
    else
        THROTTLE_RUNTIME_STATUS="ready"
        THROTTLE_RUNTIME_DETAIL="below threshold"
    fi
    return 0
}

# True (0) if any non-loopback interface currently has an HTB or ingress qdisc
# applied by sysinfo's throttling.
_tc_has_active_limit() {
    local iface
    while read -r iface; do
        [ -n "$iface" ] || continue
        if tc qdisc show dev "$iface" 2>/dev/null | grep -q " htb "; then
            return 0
        fi
        if tc qdisc show dev "$iface" 2>/dev/null | grep -q " ingress "; then
            return 0
        fi
    done < <(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | cut -d@ -f1)
    return 1
}

# Read throttle runtime state for display without applying tc changes.
_probe_throttle_runtime_for_display() {
    local cache_file="/var/tmp/sysinfo_throttle_cache_${USER:-root}"

    if _tc_has_active_limit; then
        THROTTLE_RUNTIME_STATUS="limited"
        THROTTLE_RUNTIME_DETAIL=$(sed -n '2p' "$cache_file" 2>/dev/null)
        THROTTLE_RUNTIME_DETAIL=${THROTTLE_RUNTIME_DETAIL:-active}
        return 0
    fi

    if [ -f "$cache_file" ]; then
        THROTTLE_RUNTIME_STATUS=$(sed -n '1p' "$cache_file" 2>/dev/null)
        THROTTLE_RUNTIME_DETAIL=$(sed -n '2p' "$cache_file" 2>/dev/null)
        THROTTLE_RUNTIME_STATUS=${THROTTLE_RUNTIME_STATUS:-ready}
        THROTTLE_RUNTIME_DETAIL=${THROTTLE_RUNTIME_DETAIL:-below threshold}
        return 0
    fi

    THROTTLE_RUNTIME_STATUS="ready"
    THROTTLE_RUNTIME_DETAIL="below threshold"
}

# Print throttle config + runtime status in the network section.
render_throttle_section() {
    local traffic_perc_num="${1:-}"

    [ "$(tolower "$SYSINFO_SHOW_THROTTLE")" = "true" ] || return 0

    if [ ! -f "$SYSINFO_CFG_FILE" ]; then
        if [ "$SYSINFO_LANG" = "zh" ]; then
            dash_kv "$L_THROTTLE_ENABLE" "${YELLOW}未配置${NONE} (运行 sysinfo -c 应用配置)" "$LBL_W"
        else
            dash_kv "$L_THROTTLE_ENABLE" "${YELLOW}Not configured${NONE} (run sysinfo -c)" "$LBL_W"
        fi
        return 0
    fi

    local throttle_enabled throttle_threshold throttle_rate traffic_mode force_throttle
    throttle_enabled=$(cfg_get_raw "throttle_enabled"); throttle_enabled=${throttle_enabled:-false}
    throttle_threshold=$(cfg_get_num "throttle_threshold"); throttle_threshold=${throttle_threshold:-95}
    throttle_rate=$(cfg_get "throttle_rate"); throttle_rate=${throttle_rate:-1mbps}
    traffic_mode=$(cfg_get "traffic_mode"); traffic_mode=${traffic_mode:-both}
    force_throttle=$(cfg_get_raw "force_throttle"); force_throttle=${force_throttle:-false}

    case "$traffic_mode" in
        upload|download|both) ;;
        *) traffic_mode="both" ;;
    esac

    local mode_display rule_suffix=""
    case "$traffic_mode" in
        upload) mode_display="↑" ;;
        download) mode_display="↓" ;;
        *) mode_display="↕" ;;
    esac
    [ "$force_throttle" = "true" ] && rule_suffix=", force gateway"

    if [ "$throttle_enabled" = "true" ]; then
        if [ "$SYSINFO_LANG" = "zh" ]; then
            dash_kv "$L_THROTTLE_ENABLE" "${GREEN}开启${NONE}" "$LBL_W"
        else
            dash_kv "$L_THROTTLE_ENABLE" "${GREEN}On${NONE}" "$LBL_W"
        fi
    else
        if [ "$SYSINFO_LANG" = "zh" ]; then
            dash_kv "$L_THROTTLE_ENABLE" "${YELLOW}关闭${NONE}" "$LBL_W"
        else
            dash_kv "$L_THROTTLE_ENABLE" "${YELLOW}Off${NONE}" "$LBL_W"
        fi
    fi

    if [ "$SYSINFO_LANG" = "zh" ]; then
        dash_kv "$L_THROTTLE_RULE" "≥${throttle_threshold}% → ${throttle_rate} (${mode_display}${rule_suffix})" "$LBL_W"
    else
        dash_kv "$L_THROTTLE_RULE" "≥${throttle_threshold}% → ${throttle_rate} (${mode_display}${rule_suffix})" "$LBL_W"
    fi

    if [ "$throttle_enabled" != "true" ]; then
        if [ "$SYSINFO_LANG" = "zh" ]; then
            dash_kv "$L_THROTTLE_STATUS" "${YELLOW}未启用${NONE}" "$LBL_W"
        else
            dash_kv "$L_THROTTLE_STATUS" "${YELLOW}Disabled${NONE}" "$LBL_W"
        fi
        return 0
    fi

    if [[ "$traffic_perc_num" =~ ^[0-9]+$ ]]; then
        maybe_check_and_apply_limit "$traffic_perc_num"
    else
        _probe_throttle_runtime_for_display
    fi

    case "$THROTTLE_RUNTIME_STATUS" in
        limited)
            if [ "$SYSINFO_LANG" = "zh" ]; then
                dash_kv "$L_THROTTLE_STATUS" "${RED}限速中${NONE} (${THROTTLE_RUNTIME_DETAIL})" "$LBL_W"
            else
                dash_kv "$L_THROTTLE_STATUS" "${RED}Active${NONE} (${THROTTLE_RUNTIME_DETAIL})" "$LBL_W"
            fi
            ;;
        error)
            if [ "$SYSINFO_LANG" = "zh" ]; then
                dash_kv "$L_THROTTLE_STATUS" "${YELLOW}触发失败${NONE} (${THROTTLE_RUNTIME_DETAIL})" "$LBL_W"
            else
                dash_kv "$L_THROTTLE_STATUS" "${YELLOW}Failed${NONE} (${THROTTLE_RUNTIME_DETAIL})" "$LBL_W"
            fi
            ;;
        *)
            if [ "$SYSINFO_LANG" = "zh" ]; then
                dash_kv "$L_THROTTLE_STATUS" "${GREEN}未限速${NONE} (${THROTTLE_RUNTIME_DETAIL})" "$LBL_W"
            else
                dash_kv "$L_THROTTLE_STATUS" "${GREEN}Idle${NONE} (${THROTTLE_RUNTIME_DETAIL})" "$LBL_W"
            fi
            ;;
    esac
}

# --- Dashboard render ---
# Collects system metrics and prints the dashboard. Wrapped in a function so
# that sourcing this file only defines functions (no side effects); callers
# invoke sysinfo_render explicitly. Direct execution runs it automatically.
sysinfo_render() {

# --- Data Collection ---
# Get CPU usage using uptime/load average (simplest and most reliable)
LOAD_AVG=$(cat /proc/loadavg 2>/dev/null | tr -d '\r' | awk '{print $1}' || echo "0")
# Validate LOAD_AVG is numeric
if ! [[ "$LOAD_AVG" =~ ^[0-9]+\.?[0-9]*$ ]]; then
    LOAD_AVG="0"
fi
CPU_CORES=$(get_cpu_core_count | tr -d '\r')
# Calculate CPU usage - use bc if available, otherwise use awk
if command -v bc >/dev/null 2>&1; then
    CPU_USAGE_NUM=$(echo "scale=1; $LOAD_AVG * 100 / $CPU_CORES" | bc -l | tr -d '\r' || echo "0")
else
    CPU_USAGE_NUM=$(awk "BEGIN {printf \"%.1f\", $LOAD_AVG * 100 / $CPU_CORES}" | tr -d '\r' || echo "0")
fi
CPU_USAGE=$(printf "%.1f%%" "$CPU_USAGE_NUM")
PROCESSES=$(count_running_tasks)
USERS_LOGGED=$(who 2>/dev/null | wc -l || echo "0")
MEM_TOTAL=$(free -h 2>/dev/null | awk 'NR==2{print $2}' || echo "N/A")
MEM_USED=$(free -h 2>/dev/null | awk 'NR==2{print $3}' || echo "N/A")
MEM_PERC_NUM=$(free -m 2>/dev/null | awk 'NR==2{printf "%d", $3*100/$2}' || echo "0")
MEM_INFO="$MEM_USED / $MEM_TOTAL ($MEM_PERC_NUM%)"
SWAP_TOTAL_M=$(free -m 2>/dev/null | awk 'NR==3{print $2}' || echo "0")
if [ "$SWAP_TOTAL_M" -gt 0 ]; then
    SWAP_PERC_NUM=$(free -m 2>/dev/null | awk 'NR==3{printf "%d", $3*100/$2}' || echo "0")
    SWAP_USAGE="${SWAP_PERC_NUM}%"
else
    SWAP_USAGE="None"
fi
# Get IP addresses - properly handle IPv4 vs IPv6
ALL_IPS=$(hostname -I 2>/dev/null || echo "")
FIRST_IP=$(echo "$ALL_IPS" | awk '{print $1}')

# Check if first IP is IPv4 or IPv6
if [[ "$FIRST_IP" == *:* ]]; then
    # First IP is IPv6, no IPv4
    IP_V4="N/A"
    # Use first non-IPv6-like IP as IPv4 if available
    IP_V4_FALLBACK=$(echo "$ALL_IPS" | awk '{for(i=1;i<=NF;i++) if($i !~ /:/) print $i; exit}' | head -1)
    [ -n "$IP_V4_FALLBACK" ] && IP_V4="$IP_V4_FALLBACK"
else
    # First IP is IPv4
    IP_V4="$FIRST_IP"
fi

# Get IPv6 address - prioritize physical ethernet interfaces (en*, eth*)
# Then fallback to other interfaces, excluding temporary addresses
get_ipv6() {
    local interfaces="$1"
    timeout 1 ip -6 addr show scope global $interfaces 2>/dev/null | grep inet6 | grep -v "temporary" | awk '{print $2}' | cut -d'/' -f1 | sort | head -n 1 || echo ""
}

# Try physical ethernet interfaces first (en*, eth*)
IP_V6=$(get_ipv6 "en*" 2>/dev/null)
if [ -z "$IP_V6" ]; then
    IP_V6=$(get_ipv6 "eth*" 2>/dev/null)
fi
# Fallback: get from any global interface (sorted for consistency)
if [ -z "$IP_V6" ]; then
    IP_V6=$(timeout 1 ip -6 addr show scope global 2>/dev/null | grep inet6 | grep -v "temporary" | awk '{print $2}' | cut -d'/' -f1 | sort | head -n 1 || echo "")
fi
# Last fallback: include temporary addresses
if [ -z "$IP_V6" ]; then
    IP_V6=$(timeout 1 ip -6 addr show scope global 2>/dev/null | grep inet6 | awk '{print $2}' | cut -d'/' -f1 | sort | head -n 1 || echo "")
fi
[ -z "$IP_V6" ] && IP_V6="N/A"
UPTIME=$(uptime -p 2>/dev/null | sed 's/up //' || echo "N/A")

# --- Network Speed Calculation ---
# Get network stats (exclude loopback) - sum all interfaces
read_net_counters
RX_BYTES=$RX_TOTAL
TX_BYTES=$TX_TOTAL

# Try to get previous stats from temp file for speed calculation
# Use /var/tmp for better permission handling
NET_STATS_FILE="/var/tmp/sysinfo_net_stats_${USER:-root}"
if [ -f "$NET_STATS_FILE" ]; then
    PREV_RX=$(cat "$NET_STATS_FILE" 2>/dev/null | cut -d' ' -f1 || echo "0")
    PREV_TX=$(cat "$NET_STATS_FILE" 2>/dev/null | cut -d' ' -f2 || echo "0")
    PREV_TIME=$(cat "$NET_STATS_FILE" 2>/dev/null | cut -d' ' -f3 || echo "0")
else
    PREV_RX="0"
    PREV_TX="0"
    PREV_TIME="0"
fi

# Save current stats
CURRENT_TIME=$(date +%s)
echo "$RX_BYTES $TX_BYTES $CURRENT_TIME" > "$NET_STATS_FILE" 2>/dev/null

# Update monthly traffic statistics - pass current stats
update_traffic_stats "$RX_BYTES" "$TX_BYTES"

# Get traffic statistics for display
get_traffic_stats
TRAFFIC_AVAILABLE=$?

# Validate variables are numeric
PREV_TIME=${PREV_TIME:-0}
PREV_RX=${PREV_RX:-0}
PREV_TX=${PREV_TX:-0}
CURRENT_TIME=${CURRENT_TIME:-$(date +%s)}
RX_BYTES=${RX_BYTES:-0}
TX_BYTES=${TX_BYTES:-0}

# Ensure they are numeric
[[ ! "$PREV_TIME" =~ ^[0-9]+$ ]] && PREV_TIME=0
[[ ! "$PREV_RX" =~ ^[0-9]+$ ]] && PREV_RX=0
[[ ! "$PREV_TX" =~ ^[0-9]+$ ]] && PREV_TX=0
[[ ! "$CURRENT_TIME" =~ ^[0-9]+$ ]] && CURRENT_TIME=$(date +%s)
[[ ! "$RX_BYTES" =~ ^[0-9]+$ ]] && RX_BYTES=0
[[ ! "$TX_BYTES" =~ ^[0-9]+$ ]] && TX_BYTES=0

# Calculate speed if we have previous data (at least 1 second ago)
# Per-direction throughput in Mbit/s (download=rx, upload=tx) plus the NIC link
# speed; the notify module applies custom rates / direction mode / threshold.
NIC_RX_MBPS=""
NIC_TX_MBPS=""
NIC_LINK_SPEED=""
if [ "$PREV_TIME" -gt 0 ] && [ $((CURRENT_TIME - PREV_TIME)) -ge 1 ]; then
    TIME_DIFF=$((CURRENT_TIME - PREV_TIME))
    RX_DIFF=$((RX_BYTES - PREV_RX))
    TX_DIFF=$((TX_BYTES - PREV_TX))
    [ "$RX_DIFF" -lt 0 ] && RX_DIFF=0
    [ "$TX_DIFF" -lt 0 ] && TX_DIFF=0
    RX_SPEED_FMT=$(_fmt_speed "$RX_DIFF" "$TIME_DIFF")
    TX_SPEED_FMT=$(_fmt_speed "$TX_DIFF" "$TIME_DIFF")
    NIC_RX_MBPS=$(awk -v b="$RX_DIFF" -v t="$TIME_DIFF" 'BEGIN{ if(t<=0)exit; printf "%d", b/t*8/1000000 }')
    NIC_TX_MBPS=$(awk -v b="$TX_DIFF" -v t="$TIME_DIFF" 'BEGIN{ if(t<=0)exit; printf "%d", b/t*8/1000000 }')
    NIC_LINK_SPEED=$(get_nic_link_speed)
else
    # No previous data or not enough time passed
    RX_SPEED_FMT="0 KB/s"
    TX_SPEED_FMT="0 KB/s"
fi

# Try multiple methods to get CPU model
CPU_MODEL=""
if [ -f /proc/cpuinfo ]; then
    # Method 1: /proc/cpuinfo (most reliable)
    CPU_MODEL=$(grep -m 1 'model name' /proc/cpuinfo 2>/dev/null | tr -d '\r' | awk -F: '{for(i=2;i<=NF;i++) printf "%s ", $i}' | tr -d '\r' | xargs 2>/dev/null || echo "")
fi
# Fallback to lscpu if /proc/cpuinfo didn't work
if [ -z "$CPU_MODEL" ] || [ "$CPU_MODEL" = "N/A" ]; then
    CPU_MODEL=$(timeout 1 lscpu 2>/dev/null | grep "Model name" | tr -d '\r' | sed 's/Model name: *//' | sed 's/BIOS.*//' | tr -d '\r' | xargs 2>/dev/null || echo "")
fi
# Final fallback
if [ -z "$CPU_MODEL" ] || [ "$CPU_MODEL" = "N/A" ]; then
    CPU_MODEL="N/A"
fi
if [ "$SYSINFO_LANG" = "zh" ]; then
    CPU_CORE_TEXT="${CPU_CORES} 核"
elif [ "$CPU_CORES" = "1" ]; then
    CPU_CORE_TEXT="1 core"
else
    CPU_CORE_TEXT="${CPU_CORES} cores"
fi

# Load NAT config if exists
NAT_RANGE=""
if [ -f /etc/sysinfo-nat ]; then
    NAT_RANGE=$(cat /etc/sysinfo-nat 2>/dev/null | xargs || echo "")
    # Normalize "public:private" or "public-private" to "public->private".
    NAT_RANGE=$(echo "$NAT_RANGE" | sed -E 's/([0-9]+)[:-]([0-9]+)/\1->\2/g')
fi

# --- Print Dashboard ---
echo -e "${CYAN}================================================================${NONE}"
echo -e "  ${BOLD}$L_TITLE${NONE} - $(date +'%Y-%m-%d %H:%M:%S')"
echo -e "${CYAN}================================================================${NONE}"

# One label width for the whole dashboard so every colon lines up vertically.
LBL_W=$(calc_label_width \
    "$L_CPU" "$L_IPV4" "$L_IPV6" "$L_NAT" "$L_UPTIME" \
    "$L_LOAD" "$L_MEM" "$L_SWAP" "$L_PROCS" "$L_USERS" \
    "$L_DOWNLOAD" "$L_UPLOAD" "$L_TOTAL" "$L_LIMIT" \
    "$L_TRAFFIC_MODE" "$L_TRAFFIC_PERC" \
    "$L_THROTTLE_ENABLE" "$L_THROTTLE_STATUS" "$L_THROTTLE_RULE")

printf "${GREEN}%-s${NONE}\n" "$L_CORE"
dash_kv "$L_CPU" "$CPU_MODEL ($CPU_CORE_TEXT)" "$LBL_W"
dash_kv "$L_IPV4" "$IP_V4" "$LBL_W"
dash_kv "$L_IPV6" "$IP_V6" "$LBL_W"
if [ "$(tolower "$SYSINFO_SHOW_NAT")" = "true" ]; then
    if [ -n "$NAT_RANGE" ]; then
        dash_kv "$L_NAT" "$NAT_RANGE" "$LBL_W"
    elif [ "$SYSINFO_LANG" = "zh" ]; then
        dash_kv "$L_NAT" "${YELLOW}未启用${NONE}" "$LBL_W"
    else
        dash_kv "$L_NAT" "${YELLOW}Disabled${NONE}" "$LBL_W"
    fi
fi
dash_kv "$L_UPTIME" "$UPTIME" "$LBL_W"

printf "${GREEN}%-s${NONE}\n" "$L_RES"
dash_kv2 "$L_LOAD" "$CPU_USAGE" "$L_PROCS" "$PROCESSES" "$LBL_W"
dash_kv2 "$L_MEM" "$MEM_INFO" "$L_USERS" "$USERS_LOGGED" "$LBL_W"
dash_kv "$L_SWAP" "$SWAP_USAGE" "$LBL_W"

printf "${GREEN}%-s${NONE}\n" "$L_NET"
TRAFFIC_PERC_NUM=""
if [ "$(tolower "$SYSINFO_SHOW_TRAFFIC")" = "true" ] && [ "$TRAFFIC_AVAILABLE" -eq 0 ]; then
    dash_kv2 "$L_DOWNLOAD" "$RX_SPEED_FMT ($TRAFFIC_DOWN)" "$L_UPLOAD" "$TX_SPEED_FMT ($TRAFFIC_UP)" "$LBL_W"
    dash_kv2 "$L_TOTAL" "$TRAFFIC_TOTAL" "$L_LIMIT" "$TRAFFIC_LIMIT" "$LBL_W"
    if [ -z "$TRAFFIC_MODE" ]; then
        [ "$SYSINFO_LANG" = "zh" ] && TRAFFIC_MODE="双向" || TRAFFIC_MODE="Bi-directional"
    fi
    dash_kv "$L_TRAFFIC_MODE" "$TRAFFIC_MODE" "$LBL_W"
    if [ -n "$TRAFFIC_PERC" ]; then
        TRAFFIC_PERC_NUM=$(echo "$TRAFFIC_PERC" | tr -d '%')
        TRAFFIC_PERC_NUM=${TRAFFIC_PERC_NUM:-0}
        printf "  %s : [" "$(pad_label "$L_TRAFFIC_PERC" "$LBL_W")"
        draw_bar $TRAFFIC_PERC_NUM 10
        printf "] %s\n" "$TRAFFIC_PERC"
    else
        dash_kv "$L_TRAFFIC_PERC" "N/A (Unlimited)" "$LBL_W"
    fi
else
    if [ "$(tolower "$SYSINFO_SHOW_TRAFFIC")" = "true" ]; then
        dash_kv2 "$L_DOWNLOAD" "$RX_SPEED_FMT" "$L_UPLOAD" "$TX_SPEED_FMT" "$LBL_W"
    fi
fi
render_throttle_section "$TRAFFIC_PERC_NUM"

DISK_MNT_W=18
DISK_NUM_W=8
printf "${GREEN}%-s${NONE}\n" "$L_DISK"
printf "  %s %s %s %s  %s\n" \
    "$(pad_label "$L_MNT" "$DISK_MNT_W")" \
    "$(pad_label_right "$L_SIZE" "$DISK_NUM_W")" \
    "$(pad_label_right "$L_USED" "$DISK_NUM_W")" \
    "$(pad_label_right "$L_PERC" "$DISK_NUM_W")" \
    "$L_PROG"
echo -e "  -------------------------------------------------------------"
df -h -x tmpfs -x devtmpfs -x squashfs -x debugfs -x overlay -x efivarfs 2>/dev/null | tail -n +2 | while IFS=' ' read -r filesystem size used avail perc mnt rest; do
    if [ -n "$mnt" ] && [[ "$mnt" == /* ]]; then
        if [[ "$mnt" == /boot/efi ]] || [[ "$mnt" == /boot ]]; then
            continue
        fi
        if [ ${#mnt} -gt "$DISK_MNT_W" ]; then
            mnt="${mnt:0:$((DISK_MNT_W - 3))}..."
        fi
        PERC_NUM=$(echo "$perc" | tr -d '%')
        printf "  %-${DISK_MNT_W}s %${DISK_NUM_W}s %${DISK_NUM_W}s %${DISK_NUM_W}s [" \
            "$mnt" "$size" "$used" "$perc"
        draw_bar $PERC_NUM 10
        printf "]\n"
    fi
done
echo -e "${CYAN}================================================================${NONE}"

# --- Push notifications (no-op unless the notify module is loaded & enabled) ---
# Disk usage is evaluated inside the module (it supports per-path rules).
if declare -f notify_check >/dev/null 2>&1; then
    notify_check "$CPU_USAGE_NUM" "$TRAFFIC_PERC_NUM" "$THROTTLE_RUNTIME_STATUS" \
        "$NIC_RX_MBPS" "$NIC_TX_MBPS" "$NIC_LINK_SPEED"
fi

}

# When executed directly (not sourced), render once. When sourced, only
# function definitions are loaded; the caller decides when to render.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    sysinfo_render
fi
