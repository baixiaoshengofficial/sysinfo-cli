#!/bin/bash

# Throttle Testing Script
# This script helps diagnose throttle/limit issues

echo "=== sysinfo-cli Throttle Diagnostic Tool ==="
echo ""

# 1. Check if tc is available
echo "[1] Checking tc (Traffic Control)..."
if command -v tc >/dev/null 2>&1; then
    echo "✓ tc is installed: $(tc --version 2>/dev/null || echo 'unknown version')"
else
    echo "✗ tc is NOT installed. Install iproute2 (Debian/Ubuntu/Alpine/Arch) or iproute (RHEL/Fedora)."
fi
echo ""

# 2. Check gateway mode
echo "[2] Checking gateway mode (ip_forward)..."
ip_forward=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo "0")
if [ "$ip_forward" = "1" ]; then
    echo "⚠ Gateway mode is ENABLED (ip_forward=1)"
    echo "  Throttling will be skipped by default for safety."
    echo "  To force throttling, set network.force_gateway_throttle: true in YAML config."
else
    echo "✓ Gateway mode is disabled (safe to throttle)"
fi
echo ""

# 3. Check default network interface
echo "[3] Checking network interfaces..."
default_iface=$(ip route get 1.1.1.1 2>/dev/null | awk '/dev/ {for(i=1;i<=NF;i++) if ($i == "dev") {print $(i+1); exit}}')
if [ -n "$default_iface" ]; then
    echo "✓ Default interface: $default_iface"
else
    echo "⚠ Could not determine default interface"
fi
echo ""

# 4. List all network interfaces
echo "All network interfaces:"
ip -o link show 2>/dev/null | awk -F': ' '{print "  - " $2}' | head -10
echo ""

# 5. Check current qdisc status
echo "[4] Checking current tc qdisc status..."
for iface in $(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | cut -d@ -f1 | head -5); do
    qdisc_output=$(tc qdisc show dev "$iface" 2>/dev/null)
    if [ -n "$qdisc_output" ]; then
        echo "  Interface $iface:"
        echo "$qdisc_output" | sed 's/^/    /'
    fi
done
echo ""

# 6. Check sysinfo throttle configuration
echo "[5] Checking sysinfo throttle configuration..."
if [ -f /etc/sysinfo-traffic ]; then
    echo "Config file exists: /etc/sysinfo-traffic"
    throttle_enabled=$(grep -o '"throttle_enabled":[^,}]*' /etc/sysinfo-traffic 2>/dev/null | cut -d: -f2 | tr -d ' "')
    throttle_threshold=$(grep -o '"throttle_threshold":[0-9]*' /etc/sysinfo-traffic 2>/dev/null | grep -o '[0-9]*')
    throttle_rate=$(grep -o '"throttle_rate":"[^"]*"' /etc/sysinfo-traffic 2>/dev/null | cut -d'"' -f4)
    traffic_mode=$(grep -o '"traffic_mode":"[^"]*"' /etc/sysinfo-traffic 2>/dev/null | cut -d'"' -f4)
    force_throttle=$(grep -o '"force_throttle":[^,}]*' /etc/sysinfo-traffic 2>/dev/null | cut -d: -f2 | tr -d ' "')

    echo "  Throttle enabled: ${throttle_enabled:-false}"
    echo "  Throttle threshold: ${throttle_threshold:-95}%"
    echo "  Throttle rate: ${throttle_rate:-1mbps}"
    echo "  Traffic mode: ${traffic_mode:-both}"
    echo "  Force throttle: ${force_throttle:-false}"
else
    echo "⚠ Config file not found: /etc/sysinfo-traffic"
    echo "  Run 'sysinfo -r' after editing /etc/sysinfo/config.yaml"
fi
echo ""

# 7. Check IFB device status
echo "[6] Checking IFB device (for download throttling)..."
SYSINFO_IFB_DEV="ifb_sysinfo0"
if ip link show dev "$SYSINFO_IFB_DEV" >/dev/null 2>&1; then
    echo "✓ IFB device exists: $SYSINFO_IFB_DEV"
    ifb_qdisc=$(tc qdisc show dev "$SYSINFO_IFB_DEV" 2>/dev/null)
    if [ -n "$ifb_qdisc" ]; then
        echo "  IFB qdisc:"
        echo "$ifb_qdisc" | sed 's/^/    /'
    else
        echo "  No qdisc configured on IFB"
    fi
else
    echo "⚠ IFB device not found: $SYSINFO_IFB_DEV"
fi
echo ""

echo "=== Diagnostic Complete ==="
echo ""
echo "Recommendations:"
echo "1. If tc is not installed: iproute2 (apt/apk/pacman) or iproute (dnf/yum)"
echo "2. If gateway mode is enabled, set network.force_gateway_throttle: true"
echo "3. Check that the correct network interface is being throttled"
echo "4. For iperf3 testing, ensure you're testing the correct direction:"
echo "   - Upload test: iperf3 -c server (from client)"
echo "   - Download test: iperf3 -s (on server)"
echo ""
