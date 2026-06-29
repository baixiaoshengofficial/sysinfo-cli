#!/bin/bash

# ============================================
# sysinfo-cli - System Real-time Monitor
# Command Line Tool (CLI) - YAML Configuration
# ============================================

# Default paths (user config → system config; override with SYSINFO_CONFIG)
if [ -n "${SYSINFO_CONFIG:-}" ]; then
    DEFAULT_CONFIG_FILE="$SYSINFO_CONFIG"
elif [ -f "${HOME:-/nonexistent}/.config/sysinfo/config.yaml" ]; then
    DEFAULT_CONFIG_FILE="${HOME}/.config/sysinfo/config.yaml"
else
    DEFAULT_CONFIG_FILE="/etc/sysinfo/config.yaml"
fi
CONFIG_FILE=""
APPLY_CONFIG="false"
ACTION=""   # post-parse action: "" | "reset-traffic"

# ============================================
# Helper Functions
# ============================================

# Run command as root (directly if already root, otherwise with non-interactive sudo)
run_privileged() {
    if [ "$EUID" -eq 0 ]; then
        "$@"
    else
        sudo -n "$@"
    fi
}

# Check if yq is installed
check_yq() {
    if ! command -v yq >/dev/null 2>&1; then
        echo "Error: 'yq' is required for YAML configuration."
        echo ""
        echo "Install yq:"
        echo "  wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/local/bin/yq"
        echo "  chmod +x /usr/local/bin/yq"
        echo ""
        echo "Or continue with default configuration."
        return 1
    fi
    return 0
}

# Get a single config value from YAML.
# Tries the explicitly specified config file first, then the default path,
# finally returning the supplied default. Each candidate file is read in turn
# via _get_config_from_file so the lookup logic is not duplicated.
get_config() {
    local key="$1"
    local default="${2:-}"
    local value

    for _cfg in "$CONFIG_FILE" "$DEFAULT_CONFIG_FILE"; do
        [ -n "$_cfg" ] && [ -f "$_cfg" ] || continue
        value=$(_get_config_from_file "$key" "$_cfg")
        if [ -n "$value" ] && [ "$value" != "null" ]; then
            echo "$value"
            return 0
        fi
    done

    echo "$default"
}

# Resolve yq binary (prefer mikefarah build shipped by install.sh).
_yq_bin() {
    if [ -x /usr/local/bin/yq ]; then
        echo /usr/local/bin/yq
    elif command -v yq >/dev/null 2>&1; then
        command -v yq
    else
        return 1
    fi
}

# Read one YAML key from a file. Tries mikefarah v4/v3 and python-yq syntaxes.
_get_config_from_file() {
    local key="$1"
    local file="$2"
    local yq value=""
    yq=$(_yq_bin) || return 0

    value=$("$yq" eval ".$key" "$file" 2>/dev/null)
    if [ -z "$value" ] || [ "$value" = "null" ]; then
        value=$("$yq" ".$key" "$file" 2>/dev/null)
    fi
    if [ -z "$value" ] || [ "$value" = "null" ]; then
        value=$("$yq" r "$file" "$key" 2>/dev/null)
    fi
    if [ -z "$value" ] || [ "$value" = "null" ]; then
        value=$("$yq" -r ".$key" "$file" 2>/dev/null)
    fi
    [ "$value" = "null" ] && value=""
    printf '%s' "$value"
}

# Read a key only from the file being applied (-c / -r), never fall back to another path.
get_applied_config() {
    local key="$1"
    local default="${2:-}"
    local value
    value=$(_get_config_from_file "$key" "$CONFIG_FILE")
    if [ -n "$value" ] && [ "$value" != "null" ]; then
        echo "$value"
    else
        echo "$default"
    fi
}

is_applied_config_true() {
    local key="$1" value
    value=$(get_applied_config "$key" "false")
    [ "$value" = "true" ] || [ "$value" = "yes" ] || [ "$value" = "1" ]
}

# Get a YAML sequence as newline-separated items (empty if absent/empty list).
# Tries the explicit config file first, then the default path.
get_config_list() {
    local key="$1" value
    for _cfg in "$CONFIG_FILE" "$DEFAULT_CONFIG_FILE"; do
        [ -n "$_cfg" ] && [ -f "$_cfg" ] || continue
        check_yq 2>/dev/null || return 0
        value=$(yq eval ".${key}[]" "$_cfg" 2>/dev/null)
        if [ -n "$value" ] && [ "$value" != "null" ]; then
            printf '%s\n' "$value"
            return 0
        fi
    done
    return 0
}

# Normalize a language value to "zh", "en", or "" (auto/unknown).
normalize_lang() {
    local raw="${1:-}"
    raw="${raw#\"}"; raw="${raw%\"}"
    raw="${raw#\'}"; raw="${raw%\'}"
    case "$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr -d ' \t\r\n')" in
        zh|zh-cn|cn|chinese) echo "zh" ;;
        en|en-us|english) echo "en" ;;
        auto|"") echo "" ;;
        *) echo "" ;;
    esac
}

# Check if config boolean is true
is_config_true() {
    local key="$1"
    local value
    value=$(get_config "$key" "false")
    [ "$value" = "true" ] || [ "$value" = "yes" ] || [ "$value" = "1" ]
}

# ============================================
# Configuration Management
# ============================================

# Load configuration from YAML file
load_config() {
    local config_file="$1"

    if [ ! -f "$config_file" ]; then
        echo "Error: Configuration file not found: $config_file"
        return 1
    fi

    CONFIG_FILE="$config_file"
    return 0
}

# Apply configuration from YAML
apply_config() {
    if [ -z "$CONFIG_FILE" ] || [ ! -f "$CONFIG_FILE" ]; then
        return 1
    fi

    check_yq || return 1

    # Persist display language so dashboard/banner honor it across sessions.
    # "auto" (or unknown) removes the override and falls back to system locale.
    local cfg_lang norm_lang
    cfg_lang=$(get_applied_config "display.language" "auto")
    norm_lang=$(normalize_lang "$cfg_lang")
    if [ -n "$norm_lang" ]; then
        echo "$norm_lang" | run_privileged tee /etc/sysinfo-lang >/dev/null 2>&1
        echo "✓ Language set: $norm_lang (from $CONFIG_FILE)"
    else
        run_privileged rm -f /etc/sysinfo-lang
        echo "✓ Language: auto (from $CONFIG_FILE, follows system locale)"
        # Hint when the file clearly says zh/en but yq failed to parse it.
        if grep -qE '^[[:space:]]*language:[[:space:]]*"?zh' "$CONFIG_FILE" 2>/dev/null; then
            echo "  ⚠ File contains language: zh but yq read failed — check: yq --version; which yq"
            echo "    Expected mikefarah yq at /usr/local/bin/yq (re-run install.sh)"
        fi
    fi

    local nat_enabled
    nat_enabled=$(is_applied_config_true "nat.enabled" && echo "true" || echo "false")

    # Apply NAT mappings (record for display). Clear stale file when disabled
    # or empty so the dashboard never shows outdated mappings.
    if $nat_enabled; then
        local mappings
        mappings=$(yq eval '.nat.mappings[]' "$CONFIG_FILE" 2>/dev/null | tr '\n' ' ' | sed 's/ *$//')
        if [ -n "$mappings" ]; then
            echo "$mappings" | run_privileged tee /etc/sysinfo-nat >/dev/null 2>&1
            echo "✓ NAT configured: $mappings"
        else
            run_privileged rm -f /etc/sysinfo-nat
            echo "✓ NAT enabled (no mappings configured)"
        fi
    else
        run_privileged rm -f /etc/sysinfo-nat
    fi

    # Apply traffic configuration
    local traffic_enabled
    local traffic_limit
    local traffic_day
    local traffic_mode

    traffic_enabled=$(is_applied_config_true "traffic.enabled" && echo "true" || echo "false")
    traffic_limit=$(get_applied_config "traffic.limit" "1T")
    traffic_day=$(get_applied_config "traffic.reset_day" "1")
    traffic_mode=$(get_applied_config "traffic.mode" "both")

    if $traffic_enabled; then
        local traffic_json="{\"limit\":\"$traffic_limit\",\"reset_day\":$traffic_day,\"traffic_mode\":\"$traffic_mode\""
        local throttle_enabled
        throttle_enabled=$(is_applied_config_true "throttle.enabled" && echo "true" || echo "false")

        # Always persist threshold/rate/force so the dashboard shows the real
        # configured rule even when throttling is currently disabled.
        local throttle_threshold throttle_rate throttle_force
        throttle_threshold=$(get_applied_config "throttle.threshold" "95")
        throttle_rate=$(get_applied_config "throttle.rate" "10mbps")
        throttle_force=$(is_applied_config_true "network.force_gateway_throttle" && echo "true" || echo "false")
        traffic_json+=",\"throttle_enabled\":$throttle_enabled,\"throttle_threshold\":$throttle_threshold,\"throttle_rate\":\"$throttle_rate\",\"force_throttle\":$throttle_force"

        traffic_json+="}"

        echo "$traffic_json" | run_privileged tee /etc/sysinfo-traffic >/dev/null 2>&1
        echo "✓ Traffic configured: $traffic_limit (day $traffic_day, mode $traffic_mode)"
        if $throttle_enabled; then
            echo "  Throttle enabled: $throttle_threshold% @ $throttle_rate"
        fi
    fi

    return 0
}

# Resolve the core script path. Search common install layouts:
#   1) sibling of this CLI script (src/ or ~/.local/bin/)
#   2) /usr/local/bin/sysinfo_core.sh (system CLI co-install)
#   3) /etc/profile.d/sysinfo_core.sh (profile.d / legacy install)
#   4) ~/.local/bin/sysinfo_core.sh (user install)
# Override with SYSINFO_CORE if set.
locate_core_script() {
    local script_dir candidate
    if [ -n "${SYSINFO_CORE:-}" ] && [ -f "$SYSINFO_CORE" ]; then
        CORE_SCRIPT="$SYSINFO_CORE"
        return 0
    fi
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    for candidate in \
        "$script_dir/sysinfo_core.sh" \
        "/usr/local/bin/sysinfo_core.sh" \
        "/etc/profile.d/sysinfo_core.sh" \
        "${HOME:-}/.local/bin/sysinfo_core.sh"; do
        if [ -n "$candidate" ] && [ -f "$candidate" ]; then
            CORE_SCRIPT="$candidate"
            return 0
        fi
    done
    return 1
}

# Source the optional push-notification module (best-effort). Mirrors the core
# search layout. Missing module is non-fatal — notifications simply stay off.
NOTIFY_SCRIPT=""
load_notify_module() {
    local script_dir candidate
    [ -n "$NOTIFY_SCRIPT" ] && return 0
    if [ -n "${SYSINFO_NOTIFY:-}" ] && [ -f "$SYSINFO_NOTIFY" ]; then
        NOTIFY_SCRIPT="$SYSINFO_NOTIFY"
    else
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        for candidate in \
            "$script_dir/sysinfo_notify.sh" \
            "/usr/local/bin/sysinfo_notify.sh" \
            "/etc/profile.d/sysinfo_notify.sh" \
            "${HOME:-}/.local/bin/sysinfo_notify.sh"; do
            if [ -n "$candidate" ] && [ -f "$candidate" ]; then
                NOTIFY_SCRIPT="$candidate"
                break
            fi
        done
    fi
    [ -n "$NOTIFY_SCRIPT" ] || return 1
    # shellcheck disable=SC1090
    source "$NOTIFY_SCRIPT"
    return 0
}

# ============================================
# Show Help
# ============================================

show_help() {
    cat << 'EOF'
sysinfo-cli - System Real-time Monitor (Simplified YAML Configuration)

Usage:
  sysinfo                          - Display system info with default config
  sysinfo [N]                      - Display with N seconds refresh
  sysinfo -c config.yaml           - Apply configuration from YAML file
  sysinfo -r                       - Reload configuration from default path
  sysinfo -h                       - Show this help message

Configuration:
  The configuration is loaded from /etc/sysinfo/config.yaml by default.
  You can specify a custom config file with -c option.

  Default configuration (auto-generated on install):
    - Monthly traffic limit:1T
    - Reset day: 1st of each month
    - Traffic mode: both (upload + download)
    - Throttle enabled at 95% with 10mbps limit

  To customize settings, edit the YAML config file:
    sudo nano /etc/sysinfo/config.yaml

Configuration File Format (YAML):

  network:
    interface: ""              # Auto-detect if empty
    force_gateway_throttle: false

  nat:
    enabled: false
    mappings:
      - "8080:80"
      - "9000:3000"

  traffic:
    enabled: true
    limit: "1T"               # 1T, 500G, 100M, or UNLIMITED
    reset_day: 1              # 1-31
    mode: "both"              # upload, download, or both

  throttle:
    enabled: true
    threshold: 95             # Percentage (0-100)
    rate: "10mbps"           # Rate limit

  display:
    language: "auto"          # auto | zh | en
    refresh_interval: 1       # Seconds (1-60)
    show_traffic: true
    show_nat: true
    show_throttle: true

  notify:                     # Push alerts (modular, Bark). Disabled by default.
    enabled: false
    bark:
      url: "https://api.day.app"
      key: ""
    cooldown: 1800            # Min seconds between repeated alerts per rule
    rules:
      cpu:      { enabled: false, threshold: 90 }
      net:      { enabled: false, threshold: 90 }   # monthly traffic quota %
      nic:      { enabled: false, threshold: 80, mode: both, upload_rate: 0, download_rate: 0 }
      throttle: { enabled: false }
      disk:     { enabled: false, threshold: 90, paths: [] }  # [] = all mounts

Commands:
  -c <file>     Apply configuration from YAML file
  -r              Reload configuration (apply from /etc/sysinfo/config.yaml)
  -h, --help    Show this help message

Maintenance Commands:
  --reset-traffic   Reset monthly traffic statistics
  --clear-nat       Clear NAT port mappings

Notification Commands:
  --notify-test     Send a test push to verify Bark configuration
  --notify-check    Evaluate alert rules against current metrics (use in cron)

Examples:
  # Display system info (default config)
  sysinfo

  # Apply configuration from YAML file
  sysinfo -c /path/to/custom.yaml

  # Reload configuration (apply from /etc/sysinfo/config.yaml)
  sysinfo -r

  # Edit configuration
  sudo nano /etc/sysinfo/config.yaml

  # Reset traffic statistics
  sysinfo --reset-traffic

  # Test push notification
  sysinfo --notify-test

  # Evaluate alert rules every 5 minutes via cron
  #   */5 * * * * /usr/local/bin/sysinfo --notify-check

For more information, visit: https://github.com/baixiaoshengofficial/sysinfo-cli
EOF
}

# ============================================
# Entry Point
# ============================================

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -c)
            if [ -z "${2:-}" ] || [[ "$2" == -* ]]; then
                echo "Error: -c requires a config file path"
                echo "Usage: sysinfo -c /path/to/config.yaml"
                exit 1
            fi
            CONFIG_FILE="$2"
            APPLY_CONFIG="true"
            shift 2
            ;;
        -r)
            # -r always reloads the system config when present (not ~/.config shadow copy).
            if [ -n "${SYSINFO_CONFIG:-}" ] && [ -f "$SYSINFO_CONFIG" ]; then
                CONFIG_FILE="$SYSINFO_CONFIG"
            elif [ -f /etc/sysinfo/config.yaml ]; then
                CONFIG_FILE="/etc/sysinfo/config.yaml"
            elif [ -z "$CONFIG_FILE" ]; then
                CONFIG_FILE="$DEFAULT_CONFIG_FILE"
            fi
            echo "Reloading configuration from: $CONFIG_FILE"
            if load_config "$CONFIG_FILE"; then
                apply_config
                exit 0
            else
                echo "Error: Failed to load configuration"
                exit 1
            fi
            ;;
        --reset-traffic)
            # Defer to the post-parse block so core location/sourcing is unified.
            ACTION="reset-traffic"
            shift
            ;;
        --notify-check)
            # Evaluate notification rules against current metrics (for cron).
            ACTION="notify-check"
            shift
            ;;
        --notify-test)
            # Send a test push to verify provider configuration.
            ACTION="notify-test"
            shift
            ;;
        --clear-nat)
            run_privileged rm -f /etc/sysinfo-nat
            echo "NAT port mappings cleared"
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            echo "Use -h for help"
            exit 1
            ;;
        *)
            # Assume it's a refresh interval
            if [[ "$1" =~ ^[0-9]+$ ]]; then
                INTERVAL="$1"
            fi
            shift
            ;;
    esac
done

# If no config file specified, use default for display/runtime configuration only.
if [ -z "$CONFIG_FILE" ] && [ -f "$DEFAULT_CONFIG_FILE" ]; then
    CONFIG_FILE="$DEFAULT_CONFIG_FILE"
fi

# Send a test push (no core engine required).
if [ "$ACTION" = "notify-test" ]; then
    if ! load_notify_module; then
        echo "Error: notification module (sysinfo_notify.sh) not found"
        exit 1
    fi
    notify_test
    exit $?
fi

# Apply config only when explicitly requested with -c.
if [ "$APPLY_CONFIG" = "true" ]; then
    if [ -z "$CONFIG_FILE" ]; then
        CONFIG_FILE="$DEFAULT_CONFIG_FILE"
    fi
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Error: Configuration file not found: $CONFIG_FILE"
        exit 1
    fi
    echo "Applying configuration from: $CONFIG_FILE"
    if load_config "$CONFIG_FILE"; then
        apply_config
        exit 0
    else
        exit 1
    fi
fi

# Locate the core engine (shared by reset-traffic and the dashboard render).
if ! locate_core_script; then
    echo "Error: sysinfo_core.sh not found"
    echo ""
    echo "Searched:"
    echo "  - Next to this script"
    echo "  - /usr/local/bin/sysinfo_core.sh"
    echo "  - /etc/profile.d/sysinfo_core.sh"
    echo "  - \$HOME/.local/bin/sysinfo_core.sh"
    echo ""
    echo "Fix:  sudo ./install.sh"
    exit 1
fi

# Maintenance actions that need core functions sourced.
if [ "$ACTION" = "reset-traffic" ]; then
    source "$CORE_SCRIPT"
    reset_traffic
    exit 0
fi

# Display system info. In an interactive terminal, refresh in a single shell
# (source core once) to avoid watch respawning bash + re-sourcing every tick.
INTERVAL=${INTERVAL:-$(get_config "display.refresh_interval" "1")}
if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]] || [ "$INTERVAL" -lt 1 ] || [ "$INTERVAL" -gt 60 ]; then
    INTERVAL=1
fi

SYSINFO_SHOW_TRAFFIC=$(get_config "display.show_traffic" "true")
SYSINFO_SHOW_NAT=$(get_config "display.show_nat" "true")
SYSINFO_SHOW_THROTTLE=$(get_config "display.show_throttle" "true")
export SYSINFO_SHOW_TRAFFIC SYSINFO_SHOW_NAT SYSINFO_SHOW_THROTTLE

# Honor display.language from the active config immediately (no -r needed).
# Empty/auto leaves SYSINFO_LANG unset so core falls back to /etc/sysinfo-lang
# or the system locale.
_cfg_lang=$(normalize_lang "$(get_config "display.language" "auto")")
if [ -n "$_cfg_lang" ]; then
    export SYSINFO_LANG="$_cfg_lang"
fi

source "$CORE_SCRIPT"

# Load the push-notification module so sysinfo_render can evaluate alert rules.
load_notify_module 2>/dev/null || true

# Headless rule evaluation (cron entrypoint): compute metrics via a silent
# render — notify_check runs inside it — then exit without drawing the dashboard.
# The NIC throughput rule needs two samples ~1s apart, so prime first (with
# notifications suppressed), then evaluate on the second render.
if [ "$ACTION" = "notify-check" ]; then
    SYSINFO_NOTIFY_SKIP=1 sysinfo_render >/dev/null 2>&1
    sleep 1
    sysinfo_render >/dev/null 2>&1
    exit 0
fi

# In-place live refresh: alternate screen + overwrite lines (no full clear flash).
sysinfo_live_loop() {
    local interval=$1
    trap 'printf "\033[?25h\033[?1049l\033[0m"; exit 0' INT TERM
    # Alternate buffer keeps scrollback clean; hide cursor while refreshing.
    printf '\033[?1049h\033[?25l'
    while true; do
        printf '\033[H'
        while IFS= read -r line || [ -n "$line" ]; do
            printf '%s\033[K\n' "$line"
        done < <(sysinfo_render)
        # Erase leftover lines when the layout shrinks (e.g. fewer disk rows).
        printf '\033[J'
        sleep "$interval"
    done
}

if [ -t 1 ]; then
    sysinfo_live_loop "$INTERVAL"
else
    sysinfo_render
fi
