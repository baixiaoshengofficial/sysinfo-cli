# Changelog / 更新日志

本文档记录 `sysinfo-cli` 的重要变更。每条目含 **中文** 与 **English** 对照。

---

## [Unreleased] — 2026-06-29

### Added · 新增

- **Bark 推送通知模块**（`src/sysinfo_notify.sh`）：CPU / 流量配额 / 网卡速率 / 限速 / 磁盘规则，边沿触发 + 冷却去重；`--notify-test`、`--notify-check`。
  **Bark push notifications** (`src/sysinfo_notify.sh`): CPU, traffic quota, NIC speed, throttle, and disk rules with edge-trigger + cooldown; `--notify-test`, `--notify-check`.

- **文档站点**：`docs/index.html` 落地页、`docs/wiki.html` Wiki；`make docs-serve` / `make docs-stop` 本地预览（端口占用自动释放）。
  **Docs site**: `docs/index.html` landing page, `docs/wiki.html` wiki; `make docs-serve` / `make docs-stop` for local preview (auto-frees occupied port).

- **RHEL/Fedora `tc` 分包**：`dnf`/`yum` 同时安装 `iproute` + `iproute-tc`（此前仅装 `iproute` 导致无 `tc`）。
  **RHEL/Fedora split `tc` package**: `dnf`/`yum` now install both `iproute` and `iproute-tc`.

- **`install.sh` root 模式**：新增 `run_privileged()`，root 容器/安装时不再依赖 `sudo`。
  **`install.sh` as root**: `run_privileged()` runs commands directly when EUID=0 (no `sudo` required).

### Changed · 变更

- **多发行版 Linux 安装**：`install.sh` 自动识别 apt / dnf / yum / apk / pacman / zypper / emerge；RHEL 系安装 `iproute`，其余多为 `iproute2`；仅支持 Linux（不支持 macOS）。
  **Multi-distro Linux install**: `install.sh` auto-detects apt/dnf/yum/apk/pacman/zypper/emerge; RHEL family gets `iproute`, others `iproute2`; Linux only (not macOS).

- **yq 按 CPU 架构下载**（amd64 / arm64 / arm），修复 ARM 服务器上 `Exec format error` 导致 YAML 配置无法读取的问题。
  **yq downloaded per CPU arch** (amd64/arm64/arm); fixes `Exec format error` on ARM hosts breaking YAML config reads.

- **yq 多语法兼容**：`sysinfo.sh` 兼容 mikefarah yq v3/v4 与常见读法；优先使用 `/usr/local/bin/yq`。
  **yq multi-syntax support** in `sysinfo.sh` for mikefarah v3/v4; prefers `/usr/local/bin/yq`.

- **`sysinfo -r` 配置应用**：从目标文件读取 `display.language` 等项（`get_applied_config`），避免误读用户目录配置；`-r` 默认应用 `/etc/sysinfo/config.yaml`。
  **`sysinfo -r` config apply**: reads keys like `display.language` only from the target file (`get_applied_config`); `-r` defaults to `/etc/sysinfo/config.yaml`.

- **远程安装**（`curl | bash`）：无本地仓库时从 GitHub 拉取 `config.yaml.example`；无 zsh 时跳过 zsh hook。
  **Remote install** (`curl | bash`): fetches `config.yaml.example` from GitHub when not in a checkout; skips zsh hook if zsh is absent.

- **落地页 / Wiki**：支持 Linux 多发行版说明；首屏并排展示 `sysinfo` 终端预览与 iPhone Bark 推送图；推送区图文与命令块等高布局。
  **Landing / Wiki**: multi-distro Linux docs; hero shows terminal + iPhone Bark side by side; notify section image aligned with command block height.

- **`Dockerfile`**：yq 按 `TARGETARCH` 选择二进制。
  **`Dockerfile`**: yq binary selected via `TARGETARCH`.

- **`sysinfo_core.sh`**：`grep -oP` 改为 `sed`，提升 Alpine 等环境兼容性。
  **`sysinfo_core.sh`**: replaced `grep -oP` with `sed` for better Alpine compatibility.

- **README / README_zh**：定位从「仅 Debian/Ubuntu」扩展为通用 Linux。
  **README / README_zh**: positioning broadened from Debian/Ubuntu-only to general Linux.

### Fixed · 修复

- ARM 主机安装错误架构的 yq 后，`language: zh` 等配置不生效。
  Wrong-arch yq on ARM caused `language: zh` and other YAML settings to be ignored.

- 管道执行 `install.sh` 时缺少 `config.yaml.example` 或 `/etc/zsh` 导致安装失败。
  Piped `install.sh` failed when `config.yaml.example` or `/etc/zsh` was missing.

---

## [0.2.0] — 2026-06-26

### Changed · 变更

- 移除根目录兼容 wrapper，统一使用 `src/`、`scripts/`；`install.sh` 将 core 同时安装到 `/usr/local/bin/` 与 `/etc/profile.d/`。
  Removed root-level wrapper scripts; unified on `src/` and `scripts/`; `install.sh` co-installs core to `/usr/local/bin/` and `/etc/profile.d/`.

- 实时监控改为单 shell 刷新循环，降低 CPU 占用。
  Live monitor uses a single-shell refresh loop to reduce CPU usage.

---

## [0.1.0] — 2026-03-02

### Added · 新增

- 月流量统计（上传/下载/双向）、进度条、NAT 展示、`tc` 限速、YAML 配置（`sysinfo -c` / `-r`）。
  Monthly traffic stats (up/down/both), progress bars, NAT display, `tc` throttling, YAML config (`sysinfo -c` / `-r`).

### Changed · 变更

- 配置统一为 YAML-only；废弃 `--nat`、`--traffic`、`--limit` 等旧 CLI 参数。
  Config is YAML-only; deprecated `--nat`, `--traffic`, `--limit` CLI flags.

### Usage · 用法示例

```bash
sysinfo -c /etc/sysinfo/config.yaml
sysinfo -r
sysinfo --reset-traffic
```
