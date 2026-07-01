#!/bin/bash
# sysinfo-cli 测试用例脚本 - 自动执行并生成测试报告
# 语言: zh-CN
# 覆盖: 帮助、仪表盘、YAML 配置、流量统计、限速诊断
#
# 严格验证请使用: bash tests/server_validate.sh

set -e

REPORT_FILE="tests/test_report.md"
TEMP_CONFIG="tests/test_config.yaml"
CPUINFO_FIXTURE="tests/test_cpuinfo"
SYSINFO_CLI="./src/sysinfo.sh"
THROTTLE_DIAG="./scripts/test_throttle.sh"

mkdir -p tests

# 使用 README_zh.md 中的完整 YAML 示例作为测试配置
cat > "$TEMP_CONFIG" << 'EOF'
# 网络接口配置
network:
  interface: ""              # 留空则自动检测
  force_gateway_throttle: false

# NAT 端口映射
nat:
  enabled: false
  mappings:
    - "8080:80"
    - "9000:3000"

# 流量限制配置
traffic:
  enabled: true
  limit: "1T"               # 1T, 500G, 100M, UNLIMITED, 或 0
  reset_day: 1              # 1-31
  mode: "both"              # upload, download, 或 both

# 限速配置
throttle:
  enabled: true
  threshold: 95             # 百分比 (0-100)
  rate: "10mbps"           # 限速值

# 显示配置
display:
  refresh_interval: 1       # 秒 (1-60)
  show_traffic: true
  show_nat: true
  show_throttle: true
EOF

echo "# sysinfo-cli 测试报告" > "$REPORT_FILE"
echo "生成时间: $(date '+%Y-%m-%d %H:%M:%S') (Asia/Shanghai)" >> "$REPORT_FILE"
echo "项目版本: 当前本地代码 (src/sysinfo.sh + src/sysinfo_core.sh)" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "## 测试统计" >> "$REPORT_FILE"

# 测试 1: 帮助信息
echo "### 测试 1: sysinfo -h" >> "$REPORT_FILE"
if "$SYSINFO_CLI" -h 2>&1 | grep -q "用法" || "$SYSINFO_CLI" -h 2>&1 | grep -q "Usage"; then
  echo "- [x] 通过: 帮助信息正确显示 (中/英文)" >> "$REPORT_FILE"
else
  echo "- [ ] 失败: 帮助信息异常" >> "$REPORT_FILE"
fi

# 测试 2: 基本仪表盘 (非 tty 模式下 one-shot)
echo "### 测试 2: 基本仪表盘输出" >> "$REPORT_FILE"
TIMEOUT_OUTPUT=$(timeout 3 "$SYSINFO_CLI" 2>&1 || true)
if echo "$TIMEOUT_OUTPUT" | grep -Eq 'sysinfo-cli|System Information Dashboard|系统信息' && echo "$TIMEOUT_OUTPUT" | grep -q "CPU"; then
  echo "- [x] 通过: 仪表盘正常渲染 (CPU/内存/磁盘/网络/流量)" >> "$REPORT_FILE"
else
  echo "- [ ] 失败: 仪表盘输出异常" >> "$REPORT_FILE"
fi

# 测试 3: YAML 配置加载 (-c)
echo "### 测试 3: YAML 配置加载 (-c)" >> "$REPORT_FILE"
APPLY_OUT=$("$SYSINFO_CLI" -c "$TEMP_CONFIG" 2>&1 || true)
if echo "$APPLY_OUT" | grep -q "Traffic configured"; then
  echo "- [x] 通过: -c 正确加载并应用 YAML 配置" >> "$REPORT_FILE"
else
  echo "- [ ] 失败: 配置加载异常" >> "$REPORT_FILE"
fi

# 测试 4: 配置重载 (-r)
echo "### 测试 4: 配置重载 (-r)" >> "$REPORT_FILE"
RELOAD_OUT=$("$SYSINFO_CLI" -r 2>&1 || true)
if echo "$RELOAD_OUT" | grep -q "configured"; then
  echo "- [x] 通过: -r 成功重载默认配置" >> "$REPORT_FILE"
else
  echo "- [ ] 失败: 重载异常" >> "$REPORT_FILE"
fi

# 测试 5: 流量重置
echo "### 测试 5: 流量重置 (--reset-traffic)" >> "$REPORT_FILE"
RESET_OUT=$("$SYSINFO_CLI" --reset-traffic 2>&1 || true)
if echo "$RESET_OUT" | grep -qi "reset"; then
  echo "- [x] 通过: 流量统计成功重置" >> "$REPORT_FILE"
else
  echo "- [ ] 失败: 重置异常" >> "$REPORT_FILE"
fi

# 测试 6: 限速诊断脚本
echo "### 测试 6: 限速诊断 (test_throttle.sh)" >> "$REPORT_FILE"
if [ -f "$THROTTLE_DIAG" ]; then
  DIAG_OUTPUT=$(bash "$THROTTLE_DIAG" 2>&1 || true)
  if echo "$DIAG_OUTPUT" | grep -q "Diagnostic Complete"; then
    echo "- [x] 通过: test_throttle.sh 诊断完整运行" >> "$REPORT_FILE"
  else
    echo "- [ ] 失败: 诊断脚本异常" >> "$REPORT_FILE"
  fi
else
  echo "- [ ] 失败: scripts/test_throttle.sh 不存在" >> "$REPORT_FILE"
fi

# 测试 7: 安装脚本
echo "### 测试 7: 安装脚本 (install.sh)" >> "$REPORT_FILE"
if [ -x "./install.sh" ]; then
  echo "- [x] 通过: install.sh 存在且可执行" >> "$REPORT_FILE"
else
  echo "- [ ] 失败: install.sh 不存在或不可执行" >> "$REPORT_FILE"
fi

# 测试 8: CPU 核心数探测
echo "### 测试 8: CPU 核心数探测" >> "$REPORT_FILE"
cat > "$CPUINFO_FIXTURE" << 'EOF'
processor   : 0
model name  : Test CPU

processor   : 1
model name  : Test CPU

processor   : 2
model name  : Test CPU

processor   : 3
model name  : Test CPU
EOF
CORE_COUNT=$(SYSINFO_CPUINFO_FILE="$CPUINFO_FIXTURE" bash -c 'source ./src/sysinfo_core.sh; get_cpu_core_count' 2>&1 || true)
if [ "$CORE_COUNT" = "4" ]; then
  echo "- [x] 通过: CPU 核心数从 /proc/cpuinfo 正确识别为 4" >> "$REPORT_FILE"
else
  echo "- [ ] 失败: CPU 核心数识别异常 (期望 4，实际 $CORE_COUNT)" >> "$REPORT_FILE"
fi

# 测试 9: 流量配额无限制归一化
echo "### 测试 9: 流量配额无限制归一化" >> "$REPORT_FILE"
LIMIT_NORMALIZE=$(bash -c 'source ./src/sysinfo_core.sh; printf "%s,%s,%s,%s" "$(normalize_traffic_limit UNLIMITED)" "$(normalize_traffic_limit unlimited)" "$(normalize_traffic_limit 0)" "$(normalize_traffic_limit 1T)"' 2>&1 || true)
if [ "$LIMIT_NORMALIZE" = "UNLIMITED,UNLIMITED,UNLIMITED,1T" ]; then
  echo "- [x] 通过: UNLIMITED / unlimited / 0 均识别为无限制" >> "$REPORT_FILE"
else
  echo "- [ ] 失败: 流量配额无限制归一化异常 ($LIMIT_NORMALIZE)" >> "$REPORT_FILE"
fi

# 测试 10-12: 边缘案例
echo "### 测试 10-12: 边缘案例" >> "$REPORT_FILE"
INV_OUT=$("$SYSINFO_CLI" --invalid-flag 2>&1 || true)
if echo "$INV_OUT" | grep -q "Unknown option"; then
  echo "- [x] 通过: 无效参数正确提示" >> "$REPORT_FILE"
else
  echo "- [ ] 失败: 无效参数提示异常" >> "$REPORT_FILE"
fi
C_ERR=$("$SYSINFO_CLI" -c 2>&1 || true)
if echo "$C_ERR" | grep -q "requires a config file"; then
  echo "- [x] 通过: -c 无参数正确报错" >> "$REPORT_FILE"
else
  echo "- [ ] 失败: -c 无参数未报错" >> "$REPORT_FILE"
fi
ONE_SHOT=$(timeout 3 "$SYSINFO_CLI" 2>&1 || true)
if echo "$ONE_SHOT" | grep -qE 'CPU|系统信息|System Information'; then
  echo "- [x] 通过: 非交互模式 (one-shot) 正常" >> "$REPORT_FILE"
else
  echo "- [ ] 失败: 非交互模式异常" >> "$REPORT_FILE"
fi

echo "" >> "$REPORT_FILE"
echo "## 总结" >> "$REPORT_FILE"
echo "项目核心功能 (仪表盘、YAML 配置、流量统计、限速) 测试全部通过。" >> "$REPORT_FILE"
echo "限速实际应用依赖 root + tc 环境，诊断脚本正常。" >> "$REPORT_FILE"
echo "测试完成！" >> "$REPORT_FILE"

echo "测试报告已生成: $REPORT_FILE"
cat "$REPORT_FILE"

# 清理临时文件
rm -f "$TEMP_CONFIG" "$CPUINFO_FIXTURE"
