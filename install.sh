#!/bin/bash
GITHUB_RAW="https://raw.githubusercontent.com/jokerknight/sysinfo-cli/main"
LOCAL_SRC_DIR=""

LANG_CHOICE=""

# ============================================
# i18n helpers
# ============================================

detect_install_lang() {
    local input="${1:-}"
    case "$(echo "$input" | tr '[:upper:]' '[:lower:]')" in
        zh|zh-cn|cn|chinese) echo "zh" ;;
        en|en-us|english) echo "en" ;;
        *)
            local env_lang="${LC_ALL:-${LANG:-}}"
            case "$env_lang" in
                zh*|ZH*) echo "zh" ;;
                *) echo "en" ;;
            esac
            ;;
    esac
}

msg() {
    local key="$1"
    if [ "$INSTALL_LANG" = "zh" ]; then
        case "$key" in
            deps_check) echo "检查依赖中..." ;;
            deps_ok) echo "  ✓ 依赖已满足" ;;
            deps_installed) echo "  ✓ 依赖安装完成" ;;
            install_iproute2) echo "  安装 iproute2..." ;;
            install_yq) echo "  安装 yq..." ;;
            china_mirror) echo "检测到国内网络，使用镜像下载..." ;;
            cleanup) echo "清理旧安装..." ;;
            start_install) echo "开始安装..." ;;
            gen_config) echo "生成默认配置..." ;;
            done) echo "安装完成！" ;;
            use_local_core) echo "使用本地 src/sysinfo_core.sh..." ;;
            use_local_main) echo "使用本地 src/sysinfo.sh..." ;;
            use_local_banner) echo "使用本地 src/sysinfo_banner.sh..." ;;
            not_found) echo "错误：未找到 sysinfo.sh（$SCRIPT_DIR）" ;;
            *) echo "$key" ;;
        esac
    else
        case "$key" in
            deps_check) echo "Checking dependencies..." ;;
            deps_ok) echo "  ✓ All dependencies satisfied" ;;
            deps_installed) echo "  ✓ Dependencies installed" ;;
            install_iproute2) echo "  Installing iproute2..." ;;
            install_yq) echo "  Installing yq..." ;;
            china_mirror) echo "Detected China access, using mirror..." ;;
            cleanup) echo "Cleaning up old installation..." ;;
            start_install) echo "Starting installation..." ;;
            gen_config) echo "Generating default configuration..." ;;
            done) echo "Installation complete!" ;;
            use_local_core) echo "Using local src/sysinfo_core.sh..." ;;
            use_local_main) echo "Using local src/sysinfo.sh..." ;;
            use_local_banner) echo "Using local src/sysinfo_banner.sh..." ;;
            not_found) echo "Error: sysinfo.sh not found in $SCRIPT_DIR" ;;
            *) echo "$key" ;;
        esac
    fi
}

# ============================================
# Functions
# ============================================

# Detect if in China and use mirror
check_china() {
    if timeout 3 curl -s -I https://github.com &>/dev/null; then
        echo "false"
    else
        echo "true"
    fi
}

# Check and install dependencies
check_and_install_deps() {
    local missing_deps=()

    # Check for tc (Traffic Control)
    if ! command -v tc >/dev/null 2>&1; then
        missing_deps+=("iproute2")
    fi

    # Check for yq (YAML parser)
    if ! command -v yq >/dev/null 2>&1; then
        missing_deps+=("yq")
    fi

    # Install missing dependencies
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo ""
        msg deps_check

        # Update package list
        if [ -f /etc/debian_version ]; then
            sudo apt-get update -qq >/dev/null 2>&1
        fi

        # Install iproute2
        if [[ " ${missing_deps[*]} " =~ "iproute2" ]]; then
            msg install_iproute2
            sudo apt-get install -y iproute2 >/dev/null 2>&1
        fi

        # Install yq
        if [[ " ${missing_deps[*]} " =~ "yq" ]]; then
            msg install_yq
            local yq_url="https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64"
            sudo wget -q "$yq_url" -O /usr/local/bin/yq
            sudo chmod +x /usr/local/bin/yq
        fi

        msg deps_installed
        echo ""
    else
        msg deps_ok
        echo ""
    fi
}

# Print usage information
print_usage() {
    if [ "$INSTALL_LANG" = "zh" ]; then
        echo "用法："
        echo "  ./install.sh                 - 安装 sysinfo-cli（默认）"
        echo "  ./install.sh --lang zh|en    - 指定安装语言"
        echo "  ./install.sh --help          - 显示帮助"
        echo ""
        echo "安装后可使用 'sysinfo'："
        echo "  - 查看系统信息"
        echo "  - 重载配置：           sysinfo -r"
        echo "  - 编辑 YAML 配置：     sudo nano /etc/sysinfo/config.yaml"
        echo "  - 应用配置：           sysinfo -c config.yaml"
        echo ""
        echo "默认配置（安装时自动生成）："
        echo "  - 月流量上限：1T"
        echo "  - 每月重置日：1号"
        echo "  - 流量模式：both（上行+下行）"
        echo "  - 达到 95% 后按 10mbps 限速"
        echo ""
        echo "配置文件位置："
        echo "  /etc/sysinfo/config.yaml"
        echo ""
        echo "其他命令："
        echo "  sysinfo -h              - 查看帮助"
        echo "  sysinfo --reset-traffic - 重置流量统计"
    else
        echo "Usage:"
        echo "  ./install.sh                 - Install sysinfo-cli (default)"
        echo "  ./install.sh --lang zh|en    - Set installation language"
        echo "  ./install.sh --help          - Show help"
        echo ""
        echo "After installation, use 'sysinfo' to:"
        echo "  - View system info"
        echo "  - Reload configuration:      sysinfo -r"
        echo "  - Edit YAML config:          sudo nano /etc/sysinfo/config.yaml"
        echo "  - Apply configuration:       sysinfo -c config.yaml"
        echo ""
        echo "Default configuration (auto-generated on install):"
        echo "  - Monthly traffic limit: 1T"
        echo "  - Reset day: 1st of each month"
        echo "  - Traffic mode: both (upload + download)"
        echo "  - Throttle enabled at 95% with 10mbps limit"
        echo ""
        echo "Configuration file location:"
        echo "  /etc/sysinfo/config.yaml"
        echo ""
        echo "Other options:"
        echo "  sysinfo -h              - Show sysinfo help"
        echo "  sysinfo --reset-traffic - Reset traffic stats"
    fi
}

# ============================================
# Main Installation Process
# ============================================

SHOW_HELP="false"

# Parse arguments
while [ "$#" -gt 0 ]; do
    case "$1" in
        --help|-h|help)
            SHOW_HELP="true"
            ;;
        --uninstall)
            bash "$(dirname "${BASH_SOURCE[0]}")/uninstall.sh"
            exit 0
            ;;
        --lang)
            shift
            LANG_CHOICE="$1"
            ;;
        --lang=*)
            LANG_CHOICE="${1#*=}"
            ;;
    esac
    shift
done

INSTALL_LANG="$(detect_install_lang "$LANG_CHOICE")"

if [ "$SHOW_HELP" = "true" ]; then
    print_usage
    exit 0
fi

# Check and install dependencies
check_and_install_deps

# Check for China access and use mirror if needed
CHINA_ACCESS=$(check_china)
if [ "$CHINA_ACCESS" = "true" ]; then
    msg china_mirror
    GITHUB_RAW="https://gh.277177.xyz/$GITHUB_RAW"
fi

# Clean up old installation
msg cleanup

# Best-effort runtime cleanup: clear active tc/ifb throttling state from previous installs
if command -v tc >/dev/null 2>&1 && command -v ip >/dev/null 2>&1; then
    while read -r IFACE; do
        [ -n "$IFACE" ] || continue
        [ "$IFACE" = "lo" ] && continue
        sudo tc qdisc del dev "$IFACE" root >/dev/null 2>&1 || true
        sudo tc qdisc del dev "$IFACE" ingress >/dev/null 2>&1 || true
    done < <(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | cut -d@ -f1)

    sudo tc qdisc del dev ifb_sysinfo0 root >/dev/null 2>&1 || true
fi

sudo rm -f /var/tmp/sysinfo_throttle_state

sudo rm -f /etc/profile.d/sysinfo.sh /etc/profile.d/sysinfo-main.sh \
         /usr/local/bin/sysinfo /usr/local/bin/sysinfo-main \
         /etc/sysinfo-lang /etc/sysinfo-nat /etc/sysinfo-traffic /etc/sysinfo-traffic.json
sudo rm -f /var/tmp/sysinfo_net_stats_*

msg start_install

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LOCAL_SRC_DIR="$SCRIPT_DIR/src"

# Install sysinfo_core.sh
if [[ "${BASH_SOURCE[0]}" == /dev/fd/* ]]; then
    echo "Downloading sysinfo_core.sh from $GITHUB_RAW/src/sysinfo_core.sh..."
    sudo curl -sSL "$GITHUB_RAW/src/sysinfo_core.sh" -o /etc/profile.d/sysinfo_core.sh
elif [ -f "$LOCAL_SRC_DIR/sysinfo_core.sh" ]; then
    msg use_local_core
    sudo cp "$LOCAL_SRC_DIR/sysinfo_core.sh" /etc/profile.d/sysinfo_core.sh
else
    echo "Downloading sysinfo_core.sh from $GITHUB_RAW/src/sysinfo_core.sh..."
    sudo curl -sSL "$GITHUB_RAW/src/sysinfo_core.sh" -o /etc/profile.d/sysinfo_core.sh
fi
sudo chmod +x /etc/profile.d/sysinfo_core.sh

# Install sysinfo.sh (CLI tool only, not for profile.d)
if [[ "${BASH_SOURCE[0]}" == /dev/fd/* ]]; then
    echo "Downloading sysinfo.sh from $GITHUB_RAW/src/sysinfo.sh..."
    sudo curl -sSL "$GITHUB_RAW/src/sysinfo.sh" -o /usr/local/bin/sysinfo-cli.sh
elif [ -f "$LOCAL_SRC_DIR/sysinfo.sh" ]; then
    msg use_local_main
    sudo cp "$LOCAL_SRC_DIR/sysinfo.sh" /usr/local/bin/sysinfo-cli.sh
else
    echo "Downloading sysinfo.sh from $GITHUB_RAW/src/sysinfo.sh..."
    sudo curl -sSL "$GITHUB_RAW/src/sysinfo.sh" -o /usr/local/bin/sysinfo-cli.sh
fi
sudo chmod +x /usr/local/bin/sysinfo-cli.sh

# Install sysinfo_banner.sh (SSH login banner only)
if [[ "${BASH_SOURCE[0]}" == /dev/fd/* ]]; then
    echo "Downloading sysinfo_banner.sh from $GITHUB_RAW/src/sysinfo_banner.sh..."
    sudo curl -sSL "$GITHUB_RAW/src/sysinfo_banner.sh" -o /etc/profile.d/sysinfo-banner.sh
elif [ -f "$LOCAL_SRC_DIR/sysinfo_banner.sh" ]; then
    msg use_local_banner
    sudo cp "$LOCAL_SRC_DIR/sysinfo_banner.sh" /etc/profile.d/sysinfo-banner.sh
else
    echo "Downloading sysinfo_banner.sh from $GITHUB_RAW/src/sysinfo_banner.sh..."
    sudo curl -sSL "$GITHUB_RAW/src/sysinfo_banner.sh" -o /etc/profile.d/sysinfo-banner.sh
fi
sudo chmod +x /etc/profile.d/sysinfo-banner.sh 2>/dev/null

# Create /usr/local/bin/sysinfo wrapper. Keep a thin wrapper instead of
# duplicating CLI logic, so installed behavior stays aligned with sysinfo.sh.
sudo tee /usr/local/bin/sysinfo > /dev/null << 'CMD'
#!/bin/bash
exec /usr/local/bin/sysinfo-cli.sh "$@"
CMD
sudo chmod +x /usr/local/bin/sysinfo

# Persist language selection for runtime dashboard/help
echo "$INSTALL_LANG" | sudo tee /etc/sysinfo-lang >/dev/null

# Generate default YAML configuration
msg gen_config
sudo mkdir -p /etc/sysinfo

sudo tee /etc/sysinfo/config.yaml > /dev/null << 'EOF'
# SysInfo Configuration File
# Default configuration (auto-generated on install)

# Network Interface Configuration
network:
  # Interface to monitor (leave empty for auto-detection)
  interface: ""
  # Force throttle on gateway mode (ip_forward=1) - USE WITH CAUTION
  force_gateway_throttle: false

# NAT Port Mappings
nat:
  enabled: false
  # Port mappings: public-port:private-port
  mappings: []

# Traffic Limit Configuration
traffic:
  enabled: true
  # Monthly traffic limit: 1T, 500G, 100M, or UNLIMITED
  limit: "1T"
  # Day of month to reset traffic (1-31)
  reset_day: 1
  # Traffic mode: upload, download, or both
  mode: "both"

# Throttle Configuration (applied when traffic usage exceeds threshold)
throttle:
  enabled: true
  # Traffic percentage to trigger throttling (0-100)
  threshold: 95
  # Rate limit when throttled: 10mbps, 5mbps, 1mbps, etc. (minimum: 1mbps)
  rate: "10mbps"

# Display Configuration
display:
  # Refresh interval in seconds (1-60)
  refresh_interval: 1
  # Show traffic statistics
  show_traffic: true
  # Show NAT port mappings
  show_nat: true
  # Show throttle status
  show_throttle: true
EOF

echo ""
echo "============================================"
msg done
echo "============================================"
echo ""
if [ "$INSTALL_LANG" = "zh" ]; then
    echo "用法："
    echo "  sysinfo              - 实时监控（1 秒刷新）"
    echo "  sysinfo 5            - 实时监控（5 秒刷新）"
    echo ""
    echo "配置："
    echo "  重载配置：           sysinfo -r"
    echo "  编辑 YAML 配置：     sudo nano /etc/sysinfo/config.yaml"
    echo "  应用配置：           sysinfo -c /etc/sysinfo/config.yaml"
    echo ""
    echo "配置文件位置："
    echo "  /etc/sysinfo/config.yaml"
    echo ""
    echo "默认配置："
    echo "  - 月流量上限：1T"
    echo "  - 每月重置日：1号"
    echo "  - 流量模式：both（上行+下行）"
    echo "  - 达到 95% 后按 10mbps 限速"
    echo ""
    echo "其他命令："
    echo "  sysinfo -h              - 查看帮助"
    echo "  sysinfo --reset-traffic - 重置流量统计"
else
    echo "Usage:"
    echo "  sysinfo              - Real-time monitoring (1s refresh)"
    echo "  sysinfo 5            - Real-time monitoring (5s refresh)"
    echo ""
    echo "Configuration:"
    echo "  Reload config:      sysinfo -r"
    echo "  Edit YAML config:   sudo nano /etc/sysinfo/config.yaml"
    echo "  Apply config:      sysinfo -c /etc/sysinfo/config.yaml"
    echo ""
    echo "Configuration file location:"
    echo "  /etc/sysinfo/config.yaml"
    echo ""
    echo "Default configuration:"
    echo "  - Monthly traffic limit: 1T"
    echo "  - Reset day: 1st of each month"
    echo "  - Traffic mode: both (upload + download)"
    echo "  - Throttle enabled at 95% with 10mbps limit"
    echo ""
    echo "Other commands:"
    echo "  sysinfo -h           - Show help"
    echo "  sysinfo --reset-traffic - Reset traffic stats"
fi
echo ""
print_usage
