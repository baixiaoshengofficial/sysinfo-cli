# sysinfo

适用于 Debian/Ubuntu SSH 登录的轻量级系统状态仪表板。

[English](README.md)

## 预览
![image.png](https://yourls.baixiaosheng.de/3w)

## 功能特性
- **SSH 横幅**: 通过 `/etc/profile.d/` 在登录时显示实时状态
- **实时监控**: 快捷命令 `sysinfo` 进行实时监控
- **网络速度**: 实时网络速度监控，自动转换 KB/s ↔ MB/s
- **流量统计**: 月度流量跟踪，可配置限制和统计模式
- **NAT 端口映射**: 显示和配置 NAT 端口映射
- **动态进度条**: 可视化磁盘使用情况，带颜色警告
- **轻量级**: 最小依赖，快速执行
- **YAML 配置**: 通过 YAML 文件简单灵活地配置

## 快速安装

### 1. 通过 baixiaosheng.de
```bash
bash <(curl -sSL baixiaosheng.de/sysinfo)
```

### 2. 通过 GitHub
```bash
curl -sSL https://raw.githubusercontent.com/jokerknight/sysinfo-cli/main/install.sh | bash
```

### 3. 下载并运行
```bash
git clone https://github.com/jokerknight/sysinfo-cli.git
cd sysinfo-cli
./install.sh
```

## 使用方法

### 基本命令
```bash
sysinfo              # 启动实时监控（1秒刷新）
sysinfo 2            # 以 2 秒间隔刷新
sysinfo 5            # 以 5 秒间隔刷新
```

### 通过 YAML 配置

新的 YAML 配置格式提供了简单灵活的方式来配置 sysinfo：

**默认配置**（安装时自动生成）：
- 月度流量限制：1T
- 重置日期：每月 1 号
- 流量模式：both（上传 + 下载）
- 达到 95% 时启用限速，限制为 10mbps

**编辑配置**：
```bash
sudo nano /etc/sysinfo/config.yaml
```

**应用配置**：
```bash
sysinfo -c /etc/sysinfo/config.yaml
```

**配置文件格式**：

```yaml
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
  limit: "1T"               # 1T, 500G, 100M, 或 UNLIMITED
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
```

### 命令行选项

```bash
# 使用默认配置显示系统信息
sysinfo

# 使用自定义配置文件显示
sysinfo -c /path/to/custom.yaml

# 从 YAML 文件应用配置
sysinfo -c /etc/sysinfo/config.yaml

# 重新加载配置（从 /etc/sysinfo/config.yaml 应用）
sysinfo -r

# 重置月度流量统计
sysinfo --reset-traffic

# 显示帮助
sysinfo -h
```

> 配置现为仅支持 YAML（`-c` / `-r`）。旧 CLI 配置参数已废弃。

## 配置参数说明

### 流量参数
- `limit`: 流量限制（例如 1T, 500G, 100M, UNLIMITED）
- `reset_day`: 重置日期（1-31，默认：1）
- `mode`: 流量模式（upload/download/both，默认：both）

**流量统计模式**：
- `both`（默认）：统计上传和下载双向流量
- `upload`：仅统计上传流量
- `download`：仅统计下载流量

### 限速参数
- `enabled`: 启用/禁用限速（true/false）
- `threshold`: 流量百分比（默认：95）
- `rate`: 限速值（最小 1mbps，推荐 1mbps）
- `network.force_gateway_throttle`: 在网关模式强制限速（默认：false，谨慎使用）

## 卸载

### 1. 通过 baixiaosheng.de
```bash
bash <(curl -sSL baixiaosheng.de/sysinfo/uninstall)
```

### 2. 通过 GitHub
```bash
curl -sSL https://raw.githubusercontent.com/jokerknight/sysinfo-cli/main/uninstall.sh | bash
```

### 3. 本地脚本
```bash
cd sysinfo-cli
./uninstall.sh
```

## 文件说明
- `sysinfo.sh`: 主入口脚本，处理命令行参数
- `sysinfo_core.sh`: 核心监控和 TC 功能
- `install.sh`: 安装脚本
- `uninstall.sh`: 卸载脚本
- `config.yaml.example`: 示例配置文件
