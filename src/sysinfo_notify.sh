#!/bin/bash

# ============================================
# sysinfo-cli - Push Notification Module
# ============================================
# Modular alerting layer. Currently ships a Bark provider. Rules are evaluated
# against runtime metrics (CPU%, traffic quota%, throttle state, disk%) and
# dispatched to enabled providers. Designed to be sourced by sysinfo.sh, where
# get_config()/tolower() are available; it never renders anything itself.
#
# Adding a provider: implement notify_send_<name>() and call it from
# notify_dispatch(). Adding a rule: read its config in notify_check() and call
# _notify_eval with a unique rule key.

# Per-rule state for edge detection + cooldown (avoid alert spam).
# Keyed per-user so root (cron) and interactive runs never clash on ownership
# in the sticky /var/tmp directory.
NOTIFY_STATE_FILE="${SYSINFO_NOTIFY_STATE:-/var/tmp/sysinfo-notify-state-${USER:-$(id -un 2>/dev/null || echo root)}}"

# Fallbacks so the module is safe even if sourced standalone.
if ! declare -f tolower >/dev/null 2>&1; then
    tolower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
fi
if ! declare -f get_config >/dev/null 2>&1; then
    get_config() { echo "${2:-}"; }
fi
if ! declare -f get_config_list >/dev/null 2>&1; then
    get_config_list() { return 0; }
fi

notify_is_enabled() {
    [ "$(tolower "$(get_config "notify.enabled" "false")")" = "true" ]
}

notify_cooldown() {
    local c
    c=$(get_config "notify.cooldown" "1800")
    [[ "$c" =~ ^[0-9]+$ ]] || c=1800
    echo "$c"
}

# --- Providers --------------------------------------------------------------

# Bark (https://bark.day.app). POST form to <url>/<key> with title/body/group.
notify_send_bark() {
    local title="$1" body="$2" group="${3:-sysinfo-cli}"
    local url key
    url=$(get_config "notify.bark.url" "https://api.day.app")
    key=$(get_config "notify.bark.key" "")
    [ -n "$key" ] && [ "$key" != "null" ] || return 1
    command -v curl >/dev/null 2>&1 || return 1
    url="${url%/}"
    curl -fsS -m 8 -X POST "$url/$key" \
        --data-urlencode "title=$title" \
        --data-urlencode "body=$body" \
        --data-urlencode "group=$group" \
        --data-urlencode "level=active" >/dev/null 2>&1
}

# Fan out to every enabled provider. Returns 0 if at least one succeeded.
notify_dispatch() {
    local title="$1" body="$2" group="${3:-sysinfo-cli}"
    local ok=1
    if [ -n "$(get_config "notify.bark.key" "")" ]; then
        notify_send_bark "$title" "$body" "$group" && ok=0
    fi
    return $ok
}

# --- State helpers ----------------------------------------------------------

_notify_state_get() {
    grep "^$1=" "$NOTIFY_STATE_FILE" 2>/dev/null | head -1 | cut -d= -f2-
}

_notify_state_set() {
    local key="$1" val="$2" rest
    mkdir -p "$(dirname "$NOTIFY_STATE_FILE")" 2>/dev/null
    rest=$(grep -v "^$key=" "$NOTIFY_STATE_FILE" 2>/dev/null)
    { [ -n "$rest" ] && printf '%s\n' "$rest"; printf '%s=%s\n' "$key" "$val"; } \
        > "$NOTIFY_STATE_FILE.tmp" 2>/dev/null \
        && mv "$NOTIFY_STATE_FILE.tmp" "$NOTIFY_STATE_FILE" 2>/dev/null
}

# Edge-triggered dispatch with cooldown.
# Fires once when a rule first becomes active, then re-fires every cooldown
# seconds while it stays active. Clears state when the condition recovers.
# Args: rule_key active(0|1) title body
_notify_eval() {
    local key="$1" active="$2" title="$3" body="$4"
    local now prev pstate pepoch cooldown
    now=$(date +%s)
    cooldown=$(notify_cooldown)
    prev=$(_notify_state_get "$key")
    pstate="${prev%%:*}"
    pepoch="${prev##*:}"
    [[ "$pepoch" =~ ^[0-9]+$ ]] || pepoch=0

    if [ "$active" = "1" ]; then
        if [ "$pstate" != "active" ] || [ $((now - pepoch)) -ge "$cooldown" ]; then
            # Background the send so rendering / cron never blocks on the network.
            ( notify_dispatch "$title" "$body" "sysinfo-cli" ) >/dev/null 2>&1 &
            _notify_state_set "$key" "active:$now"
        fi
    else
        [ "$pstate" = "active" ] && _notify_state_set "$key" "clear:$now"
    fi
}

# --- Rule engine ------------------------------------------------------------

_notify_rule_on() {
    [ "$(tolower "$(get_config "notify.rules.$1.enabled" "false")")" = "true" ]
}

_notify_threshold() {
    local t
    t=$(get_config "notify.rules.$1.threshold" "$2")
    [[ "$t" =~ ^[0-9]+$ ]] || t="$2"
    echo "$t"
}

# Hostname used in alert titles (set once per check).
NOTIFY_HOST="host"

# Usage percent for a single path/mount via df. Empty on failure.
_notify_path_usage() {
    df -P "$1" 2>/dev/null | awk 'NR==2{gsub("%","",$5); print $5+0}'
}

# Disk rule. Supports an optional path list (notify.rules.disk.paths):
#   - empty  -> evaluate every real mount, alert per offending mount
#   - listed -> evaluate each given mount point / directory
# Each path gets its own state key so disks alert/recover independently.
_notify_check_disk() {
    _notify_rule_on "disk" || return 0
    local thr paths use p mnt
    thr=$(_notify_threshold "disk" 90)
    paths=$(get_config_list "notify.rules.disk.paths")

    if [ -n "$paths" ]; then
        while IFS= read -r p; do
            [ -n "$p" ] || continue
            use=$(_notify_path_usage "$p")
            [[ "$use" =~ ^[0-9]+$ ]] || continue
            if [ "$use" -ge "$thr" ]; then
                _notify_eval "disk:$p" 1 "[$NOTIFY_HOST] 磁盘告警" "$p 使用率 ${use}% ≥ ${thr}%"
            else
                _notify_eval "disk:$p" 0 "" ""
            fi
        done <<< "$paths"
    else
        while read -r mnt use; do
            [ -n "$mnt" ] || continue
            if [ "$use" -ge "$thr" ]; then
                _notify_eval "disk:$mnt" 1 "[$NOTIFY_HOST] 磁盘告警" "$mnt 使用率 ${use}% ≥ ${thr}%"
            else
                _notify_eval "disk:$mnt" 0 "" ""
            fi
        done < <(df -P -x tmpfs -x devtmpfs -x squashfs -x debugfs -x overlay -x efivarfs 2>/dev/null \
            | awk 'NR>1 && $6 ~ /^\// {gsub("%","",$5); print $6, $5+0}')
    fi
}

# NIC throughput rule. Per-direction utilization = current Mbps / rate, where
# rate is the configured custom bandwidth or (fallback) the NIC link speed.
# mode selects which direction(s) to evaluate: upload | download | both.
# Args: rx_mbps(download) tx_mbps(upload) link_speed_mbps
_notify_check_nic() {
    _notify_rule_on "nic" || return 0
    local rx="$1" tx="$2" link="$3" thr mode up_rate down_rate p
    thr=$(_notify_threshold "nic" 80)
    mode=$(tolower "$(get_config "notify.rules.nic.mode" "both")")
    case "$mode" in upload|download|both) ;; *) mode="both" ;; esac

    up_rate=$(get_config "notify.rules.nic.upload_rate" "0")
    down_rate=$(get_config "notify.rules.nic.download_rate" "0")
    [[ "$up_rate" =~ ^[0-9]+$ ]] || up_rate=0
    [[ "$down_rate" =~ ^[0-9]+$ ]] || down_rate=0
    # 0 / unset custom rate => fall back to detected NIC link speed.
    [ "$up_rate" -gt 0 ] || up_rate="$link"
    [ "$down_rate" -gt 0 ] || down_rate="$link"

    if [ "$mode" = "upload" ] || [ "$mode" = "both" ]; then
        if [[ "$tx" =~ ^[0-9]+$ ]] && [[ "$up_rate" =~ ^[0-9]+$ ]] && [ "$up_rate" -gt 0 ]; then
            p=$(( tx * 100 / up_rate ))
            if [ "$p" -ge "$thr" ]; then
                _notify_eval "nic:up" 1 "[$NOTIFY_HOST] 上行带宽告警" "上行 ${tx}Mbps 已达带宽 ${p}% ≥ ${thr}% (上限 ${up_rate}Mbps)"
            else
                _notify_eval "nic:up" 0 "" ""
            fi
        fi
    fi

    if [ "$mode" = "download" ] || [ "$mode" = "both" ]; then
        if [[ "$rx" =~ ^[0-9]+$ ]] && [[ "$down_rate" =~ ^[0-9]+$ ]] && [ "$down_rate" -gt 0 ]; then
            p=$(( rx * 100 / down_rate ))
            if [ "$p" -ge "$thr" ]; then
                _notify_eval "nic:down" 1 "[$NOTIFY_HOST] 下行带宽告警" "下行 ${rx}Mbps 已达带宽 ${p}% ≥ ${thr}% (上限 ${down_rate}Mbps)"
            else
                _notify_eval "nic:down" 0 "" ""
            fi
        fi
    fi
}

# Evaluate all rules against current metrics.
# Args: cpu_pct net_quota_pct throttle_status rx_mbps tx_mbps nic_link_speed
# Any metric may be empty/non-numeric and is skipped for the relevant rule.
# Disk is evaluated internally (supports per-path rules).
notify_check() {
    [ "${SYSINFO_NOTIFY_SKIP:-}" = "1" ] && return 0
    notify_is_enabled || return 0

    local cpu net throttle thr
    NOTIFY_HOST=$(hostname 2>/dev/null || echo "host")
    cpu="${1%%.*}"
    net="${2%%.*}"
    throttle="${3:-}"

    # CPU usage quota
    if _notify_rule_on "cpu" && [[ "$cpu" =~ ^[0-9]+$ ]]; then
        thr=$(_notify_threshold "cpu" 90)
        if [ "$cpu" -ge "$thr" ]; then
            _notify_eval "cpu" 1 "[$NOTIFY_HOST] CPU 告警" "CPU 使用率 ${cpu}% ≥ ${thr}%"
        else
            _notify_eval "cpu" 0 "" ""
        fi
    fi

    # Network traffic quota (monthly)
    if _notify_rule_on "net" && [[ "$net" =~ ^[0-9]+$ ]]; then
        thr=$(_notify_threshold "net" 90)
        if [ "$net" -ge "$thr" ]; then
            _notify_eval "net" 1 "[$NOTIFY_HOST] 流量告警" "月流量已用 ${net}% ≥ ${thr}%"
        else
            _notify_eval "net" 0 "" ""
        fi
    fi

    # NIC bandwidth quota (per-direction; custom rates + direction mode)
    _notify_check_nic "${4%%.*}" "${5%%.*}" "${6%%.*}"

    # Throttle activation
    if _notify_rule_on "throttle"; then
        if [ "$throttle" = "limited" ]; then
            _notify_eval "throttle" 1 "[$NOTIFY_HOST] 限速已触发" "网络限速已激活 (流量超阈值)"
        else
            _notify_eval "throttle" 0 "" ""
        fi
    fi

    # Disk usage quota (all mounts or configured paths)
    _notify_check_disk
}

# Send a test notification to verify provider config.
notify_test() {
    local host
    host=$(hostname 2>/dev/null || echo "host")
    if ! notify_is_enabled; then
        echo "notify.enabled = false (推送未开启)"
        return 1
    fi
    if [ -z "$(get_config "notify.bark.key" "")" ]; then
        echo "notify.bark.key 未配置"
        return 1
    fi
    if notify_dispatch "[$host] sysinfo-cli 测试" "推送通道工作正常 $(date '+%Y-%m-%d %H:%M:%S')" "sysinfo-cli"; then
        echo "✓ 测试推送已发送 (test notification sent)"
        return 0
    fi
    echo "✗ 推送失败，请检查 bark.url / bark.key 与网络"
    return 1
}
