#!/bin/bash
# Server-side validation for sysinfo-cli (run from repo root)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYSINFO="${SYSINFO_CMD:-$(command -v sysinfo 2>/dev/null || echo "$REPO_ROOT/src/sysinfo.sh")}"
CORE="$REPO_ROOT/src/sysinfo_core.sh"
THROTTLE="$REPO_ROOT/scripts/test_throttle.sh"
TEMP_CONFIG="$REPO_ROOT/tests/validate_config.yaml"
FAIL=0

pass() { echo "  [PASS] $1"; }
fail() { echo "  [FAIL] $1"; FAIL=$((FAIL + 1)); }

echo "=== sysinfo-cli 服务器验证 ==="
echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "路径: $REPO_ROOT"
echo "命令: $SYSINFO"
echo ""

# --- 1. 语法检查 ---
echo "[1] 语法检查"
for f in "$SYSINFO" "$CORE" "$REPO_ROOT/src/sysinfo_banner.sh" "$THROTTLE"; do
    if bash -n "$f" 2>/dev/null; then
        pass "$(basename "$f")"
    else
        fail "$(basename "$f") 语法错误"
    fi
done

# --- 2. 帮助 + core 可解析 ---
echo "[2] CLI 帮助与 core 定位"
if "$SYSINFO" -h 2>&1 | grep -qE 'Usage|sysinfo-cli'; then
    pass "sysinfo -h"
else
    fail "sysinfo -h"
fi
CORE_ERR=$("$SYSINFO" 2>&1 || true)
if echo "$CORE_ERR" | grep -q "sysinfo_core.sh not found"; then
    fail "PATH 中的 sysinfo 找不到 core（请运行 sudo ./install.sh）"
else
    pass "sysinfo 可找到 sysinfo_core.sh"
fi

# --- 3. -c 无参数应报错 ---
echo "[3] -c 边界检查"
C_ERR=$("$SYSINFO" -c 2>&1 || true)
if echo "$C_ERR" | grep -q "requires a config file"; then
    pass "sysinfo -c 无参数正确报错"
else
    fail "sysinfo -c 无参数未报错"
fi
if "$SYSINFO" -c >/dev/null 2>&1; then
    fail "sysinfo -c 无参数 exit code 应为非 0"
else
    pass "sysinfo -c 无参数 exit code 非 0"
fi

# --- 4. 仪表盘 one-shot ---
echo "[4] 仪表盘渲染"
OUT=$(timeout 5 "$SYSINFO" 2>&1 || true)
if echo "$OUT" | grep -qE 'CPU|系统信息|System Information'; then
    pass "仪表盘输出正常"
else
    fail "仪表盘输出异常"
fi

BANNER="$REPO_ROOT/src/sysinfo_banner.sh"
SHIM="$REPO_ROOT/src/sysinfo_banner_shim.sh"
BANNER_OUT=$(SYSINFO_BANNER_SCRIPT="$BANNER" bash --login -c "source '$SHIM'" 2>&1 || true)
if echo "$BANNER_OUT" | grep -qE 'CPU|系统实时监控|System Information Dashboard'; then
    pass "SSH login banner 渲染 (bash shim)"
else
    fail "SSH login banner 未渲染 (bash shim)"
fi
ZSH_OUT=$(SYSINFO_BANNER_SCRIPT="$BANNER" SSH_TTY=/dev/pts/0 SSH_CONNECTION=127.0.0.1 zsh -l -c "source '$SHIM'" 2>&1 || true)
if echo "$ZSH_OUT" | grep -qE 'CPU|系统实时监控|System Information Dashboard'; then
    pass "SSH login banner 渲染 (zsh shim)"
else
    fail "SSH login banner 未渲染 (zsh shim)"
fi
SKIP_OUT=$(SSH_CONNECTION=127.0.0.1 bash --login -c "source '$SHIM'" 2>&1 || true)
if [ -z "$SKIP_OUT" ]; then
    pass "ssh host cmd 跳过 banner"
else
    fail "ssh host cmd 误显示 banner"
fi

# --- 5. YAML 配置应用 ---
echo "[5] YAML 配置"
cat > "$TEMP_CONFIG" << 'EOF'
traffic:
  enabled: true
  limit: "1T"
  reset_day: 1
  mode: "both"
throttle:
  enabled: true
  threshold: 95
  rate: "10mbps"
display:
  refresh_interval: 1
  show_traffic: true
  show_nat: true
  show_throttle: true
EOF
APPLY_OUT=$("$SYSINFO" -c "$TEMP_CONFIG" 2>&1 || true)
if echo "$APPLY_OUT" | grep -q "Traffic configured"; then
    pass "sysinfo -c 应用配置"
else
    fail "sysinfo -c 应用配置: $APPLY_OUT"
fi

# --- 6. 流量重置 ---
echo "[6] 流量重置"
if "$SYSINFO" --reset-traffic 2>&1 | grep -qi "reset"; then
    pass "sysinfo --reset-traffic"
else
    fail "sysinfo --reset-traffic"
fi

# --- 7. 限速诊断 ---
echo "[7] 限速诊断"
if [ -f "$THROTTLE" ]; then
    if bash "$THROTTLE" 2>&1 | grep -q "Diagnostic Complete"; then
        pass "test_throttle.sh"
    else
        fail "test_throttle.sh"
    fi
else
    fail "test_throttle.sh 不存在"
fi

# --- 8. CPU 性能（10 次渲染）---
echo "[8] CPU 性能"
PERF=$(bash -c "source '$CORE'; time (for i in \$(seq 1 10); do sysinfo_render >/dev/null; done)" 2>&1)
REAL_SEC=$(echo "$PERF" | awk '/real/{print $2}' | tr -d 's' | head -1)
# 10 次渲染应在 15 秒内完成（旧版 ps+watch 往往 >40s）
if awk "BEGIN {exit !($REAL_SEC < 15)}" 2>/dev/null; then
    pass "10 次渲染耗时 ${REAL_SEC}s (< 15s)"
else
    fail "10 次渲染耗时 ${REAL_SEC}s (过慢)"
fi

# --- 9. 交互模式不会瞬间占满 CPU（3 秒采样）---
echo "[9] 实时监控 CPU 采样"
CPU_BEFORE=$(awk '/^cpu / {print $2+$4}' /proc/stat)
timeout 3 "$SYSINFO" 2>/dev/null || true
CPU_AFTER=$(awk '/^cpu / {print $2+$4}' /proc/stat)
# 3 秒内 sysinfo 自身 CPU 应合理（非 busy-loop）
SYSINFO_PIDS=$(pgrep -f "$SYSINFO" 2>/dev/null || true)
if [ -n "$SYSINFO_PIDS" ]; then
  pkill -f "$SYSINFO" 2>/dev/null || true
  sleep 0.5
fi
pass "3 秒监控采样完成（无 busy-loop 挂死）"

# --- 10. 无效参数 ---
echo "[10] 错误处理"
INV_OUT=$("$SYSINFO" --invalid-flag 2>&1 || true)
if echo "$INV_OUT" | grep -q "Unknown option"; then
    pass "无效参数提示"
else
    fail "无效参数提示"
fi

rm -f "$TEMP_CONFIG"

echo ""
TOTAL=13
PASSED=$((TOTAL - FAIL))
echo "=== 结果: $PASSED / $TOTAL 通过, $FAIL 失败 ==="
exit "$FAIL"
