# sysinfo

A lightweight system status dashboard for Debian/Ubuntu SSH login.

[中文说明](README_zh.md)

## Preview
![image.png](https://yourls.baixiaosheng.de/3w)

## Features
- **SSH Banner**: Real-time stats upon login via `/etc/profile.d/`
- **Live Monitor**: Shortcut command `sysinfo` for real-time monitoring
- **Network Speed**: Real-time network speed monitoring with auto KB/s ↔ MB/s conversion
- **Traffic Statistics**: Monthly traffic tracking with configurable limits and counting modes
- **NAT Port Mapping**: Display and configure NAT port mappings
- **Dynamic Bars**: Visualized disk usage with color alerts
- **Lightweight**: Minimal dependencies and fast execution
- **YAML Configuration**: Simple and flexible configuration via YAML file

## Quick Installation

### 1. Via baixiaosheng.de
```bash
bash <(curl -sSL baixiaosheng.de/sysinfo)
```

### 2. Via GitHub
```bash
curl -sSL https://raw.githubusercontent.com/jokerknight/sysinfo-cli/main/install.sh | bash
```

### 3. Download and run
```bash
git clone https://github.com/jokerknight/sysinfo-cli.git
cd sysinfo-cli
./install.sh
```

## Usage

### Basic Commands
```bash
sysinfo              # Start real-time monitoring (1s refresh)
sysinfo 2            # Start with 2s refresh interval
sysinfo 5            # Start with 5s refresh interval
```

### Configuration via YAML

The new YAML configuration format provides a simple and flexible way to configure sysinfo:

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
  limit: "1T"               # 1T, 500G, 100M, or UNLIMITED
  reset_day: 1              # 1-31
  mode: "both"              # upload, download, or both

# Throttle Configuration
throttle:
  enabled: true
  threshold: 95             # Percentage (0-100)
  rate: "10mbps"           # Rate limit

# Display Configuration
display:
  refresh_interval: 1       # Seconds (1-60)
  show_traffic: true
  show_nat: true
  show_throttle: true
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

# Show help
sysinfo -h
```

> Configuration is YAML-only (`-c` / `-r`). Legacy CLI configuration flags are deprecated.

## Configuration Parameters

### Traffic Parameters
- `limit`: Traffic limit (e.g., 1T, 500G, 100M, UNLIMITED)
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

## Uninstall

### 1. Via baixiaosheng.de
```bash
bash <(curl -sSL baixiaosheng.de/sysinfo/uninstall)
```

### 2. Via GitHub
```bash
curl -sSL https://raw.githubusercontent.com/jokerknight/sysinfo-cli/main/uninstall.sh | bash
```

### 3. Local script
```bash
cd sysinfo-cli
./uninstall.sh
```

## Files
- `sysinfo.sh`: The main entry script with CLI parsing
- `sysinfo_core.sh`: Core monitoring and TC functionality
- `install.sh`: Installation script
- `uninstall.sh`: Uninstallation script
- `config.yaml.example`: Example configuration file
