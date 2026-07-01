#!/bin/bash
# Regression checks run inside each supported Docker distro after install.sh.
set -euo pipefail

fail() {
  echo "[REGRESSION FAIL] $*" >&2
  exit 1
}

strip_ansi() {
  sed -E 's/\x1B\[[0-9;?]*[[:alpha:]]//g'
}

assert_contains() {
  local haystack="$1" pattern="$2" label="$3"
  if ! printf '%s\n' "$haystack" | grep -Eq "$pattern"; then
    fail "$label (missing pattern: $pattern)"
  fi
}

SYSINFO="${SYSINFO_CMD:-sysinfo}"
CONFIG="/tmp/sysinfo-regression.yaml"

cat > "$CONFIG" <<'YAML'
network:
  interface: ""
  force_gateway_throttle: false

nat:
  enabled: true
  ranges:
    - "48081-48089"
  mappings:
    - "48081:80"
    - "48082:3000"

traffic:
  enabled: true
  limit: "1G"
  reset_day: 1
  mode: "both"

throttle:
  enabled: true
  threshold: 95
  rate: "10mbps"

display:
  language: "en"
  refresh_interval: 1
  show_traffic: true
  show_nat: true
  show_throttle: true
YAML

APPLY_OUT=$("$SYSINFO" -c "$CONFIG" 2>&1)
assert_contains "$APPLY_OUT" 'Traffic configured: 1G' "config apply writes traffic"
assert_contains "$APPLY_OUT" 'NAT configured: ranges=48081-48089;mappings=48081:80 48082:3000' "config apply writes NAT"
assert_contains "$APPLY_OUT" 'Throttle enabled: 95% @ 10mbps' "config apply writes throttle"

[ -f /etc/sysinfo-traffic ] || fail "/etc/sysinfo-traffic missing"
[ -f /etc/sysinfo-nat ] || fail "/etc/sysinfo-nat missing"

TRAFFIC_CFG=$(cat /etc/sysinfo-traffic)
assert_contains "$TRAFFIC_CFG" '"limit":"1G"' "traffic limit persisted"
assert_contains "$TRAFFIC_CFG" '"traffic_mode":"both"' "traffic mode persisted"
assert_contains "$TRAFFIC_CFG" '"throttle_enabled":true' "throttle enabled persisted"
assert_contains "$TRAFFIC_CFG" '"throttle_threshold":95' "throttle threshold persisted"
assert_contains "$TRAFFIC_CFG" '"throttle_rate":"10mbps"' "throttle rate persisted"

NAT_CFG=$(cat /etc/sysinfo-nat)
assert_contains "$NAT_CFG" '^ranges=48081-48089;mappings=48081:80 48082:3000$' "NAT runtime config persisted"

# Prime the previous network sample, then render again after one second so
# download/upload speed formatting exercises the delta path.
"$SYSINFO" >/dev/null 2>&1 || true
sleep 1
DASHBOARD=$("$SYSINFO" 2>&1 | strip_ansi)
assert_contains "$DASHBOARD" 'System Information Dashboard|系统信息' "dashboard title"
assert_contains "$DASHBOARD" 'CPU' "dashboard CPU display"
assert_contains "$DASHBOARD" 'NAT[[:space:]]*: Open: 48081-48089 \| Map: 48081->80 48082->3000' "dashboard NAT display"
assert_contains "$DASHBOARD" 'Download[[:space:]]*: .*B/s' "dashboard download speed display"
assert_contains "$DASHBOARD" 'Upload[[:space:]]*: .*B/s' "dashboard upload speed display"
assert_contains "$DASHBOARD" '(Limit|Quota)[[:space:]]*: 1G' "dashboard traffic limit display"
assert_contains "$DASHBOARD" 'Traffic Mode[[:space:]]*: Bi-directional' "dashboard traffic mode display"
assert_contains "$DASHBOARD" 'Usage[[:space:]]*: .*%' "dashboard traffic usage display"
assert_contains "$DASHBOARD" 'Throttle[[:space:]]*: .*On' "dashboard throttle enabled display"
assert_contains "$DASHBOARD" 'Throttle Rule[[:space:]]*: .*95%.*10mbps' "dashboard throttle rule display"
assert_contains "$DASHBOARD" 'Throttle Status[[:space:]]*: .*Idle|Throttle Status[[:space:]]*: .*Failed|Throttle Status[[:space:]]*: .*Active' "dashboard throttle status display"

BANNER_ZH=$(SYSINFO_LANG=zh bash /usr/local/lib/sysinfo/sysinfo_banner.sh 2>&1 | strip_ansi)
assert_contains "$BANNER_ZH" '系统实时监控' "login banner zh title"
assert_contains "$BANNER_ZH" '^核心信息$' "login banner reuses section style"
assert_contains "$BANNER_ZH" '^  CPU 型号  : ' "login banner aligns CJK CPU label"
assert_contains "$BANNER_ZH" '^  IPv4 地址 : ' "login banner aligns CJK IPv4 label"
assert_contains "$BANNER_ZH" '^  下载速度  : .*上传速度  : ' "login banner aligns CJK network row"

THROTTLE_DIAG=$(bash /opt/sysinfo-cli/scripts/test_throttle.sh 2>&1)
assert_contains "$THROTTLE_DIAG" 'Diagnostic Complete' "throttle diagnostic completes"
assert_contains "$THROTTLE_DIAG" 'Throttle enabled: true' "throttle diagnostic sees enabled state"
assert_contains "$THROTTLE_DIAG" 'Throttle threshold: 95%' "throttle diagnostic sees threshold"
assert_contains "$THROTTLE_DIAG" 'Throttle rate: 10mbps' "throttle diagnostic sees rate"
assert_contains "$THROTTLE_DIAG" 'Traffic mode: both' "throttle diagnostic sees traffic mode"

cat > /etc/sysinfo-traffic.json <<'JSON'
{"start_time":1,"rx_bytes":524288000,"tx_bytes":524288000,"last_rx":1,"last_tx":1,"traffic_mode":"both","last_update":1}
JSON

RESET_OUT=$("$SYSINFO" --reset-traffic 2>&1)
assert_contains "$RESET_OUT" 'reset|Reset' "traffic reset command"

RESET_STATS=$(cat /etc/sysinfo-traffic.json)
assert_contains "$RESET_STATS" '"rx_bytes":0' "traffic reset clears rx"
assert_contains "$RESET_STATS" '"tx_bytes":0' "traffic reset clears tx"
assert_contains "$RESET_STATS" '"traffic_mode":"both"' "traffic reset preserves traffic mode"
assert_contains "$RESET_STATS" '"last_rx":[0-9]+' "traffic reset refreshes rx baseline"
assert_contains "$RESET_STATS" '"last_tx":[0-9]+' "traffic reset refreshes tx baseline"

POST_RESET=$("$SYSINFO" 2>&1 | strip_ansi)
assert_contains "$POST_RESET" 'Total( Traffic)?[[:space:]]*: 0 B' "dashboard total resets to zero"
assert_contains "$POST_RESET" 'Usage[[:space:]]*: .*0%' "dashboard usage resets to zero"
assert_contains "$POST_RESET" 'Throttle Status[[:space:]]*: .*Idle|Throttle Status[[:space:]]*: .*Failed|Throttle Status[[:space:]]*: .*Active' "dashboard throttle remains linked after reset"

cat > "$CONFIG" <<'YAML'
network:
  interface: ""
nat:
  enabled: true
  mappings: [48081-48089]
traffic:
  enabled: false
display:
  language: "en"
  show_nat: true
  show_traffic: true
  show_throttle: true
YAML

LEGACY_OUT=$("$SYSINFO" -c "$CONFIG" 2>&1)
assert_contains "$LEGACY_OUT" 'NAT configured: ranges=48081-48089;mappings=' "legacy NAT range compatibility"
assert_contains "$LEGACY_OUT" 'Traffic disabled' "traffic disabled clears runtime config"
[ ! -f /etc/sysinfo-traffic ] || fail "traffic runtime config should be removed when traffic.enabled=false"

LEGACY_DASHBOARD=$("$SYSINFO" 2>&1 | strip_ansi)
assert_contains "$LEGACY_DASHBOARD" 'NAT[[:space:]]*: Open: 48081-48089' "legacy NAT range display"
assert_contains "$LEGACY_DASHBOARD" 'Download[[:space:]]*: .*B/s' "speed display still works without traffic config"

echo "[REGRESSION PASS] smoke, display, NAT, speed, throttle, reset linkage"
