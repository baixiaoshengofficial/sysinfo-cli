# sysinfo-cli

sysinfo-cli — 适用于 Debian/Ubuntu SSH 登录的轻量级系统状态仪表板。

[English](README.md)

## 预览
![image.png](https://yourls.baixiaosheng.de/3w)

## 功能特性
- **SSH 横幅**: 通过 `/etc/profile.d/`（bash）和 `/etc/zsh/zprofile`（zsh）在登录时显示实时状态
- **实时监控**: 快捷命令 `sysinfo` 进行实时监控
- **网络速度**: 实时网络速度监控，自动转换 KB/s ↔ MB/s
- **流量统计与限速**: 月度流量跟踪，超阈值后基于 `tc` 自动限速
- **NAT 端口映射**: 显示和配置 NAT 端口映射
- **推送通知**: 模块化告警（Bark），支持 CPU / 流量配额 / 网卡速率 / 限速 / 磁盘 规则
- **多语言**: 中文 / 英文界面，可在配置中切换
- **进度条**: 实心方块可视化磁盘 / 流量使用情况
- **轻量级**: 最小依赖，快速执行
- **YAML 配置**: 通过 YAML 文件简单灵活地配置

## 快速安装

### 1. 通过 baixiaosheng.de
```bash
bash <(curl -sSL baixiaosheng.de/sysinfo)
```

### 2. 通过 GitHub
```bash
curl -sSL https://raw.githubusercontent.com/baixiaoshengofficial/sysinfo-cli/main/install.sh | bash
```

### 3. 下载并运行
```bash
git clone https://github.com/baixiaoshengofficial/sysinfo-cli.git
cd sysinfo-cli
./install.sh
```

> 重复执行 `./install.sh` 会**保留**已有的 `/etc/sysinfo/config.yaml`；如需重置为模板请加 `--overwrite-config`（会自动备份旧配置）。指定安装语言用 `--lang zh|en`。

## 使用方法

### 基本命令
```bash
sysinfo              # 启动实时监控（1秒刷新）
sysinfo 2            # 以 2 秒间隔刷新
sysinfo 5            # 以 5 秒间隔刷新
```

### 通过 YAML 配置

新的 YAML 配置格式提供了简单灵活的方式来配置 sysinfo-cli：

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
  language: "auto"          # 界面语言: auto(跟随系统) / zh(中文) / en(English)
  refresh_interval: 1       # 秒 (1-60)
  show_traffic: true
  show_nat: true
  show_throttle: true

# 推送通知（模块化，目前支持 Bark）。默认关闭。
notify:
  enabled: false            # 推送总开关
  bark:
    url: "https://api.day.app"   # Bark 服务器地址（可自建）
    key: ""                       # Bark 设备 key（必填才会推送）
  cooldown: 1800            # 同一规则两次告警的最小间隔（秒，防刷屏）
  rules:                    # 每条规则可独立开关，默认全部关闭
    cpu:                    # CPU 使用率达到阈值触发
      enabled: false
      threshold: 90
    net:                    # 月流量配额百分比达到阈值触发
      enabled: false
      threshold: 90
    nic:                    # 当前吞吐达到带宽速率的百分比触发
      enabled: false
      threshold: 80
      mode: "both"          # 方向: upload(仅上行) / download(仅下行) / both(双向)
      upload_rate: 0        # 自定义上行带宽(Mbit/s)，0=自动用网卡链路速率
      download_rate: 0      # 自定义下行带宽(Mbit/s)，0=自动用网卡链路速率
    throttle:              # 触发限速时推送
      enabled: false
    disk:                  # 磁盘使用率达到阈值触发
      enabled: false
      threshold: 90
      paths: []            # 监控哪些挂载点/目录；留空=全部挂载点
      #   例: paths: ["/", "/mnt/data", "/var/log"]
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

# 清除 NAT 端口映射
sysinfo --clear-nat

# 发送测试推送（验证 Bark 配置）
sysinfo --notify-test

# 按当前指标评估告警规则（建议放入 cron 定时执行）
sysinfo --notify-check
#   例：每 5 分钟检查一次
#   */5 * * * * /usr/local/bin/sysinfo --notify-check

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

### 推送参数（notify）
- `enabled`: 推送总开关（默认 false）
- `bark.url` / `bark.key`: Bark 服务器地址与设备 key（key 必填才会推送）
- `cooldown`: 同一规则两次告警的最小间隔（秒，默认 1800，防刷屏）
- `rules.cpu` / `rules.net` / `rules.disk`: 达到 `threshold`(%) 触发；`disk.paths` 留空=全部挂载点，或指定挂载点/目录
- `rules.nic`: 达到带宽 `threshold`(%) 触发；`mode` 选 upload/download/both；`upload_rate`/`download_rate` 自定义带宽(Mbit/s)，0=自动用网卡链路速率
- `rules.throttle`: 触发限速时推送

> 规则采用「边沿触发 + 冷却」：首次越过阈值推一次，持续超标每 `cooldown` 秒重推，恢复后清除状态。
> `nic` 规则需要两次网络采样才能算速率，`--notify-check` 已内置自动采样。

## 卸载

### 1. 通过 baixiaosheng.de
```bash
bash <(curl -sSL baixiaosheng.de/sysinfo/uninstall)
```

### 2. 通过 GitHub
```bash
curl -sSL https://raw.githubusercontent.com/baixiaoshengofficial/sysinfo-cli/main/uninstall.sh | bash
```

### 3. 本地脚本
```bash
cd sysinfo-cli
./uninstall.sh
```

## 文件说明

```
sysinfo-cli/
├── src/
│   ├── sysinfo.sh             # CLI 入口（参数解析、YAML 配置、实时面板）
│   ├── sysinfo_core.sh        # 核心引擎（指标采集、流量统计、tc 限速）
│   ├── sysinfo_notify.sh      # 推送通知模块（Bark + 规则引擎）
│   ├── sysinfo_banner.sh      # SSH 登录横幅（一次性轻量展示）
│   └── sysinfo_banner_shim.sh # 登录横幅 POSIX shim（兼容 bash/zsh）
├── scripts/
│   └── test_throttle.sh       # 限速诊断工具
├── tests/
│   ├── test_sysinfo.sh        # 自动化测试
│   └── server_validate.sh     # 服务器端完整验证
├── install.sh                 # 安装 / 更新（sudo）
├── uninstall.sh               # 卸载脚本
└── config.yaml.example        # YAML 配置示例
```

详见：[docs/PROJECT_STRUCTURE.md](docs/PROJECT_STRUCTURE.md)（含系统安装后的路径说明）

**开发快速上手：**

```bash
./src/sysinfo.sh -h              # 查看帮助
timeout 3 ./src/sysinfo.sh       # 一次性仪表盘（非交互）
bash tests/server_validate.sh    # 完整验证
sudo ./install.sh                # 安装或更新
```
