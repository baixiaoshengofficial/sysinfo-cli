#!/bin/bash
GITHUB_RAW="https://raw.githubusercontent.com/baixiaoshengofficial/sysinfo-cli/main"
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
            install_iproute2) echo "  安装 iproute（tc/ip）..." ;;
            install_yq) echo "  安装 yq..." ;;
            install_download_tool) echo "  安装 curl/wget..." ;;
            china_mirror) echo "检测到国内网络，使用镜像下载..." ;;
            cleanup) echo "清理旧安装..." ;;
            start_install) echo "开始安装..." ;;
            gen_config) echo "生成默认配置..." ;;
            done) echo "安装完成！" ;;
            use_local_core) echo "使用本地 src/sysinfo_core.sh..." ;;
            use_local_main) echo "使用本地 src/sysinfo.sh..." ;;
            use_local_banner) echo "使用本地 src/sysinfo_banner.sh..." ;;
            use_local_shim) echo "使用本地 src/sysinfo_banner_shim.sh..." ;;
            apply_config) echo "应用配置..." ;;
            apply_config_ok) echo "  ✓ 配置已应用" ;;
            config_kept) echo "  ✓ 已保留现有配置 /etc/sysinfo/config.yaml (如需重置: --overwrite-config)" ;;
            config_overwritten) echo "  ✓ 已用模板覆盖配置 (旧配置已备份为 config.yaml.bak.*)" ;;
            reinstall_hint) echo "更新时请重新执行: sudo ./install.sh" ;;
            *) echo "$key" ;;
        esac
    else
        case "$key" in
            deps_check) echo "Checking dependencies..." ;;
            deps_ok) echo "  ✓ All dependencies satisfied" ;;
            deps_installed) echo "  ✓ Dependencies installed" ;;
            install_iproute2) echo "  Installing iproute (tc/ip)..." ;;
            install_yq) echo "  Installing yq..." ;;
            install_download_tool) echo "  Installing curl/wget..." ;;
            china_mirror) echo "Detected China access, using mirror..." ;;
            cleanup) echo "Cleaning up old installation..." ;;
            start_install) echo "Starting installation..." ;;
            gen_config) echo "Generating default configuration..." ;;
            done) echo "Installation complete!" ;;
            use_local_core) echo "Using local src/sysinfo_core.sh..." ;;
            use_local_main) echo "Using local src/sysinfo.sh..." ;;
            use_local_banner) echo "Using local src/sysinfo_banner.sh..." ;;
            use_local_shim) echo "Using local src/sysinfo_banner_shim.sh..." ;;
            apply_config) echo "Applying configuration..." ;;
            apply_config_ok) echo "  ✓ Configuration applied" ;;
            config_kept) echo "  ✓ Kept existing /etc/sysinfo/config.yaml (reset with --overwrite-config)" ;;
            config_overwritten) echo "  ✓ Config overwritten from template (old one backed up as config.yaml.bak.*)" ;;
            reinstall_hint) echo "To update, re-run: sudo ./install.sh" ;;
            not_found) echo "Error: sysinfo.sh not found in $SCRIPT_DIR" ;;
            *) echo "$key" ;;
        esac
    fi
}

# ============================================
# Functions
# ============================================

run_privileged() {
    if [ "$EUID" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

# Detect if in China and use mirror
check_china() {
    if timeout 3 curl -s -I https://github.com &>/dev/null; then
        echo "false"
    else
        echo "true"
    fi
}

# Linux-only (Debian/Ubuntu/RHEL/Fedora/Alpine/Arch/openSUSE/…). macOS is not supported.
require_linux() {
    if [ "$(uname -s 2>/dev/null)" != "Linux" ]; then
        if [ "$INSTALL_LANG" = "zh" ]; then
            echo "错误：sysinfo-cli 仅支持 Linux（不支持 macOS）。"
        else
            echo "Error: sysinfo-cli supports Linux only (macOS is not supported)."
        fi
        exit 1
    fi
}

# apt | dnf | yum | zypper | apk | pacman | emerge | unknown
detect_pkg_manager() {
    if command -v apt-get >/dev/null 2>&1; then
        echo "apt"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    elif command -v yum >/dev/null 2>&1; then
        echo "yum"
    elif command -v zypper >/dev/null 2>&1; then
        echo "zypper"
    elif command -v apk >/dev/null 2>&1; then
        echo "apk"
    elif command -v pacman >/dev/null 2>&1; then
        echo "pacman"
    elif command -v emerge >/dev/null 2>&1; then
        echo "emerge"
    else
        echo "unknown"
    fi
}

# RHEL/Fedora split tc into iproute-tc; others use iproute2.
iproute_pkg_name() {
    case "$(detect_pkg_manager)" in
        dnf|yum) echo "iproute iproute-tc" ;;
        emerge)  echo "net-misc/iproute2" ;;
        *)       echo "iproute2" ;;
    esac
}

install_iproute_pkgs() {
    case "$(detect_pkg_manager)" in
        dnf|yum) pkg_install iproute iproute-tc ;;
        emerge)  pkg_install net-misc/iproute2 ;;
        *)       pkg_install iproute2 ;;
    esac
}

pkg_update_index() {
    local pm
    pm=$(detect_pkg_manager)
    case "$pm" in
        apt)    run_privileged apt-get update -qq >/dev/null 2>&1 ;;
        dnf)    run_privileged dnf makecache -q >/dev/null 2>&1 || true ;;
        yum)    run_privileged yum makecache -q >/dev/null 2>&1 || true ;;
        zypper) run_privileged zypper --non-interactive refresh -q >/dev/null 2>&1 || true ;;
        apk)    run_privileged apk update -q >/dev/null 2>&1 || true ;;
        pacman) run_privileged pacman -Sy --noconfirm >/dev/null 2>&1 ;;
        emerge) ;;
        *) return 1 ;;
    esac
}

# Install one or more packages via the detected package manager.
pkg_install() {
    local pm pkg
    pm=$(detect_pkg_manager)
    if [ "$pm" = "unknown" ]; then
        if [ "$INSTALL_LANG" = "zh" ]; then
            echo "错误：未找到支持的包管理器（apt/dnf/yum/zypper/apk/pacman）。"
            echo "请手动安装：$(iproute_pkg_name)（提供 tc、ip 命令）"
        else
            echo "Error: no supported package manager found (apt/dnf/yum/zypper/apk/pacman)."
            echo "Install manually: $(iproute_pkg_name) (provides tc, ip)"
        fi
        return 1
    fi

    pkg_update_index || true

    for pkg in "$@"; do
        case "$pm" in
            apt)    run_privileged apt-get install -y "$pkg" >/dev/null 2>&1 ;;
            dnf)    run_privileged dnf install -y "$pkg" >/dev/null 2>&1 ;;
            yum)    run_privileged yum install -y "$pkg" >/dev/null 2>&1 ;;
            zypper) run_privileged zypper --non-interactive install -y "$pkg" >/dev/null 2>&1 ;;
            apk)    run_privileged apk add --no-cache "$pkg" >/dev/null 2>&1 ;;
            pacman) run_privileged pacman -S --noconfirm --needed "$pkg" >/dev/null 2>&1 ;;
            emerge) run_privileged emerge -q "$pkg" >/dev/null 2>&1 ;;
        esac || return 1
    done
}

# Download a URL to dest (curl or wget).
download_file() {
    local url="$1" dest="$2"
    if command -v curl >/dev/null 2>&1; then
        run_privileged curl -fsSL "$url" -o "$dest"
    elif command -v wget >/dev/null 2>&1; then
        run_privileged wget -q "$url" -O "$dest"
    else
        msg install_download_tool
        pkg_install curl wget || pkg_install curl || pkg_install wget || return 1
        if command -v curl >/dev/null 2>&1; then
            run_privileged curl -fsSL "$url" -o "$dest"
        else
            run_privileged wget -q "$url" -O "$dest"
        fi
    fi
}

# Map uname -m to mikefarah/yq release asset suffix.
detect_yq_asset() {
    case "$(uname -m 2>/dev/null)" in
        x86_64|amd64)   echo "yq_linux_amd64" ;;
        aarch64|arm64)  echo "yq_linux_arm64" ;;
        armv7l|armv6l|armhf|arm) echo "yq_linux_arm" ;;
        i686|i386)      echo "yq_linux_386" ;;
        *)
            echo "unsupported"
            return 1
            ;;
    esac
}

# Install mikefarah yq for the current CPU architecture.
install_yq_binary() {
    local asset url
    asset=$(detect_yq_asset) || {
        echo "Error: unsupported CPU architecture for yq: $(uname -m)"
        return 1
    }
    url="https://github.com/mikefarah/yq/releases/latest/download/${asset}"
    msg install_yq
    echo "  → ${asset}"
    run_privileged rm -f /usr/local/bin/yq
    download_file "$url" /usr/local/bin/yq || return 1
    run_privileged chmod +x /usr/local/bin/yq
    if ! /usr/local/bin/yq --version 2>/dev/null | grep -qi mikefarah; then
        echo "Error: yq install failed (wrong binary or network issue)"
        return 1
    fi
}

# Check and install dependencies
check_and_install_deps() {
    local missing_deps=()

    # Check for tc (Traffic Control)
    if ! command -v tc >/dev/null 2>&1; then
        missing_deps+=("iproute2")
    fi

    # yq must be mikefarah build AND runnable on this CPU (not wrong-arch amd64 on ARM).
    if ! /usr/local/bin/yq --version 2>/dev/null | grep -qi mikefarah; then
        missing_deps+=("yq")
    fi

    # curl/wget for remote install and yq download
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        missing_deps+=("download")
    fi

    # Install missing dependencies
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo ""
        msg deps_check

        # curl/wget
        if [[ " ${missing_deps[*]} " =~ "download" ]]; then
            msg install_download_tool
            pkg_install curl wget || pkg_install curl || pkg_install wget || exit 1
        fi

        # Install iproute2 / iproute (provides tc, ip)
        if [[ " ${missing_deps[*]} " =~ "iproute2" ]]; then
            msg install_iproute2
            echo "  → $(iproute_pkg_name) ($(detect_pkg_manager))"
            install_iproute_pkgs || exit 1
        fi

        # Install mikefarah yq to /usr/local/bin (overrides incompatible apt python-yq).
        if [[ " ${missing_deps[*]} " =~ "yq" ]]; then
            install_yq_binary || exit 1
        fi

        msg deps_installed
        echo ""
    else
        msg deps_ok
        echo ""
    fi
}

# True when install.sh is piped (curl | bash) or not run from a full repo checkout.
is_remote_install() {
    case "${BASH_SOURCE[0]:-}" in
        /dev/fd/*|/dev/stdin|bash|"") return 0 ;;
    esac
    [ ! -f "$SCRIPT_DIR/config.yaml.example" ]
}

# Copy or download config.yaml.example to a destination path.
install_config_template() {
    local dest="$1"
    if [ -f "$SCRIPT_DIR/config.yaml.example" ]; then
        run_privileged cp "$SCRIPT_DIR/config.yaml.example" "$dest"
    else
        download_file "$GITHUB_RAW/config.yaml.example" "$dest"
    fi
}

# Hook login banner for zsh (skip when zsh is not installed).
install_zsh_banner_hook() {
  local zprofile="/etc/zsh/zprofile"
  command -v zsh >/dev/null 2>&1 || return 0
  run_privileged mkdir -p /etc/zsh
  if ! run_privileged grep -qF "$ZPROFILE_MARK" "$zprofile" 2>/dev/null; then
      run_privileged tee -a "$zprofile" >/dev/null <<'EOF'

# sysinfo-cli banner
[ -r /etc/profile.d/sysinfo-banner.sh ] && . /etc/profile.d/sysinfo-banner.sh
EOF
  fi
}

# Print usage information
print_usage() {
    if [ "$INSTALL_LANG" = "zh" ]; then
        echo "用法："
        echo "  ./install.sh                 - 安装 sysinfo-cli（默认，保留已有配置）"
        echo "  ./install.sh --lang zh|en    - 指定安装语言"
        echo "  ./install.sh --overwrite-config - 用模板覆盖配置（自动备份旧配置）"
        echo "  ./install.sh --help          - 显示帮助"
        echo ""
        echo "支持 Linux：Debian/Ubuntu、RHEL/Fedora、Alpine、Arch、openSUSE 等（不支持 macOS）"
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
        echo ""
        msg reinstall_hint
    else
        echo "Usage:"
        echo "  ./install.sh                 - Install sysinfo-cli (default, keeps existing config)"
        echo "  ./install.sh --lang zh|en    - Set installation language"
        echo "  ./install.sh --overwrite-config - Overwrite config from template (old one backed up)"
        echo "  ./install.sh --help          - Show help"
        echo ""
        echo "Linux supported: Debian/Ubuntu, RHEL/Fedora, Alpine, Arch, openSUSE, etc. (not macOS)"
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
        echo ""
        msg reinstall_hint
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
        --overwrite-config|--reset-config)
            OVERWRITE_CONFIG="true"
            ;;
    esac
    shift
done

INSTALL_LANG="$(detect_install_lang "$LANG_CHOICE")"

if [ "$SHOW_HELP" = "true" ]; then
    print_usage
    exit 0
fi

require_linux

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
        run_privileged tc qdisc del dev "$IFACE" root >/dev/null 2>&1 || true
        run_privileged tc qdisc del dev "$IFACE" ingress >/dev/null 2>&1 || true
    done < <(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | cut -d@ -f1)

    run_privileged tc qdisc del dev ifb_sysinfo0 root >/dev/null 2>&1 || true
fi

run_privileged rm -f /var/tmp/sysinfo_throttle_state

run_privileged rm -f /etc/profile.d/sysinfo.sh /etc/profile.d/sysinfo-main.sh \
         /usr/local/bin/sysinfo /usr/local/bin/sysinfo-main
# Regenerate traffic JSON from YAML on install (preserve config.yaml if present).
run_privileged rm -f /etc/sysinfo-traffic /etc/sysinfo-traffic.json
run_privileged rm -f /var/tmp/sysinfo_net_stats_*

msg start_install

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LOCAL_SRC_DIR="$SCRIPT_DIR/src"

# Install sysinfo_core.sh
if is_remote_install; then
    echo "Downloading sysinfo_core.sh from $GITHUB_RAW/src/sysinfo_core.sh..."
    download_file "$GITHUB_RAW/src/sysinfo_core.sh" /etc/profile.d/sysinfo_core.sh
elif [ -f "$LOCAL_SRC_DIR/sysinfo_core.sh" ]; then
    msg use_local_core
    run_privileged cp "$LOCAL_SRC_DIR/sysinfo_core.sh" /etc/profile.d/sysinfo_core.sh
else
    echo "Downloading sysinfo_core.sh from $GITHUB_RAW/src/sysinfo_core.sh..."
    download_file "$GITHUB_RAW/src/sysinfo_core.sh" /etc/profile.d/sysinfo_core.sh
fi
run_privileged chmod +x /etc/profile.d/sysinfo_core.sh

# Also install core next to the CLI so /usr/local/bin/sysinfo always finds it
# even when /etc/profile.d/ is missing or incomplete.
run_privileged cp /etc/profile.d/sysinfo_core.sh /usr/local/bin/sysinfo_core.sh
run_privileged chmod +x /usr/local/bin/sysinfo_core.sh

# Install push-notification module (sourced on demand by the CLI).
if is_remote_install; then
    echo "Downloading sysinfo_notify.sh from $GITHUB_RAW/src/sysinfo_notify.sh..."
    download_file "$GITHUB_RAW/src/sysinfo_notify.sh" /usr/local/bin/sysinfo_notify.sh
elif [ -f "$LOCAL_SRC_DIR/sysinfo_notify.sh" ]; then
    run_privileged cp "$LOCAL_SRC_DIR/sysinfo_notify.sh" /usr/local/bin/sysinfo_notify.sh
else
    echo "Downloading sysinfo_notify.sh from $GITHUB_RAW/src/sysinfo_notify.sh..."
    download_file "$GITHUB_RAW/src/sysinfo_notify.sh" /usr/local/bin/sysinfo_notify.sh
fi
run_privileged chmod +x /usr/local/bin/sysinfo_notify.sh

# Install sysinfo.sh (CLI tool only, not for profile.d)
if is_remote_install; then
    echo "Downloading sysinfo.sh from $GITHUB_RAW/src/sysinfo.sh..."
    download_file "$GITHUB_RAW/src/sysinfo.sh" /usr/local/bin/sysinfo-cli.sh
elif [ -f "$LOCAL_SRC_DIR/sysinfo.sh" ]; then
    msg use_local_main
    run_privileged cp "$LOCAL_SRC_DIR/sysinfo.sh" /usr/local/bin/sysinfo-cli.sh
else
    echo "Downloading sysinfo.sh from $GITHUB_RAW/src/sysinfo.sh..."
    download_file "$GITHUB_RAW/src/sysinfo.sh" /usr/local/bin/sysinfo-cli.sh
fi
run_privileged chmod +x /usr/local/bin/sysinfo-cli.sh

# Install sysinfo_banner.sh (SSH login banner — bash renderer)
run_privileged mkdir -p /usr/local/lib/sysinfo
if is_remote_install; then
    echo "Downloading sysinfo_banner.sh from $GITHUB_RAW/src/sysinfo_banner.sh..."
    download_file "$GITHUB_RAW/src/sysinfo_banner.sh" /usr/local/lib/sysinfo/sysinfo_banner.sh
elif [ -f "$LOCAL_SRC_DIR/sysinfo_banner.sh" ]; then
    msg use_local_banner
    run_privileged cp "$LOCAL_SRC_DIR/sysinfo_banner.sh" /usr/local/lib/sysinfo/sysinfo_banner.sh
else
    echo "Downloading sysinfo_banner.sh from $GITHUB_RAW/src/sysinfo_banner.sh..."
    download_file "$GITHUB_RAW/src/sysinfo_banner.sh" /usr/local/lib/sysinfo/sysinfo_banner.sh
fi
run_privileged chmod +x /usr/local/lib/sysinfo/sysinfo_banner.sh

# POSIX shim for /etc/profile.d (bash) and /etc/zsh/zprofile (zsh login shells)
if is_remote_install; then
    download_file "$GITHUB_RAW/src/sysinfo_banner_shim.sh" /etc/profile.d/sysinfo-banner.sh
elif [ -f "$LOCAL_SRC_DIR/sysinfo_banner_shim.sh" ]; then
    msg use_local_shim
    run_privileged cp "$LOCAL_SRC_DIR/sysinfo_banner_shim.sh" /etc/profile.d/sysinfo-banner.sh
else
    download_file "$GITHUB_RAW/src/sysinfo_banner_shim.sh" /etc/profile.d/sysinfo-banner.sh
fi
run_privileged chmod +x /etc/profile.d/sysinfo-banner.sh 2>/dev/null

# zsh does not source /etc/profile.d — hook the same shim from zprofile (if zsh exists)
ZPROFILE_MARK="# sysinfo-cli banner"
install_zsh_banner_hook

# Create /usr/local/bin/sysinfo wrapper. Keep a thin wrapper instead of
# duplicating CLI logic, so installed behavior stays aligned with sysinfo.sh.
run_privileged tee /usr/local/bin/sysinfo > /dev/null << 'CMD'
#!/bin/bash
exec /usr/local/bin/sysinfo-cli.sh "$@"
CMD
run_privileged chmod +x /usr/local/bin/sysinfo

# Persist language selection for runtime dashboard/help (seed before apply)
echo "$INSTALL_LANG" | run_privileged tee /etc/sysinfo-lang >/dev/null

# Default YAML — by default keep existing file on reinstall so custom settings
# survive updates. Use --overwrite-config to reset it to the shipped template.
# On (re)generation, bake the chosen language into the config so it is the
# single source of truth (config.yaml's display.language drives /etc/sysinfo-lang).
msg gen_config
run_privileged mkdir -p /etc/sysinfo
if [ ! -f /etc/sysinfo/config.yaml ]; then
    install_config_template /etc/sysinfo/config.yaml
    run_privileged sed -i "s/^\(\s*language:\).*/\1 \"$INSTALL_LANG\"/" /etc/sysinfo/config.yaml
elif [ "${OVERWRITE_CONFIG:-false}" = "true" ]; then
    # Back up the old config before replacing it.
    run_privileged cp /etc/sysinfo/config.yaml "/etc/sysinfo/config.yaml.bak.$(date +%Y%m%d%H%M%S)"
    install_config_template /etc/sysinfo/config.yaml
    run_privileged sed -i "s/^\(\s*language:\).*/\1 \"$INSTALL_LANG\"/" /etc/sysinfo/config.yaml
    msg config_overwritten
else
    msg config_kept
fi

# Apply config (traffic + throttle JSON, NAT, etc.)
msg apply_config
if run_privileged /usr/local/bin/sysinfo -r >/dev/null 2>&1; then
    msg apply_config_ok
else
    echo "  (run: sysinfo -r)"
fi

echo ""
echo "============================================"
msg done
echo "============================================"
echo ""
print_usage
