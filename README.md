# sysinfo-cli

sysinfo-cli — A lightweight system status dashboard for Linux SSH login (Debian, Ubuntu, RHEL, Fedora, Alpine, Arch, openSUSE, …; macOS not supported).

[中文说明](README_zh.md)

## Preview
![image.png](https://yourls.baixiaosheng.de/3w)

## Features
- **SSH Banner**: Real-time stats upon login via `/etc/profile.d/` (bash) and `/etc/zsh/zprofile` (zsh)
- **Live Monitor**: Shortcut command `sysinfo` for real-time monitoring
- **Network Speed**: Real-time network speed monitoring with auto KB/s ↔ MB/s conversion
- **Traffic & Throttling**: Monthly traffic tracking with automatic `tc`-based rate limiting above a threshold
- **NAT Port Mapping**: Display and configure NAT port mappings
- **Push Notifications**: Modular alerts (Bark) for CPU / traffic quota / NIC speed / throttle / disk rules
- **Multi-language**: Chinese / English UI, switchable in config
- **Progress Bars**: Solid-block visualization of disk / traffic usage
- **Lightweight**: Minimal dependencies and fast execution
- **YAML Configuration**: Simple and flexible configuration via YAML file

## Quick Installation

### 1. Via baixiaosheng.de
```bash
bash <(curl -sSL baixiaosheng.de/sysinfo)
```

### 2. Via GitHub
```bash
curl -sSL https://raw.githubusercontent.com/baixiaoshengofficial/sysinfo-cli/main/install.sh | bash
```

### 3. Download and run
```bash
git clone https://github.com/baixiaoshengofficial/sysinfo-cli.git
cd sysinfo-cli
./install.sh
```

> Re-running `./install.sh` **keeps** an existing `/etc/sysinfo/config.yaml`; pass `--overwrite-config` to reset it to the template (the old one is backed up). Use `--lang zh|en` to set the install language.

## Usage

### Basic Commands
```bash
sysinfo              # Start real-time monitoring (1s refresh)
sysinfo 2            # Start with 2s refresh interval
sysinfo 5            # Start with 5s refresh interval
```

### Configuration via YAML

The new YAML configuration format provides a simple and flexible way to configure sysinfo-cli:

**Default Configuration** (auto-generated on install):
- Monthly traffic limit: 1T
- Reset day: 1st of each month
- Traffic mode: both (upload + download)
- Throttle enabled at 95% with 10mbps limit

**Edit Configuration**:
```bash
sudo nano /etc/sysinfo/config.yaml
```

**Apply Configuration**:
```bash
sysinfo -c /etc/sysinfo/config.yaml
```

**Configuration File Format**:

```yaml
# Network Interface Configuration
network:
  interface: ""              # Auto-detect if empty
  force_gateway_throttle: false

# NAT Port Mappings
nat:
  enabled: false
  mappings:
    - "8080:80"
    - "9000:3000"

# Traffic Limit Configuration
traffic:
  enabled: true
  limit: "1T"               # 1T, 500G, 100M, UNLIMITED, or 0
  reset_day: 1              # 1-31
  mode: "both"              # upload, download, or both

# Throttle Configuration
throttle:
  enabled: true
  threshold: 95             # Percentage (0-100)
  rate: "10mbps"           # Rate limit

# Display Configuration
display:
  language: "auto"          # UI language: auto (system locale) / zh / en
  refresh_interval: 1       # Seconds (1-60)
  show_traffic: true
  show_nat: true
  show_throttle: true

# Push Notification (modular; currently supports Bark). Disabled by default.
notify:
  enabled: false            # Master switch
  bark:
    url: "https://api.day.app"   # Bark server base URL (self-hosted OK)
    key: ""                       # Bark device key (required to enable push)
  cooldown: 1800            # Min seconds between repeated alerts per rule
  rules:                    # Each rule toggles independently; all off by default
    cpu:                    # Fire when CPU usage % reaches threshold
      enabled: false
      threshold: 90
    net:                    # Fire when monthly traffic quota % reaches threshold
      enabled: false
      threshold: 90
    nic:                    # Fire when throughput reaches % of bandwidth rate
      enabled: false
      threshold: 80
      mode: "both"          # upload | download | both
      upload_rate: 0        # Custom uplink Mbit/s; 0 = auto NIC link speed
      download_rate: 0      # Custom downlink Mbit/s; 0 = auto NIC link speed
    throttle:              # Fire when rate-limit (throttle) becomes active
      enabled: false
    disk:                  # Fire when disk usage % reaches threshold
      enabled: false
      threshold: 90
      paths: []            # Which mounts/dirs to watch; empty = all mounts
      #   e.g. paths: ["/", "/mnt/data", "/var/log"]
```

### Command Line Options

```bash
# Display system info with default config
sysinfo

# Display with custom configuration file
sysinfo -c /path/to/custom.yaml

# Apply configuration from YAML file
sysinfo -c /etc/sysinfo/config.yaml

# Reload configuration (apply from /etc/sysinfo/config.yaml)
sysinfo -r

# Reset monthly traffic statistics
sysinfo --reset-traffic

# Clear NAT port mappings
sysinfo --clear-nat

# Send a test push (verify Bark config)
sysinfo --notify-test

# Evaluate alert rules against current metrics (use in cron)
sysinfo --notify-check
#   e.g. check every 5 minutes:
#   */5 * * * * /usr/local/bin/sysinfo --notify-check

# Show help
sysinfo -h
```

> Configuration is YAML-only (`-c` / `-r`). Legacy CLI configuration flags are deprecated.

## Configuration Parameters

### Traffic Parameters
- `limit`: Traffic limit (e.g., 1T, 500G, 100M, UNLIMITED, or 0 for unlimited)
- `reset_day`: Reset day (1-31, default: 1)
- `mode`: Traffic mode (upload/download/both, default: both)

**Traffic modes**:
- `both` (default): Count both upload and download traffic
- `upload`: Count only upload traffic
- `download`: Count only download traffic

### Throttling Parameters
- `enabled`: Enable/disable throttling (true/false)
- `threshold`: Traffic percentage (default: 95)
- `rate`: Speed limit (minimum: 1mbps, recommended: 1mbps)
- `network.force_gateway_throttle`: Force throttling on gateway mode (default: false, use with caution)

### Notification Parameters (notify)
- `enabled`: Master switch for push (default false)
- `bark.url` / `bark.key`: Bark server URL and device key (key required to push)
- `cooldown`: Min seconds between repeated alerts for the same rule (default 1800)
- `rules.cpu` / `rules.net` / `rules.disk`: fire at `threshold` (%); `disk.paths` empty = all mounts, or list specific mounts/dirs
- `rules.nic`: fire at bandwidth `threshold` (%); `mode` = upload/download/both; `upload_rate`/`download_rate` custom Mbit/s, 0 = auto NIC link speed
- `rules.throttle`: fire when rate-limiting becomes active

> Rules are edge-triggered with cooldown: alert once on crossing, re-alert every `cooldown` while sustained, clear on recovery.
> The `nic` rule needs two network samples to compute a rate; `--notify-check` self-samples automatically.

## Uninstall

### 1. Via baixiaosheng.de
```bash
bash <(curl -sSL baixiaosheng.de/sysinfo/uninstall)
```

### 2. Via GitHub
```bash
curl -sSL https://raw.githubusercontent.com/baixiaoshengofficial/sysinfo-cli/main/uninstall.sh | bash
```

### 3. Local script
```bash
cd sysinfo-cli
./uninstall.sh
```

## Files

```
sysinfo-cli/
├── src/
│   ├── sysinfo.sh             # CLI entry point (args, YAML config, live dashboard)
│   ├── sysinfo_core.sh        # Core engine (metrics, traffic stats, tc throttling)
│   ├── sysinfo_notify.sh      # Push notification module (Bark + rule engine)
│   ├── sysinfo_banner.sh      # SSH login banner (one-shot, lightweight)
│   └── sysinfo_banner_shim.sh # Login banner POSIX shim (bash/zsh compatible)
├── scripts/
│   └── test_throttle.sh       # Throttle diagnostic tool
├── tests/
│   ├── test_sysinfo.sh        # Automated test runner
│   └── server_validate.sh     # Server-side validation suite
├── install.sh                 # Install / update (requires sudo)
├── uninstall.sh               # Uninstaller
└── config.yaml.example        # Example YAML configuration
```

See also: [docs/PROJECT_STRUCTURE.md](docs/PROJECT_STRUCTURE.md) for installed system paths.

**Development quick start:**

```bash
./src/sysinfo.sh -h              # Help
timeout 3 ./src/sysinfo.sh       # One-shot dashboard (non-interactive)
bash tests/server_validate.sh    # Full validation
sudo ./install.sh                # Install or update
```
