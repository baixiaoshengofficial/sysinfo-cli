#!/bin/bash

# ============================================
# SysInfo-Cli - System Real-time Monitor
# Command Line Tool (CLI) - YAML Configuration
# ============================================

# Default paths
DEFAULT_CONFIG_FILE="/etc/sysinfo/config.yaml"
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

# Read one YAML key from a specific file (helper for get_config).
_get_config_from_file() {
    local key="$1"
    local file="$2"
    check_yq 2>/dev/null || return 0
    yq eval ".$key" "$file" 2>/dev/null
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

    local nat_enabled
    nat_enabled=$(is_config_true "nat.enabled" && echo "true" || echo "false")

    # Apply NAT mappings
    if $nat_enabled; then
        local mappings
        mappings=$(yq eval '.nat.mappings[]' "$CONFIG_FILE" 2>/dev/null | tr '\n' ' ' | sed 's/ *$//')
        if [ -n "$mappings" ]; then
            echo "$mappings" | run_privileged tee /etc/sysinfo-nat >/dev/null 2>&1
            echo "✓ NAT configured: $mappings"
        fi
    fi

    # Apply traffic configuration
    local traffic_enabled
    local traffic_limit
    local traffic_day
    local traffic_mode

    traffic_enabled=$(is_config_true "traffic.enabled" && echo "true" || echo "false")
    traffic_limit=$(get_config "traffic.limit" "1T")
    traffic_day=$(get_config "traffic.reset_day" "1")
    traffic_mode=$(get_config "traffic.mode" "both")

    if $traffic_enabled; then
        local traffic_json="{\"limit\":\"$traffic_limit\",\"reset_day\":$traffic_day,\"traffic_mode\":\"$traffic_mode\""
        local throttle_enabled
        throttle_enabled=$(is_config_true "throttle.enabled" && echo "true" || echo "false")

        if $throttle_enabled; then
            local throttle_threshold
            local throttle_rate
            local throttle_force
            throttle_threshold=$(get_config "throttle.threshold" "95")
            throttle_rate=$(get_config "throttle.rate" "10mbps")
            throttle_force=$(is_config_true "network.force_gateway_throttle" && echo "true" || echo "false")
            traffic_json+=",\"throttle_enabled\":true,\"throttle_threshold\":$throttle_threshold,\"throttle_rate\":\"$throttle_rate\",\"force_throttle\":$throttle_force"
        else
            traffic_json+=",\"throttle_enabled\":false,\"force_throttle\":false"
        fi

        traffic_json+="}"

        echo "$traffic_json" | run_privileged tee /etc/sysinfo-traffic >/dev/null 2>&1
        echo "✓ Traffic configured: $traffic_limit (day $traffic_day, mode $traffic_mode)"
        if $throttle_enabled; then
            echo "  Throttle enabled: $throttle_threshold% @ $throttle_rate"
        fi
    fi

    return 0
}

# Resolve the core script path: prefer the sibling src/ copy, fall back to the
# installed /etc/profile.d copy. Returns 0 and sets CORE_SCRIPT, or returns 1.
locate_core_script() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    CORE_SCRIPT="$script_dir/sysinfo_core.sh"
    if [ ! -f "$CORE_SCRIPT" ] && [ -f "/etc/profile.d/sysinfo_core.sh" ]; then
        CORE_SCRIPT="/etc/profile.d/sysinfo_core.sh"
    fi
    [ -f "$CORE_SCRIPT" ]
}

# ============================================
# Show Help
# ============================================

show_help() {
    cat << 'EOF'
SysInfo-Cli - System Real-time Monitor (Simplified YAML Configuration)

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
    refresh_interval: 1       # Seconds (1-60)
    show_traffic: true
    show_nat: true
    show_throttle: true

Commands:
  -c <file>     Apply configuration from YAML file
  -r              Reload configuration (apply from /etc/sysinfo/config.yaml)
  -h, --help    Show this help message

Maintenance Commands:
  --reset-traffic   Reset monthly traffic statistics
  --clear-nat       Clear NAT port mappings

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

For more information, visit: https://github.com/jokerknight/sysinfo-cli
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
            CONFIG_FILE="$2"
            APPLY_CONFIG="true"
            shift 2
            ;;
        -r)
            # Reload configuration from default path
            if [ -z "$CONFIG_FILE" ]; then
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

# Apply config only when explicitly requested with -c.
if [ "$APPLY_CONFIG" = "true" ] && [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
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
    exit 1
fi

# Maintenance actions that need core functions sourced.
if [ "$ACTION" = "reset-traffic" ]; then
    source "$CORE_SCRIPT"
    reset_traffic
    exit 0
fi

# Display system info. In an interactive terminal, use watch for live monitoring;
# in non-interactive/test contexts, render once to avoid hanging.
INTERVAL=${INTERVAL:-$(get_config "display.refresh_interval" "1")}
if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]] || [ "$INTERVAL" -lt 1 ] || [ "$INTERVAL" -gt 60 ]; then
    INTERVAL=1
fi

SYSINFO_SHOW_TRAFFIC=$(get_config "display.show_traffic" "true")
SYSINFO_SHOW_NAT=$(get_config "display.show_nat" "true")
SYSINFO_SHOW_THROTTLE=$(get_config "display.show_throttle" "true")
export SYSINFO_SHOW_TRAFFIC SYSINFO_SHOW_NAT SYSINFO_SHOW_THROTTLE

if [ -t 1 ] && command -v watch >/dev/null 2>&1; then
    watch -c -n "$INTERVAL" -t bash -c "echo ''; source '$CORE_SCRIPT' 2>/dev/null && sysinfo_render" 2>/dev/null
else
    source "$CORE_SCRIPT"
    sysinfo_render
fi
