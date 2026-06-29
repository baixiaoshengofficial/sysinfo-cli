# Changelog

本文档记录 `sysinfo-cli` 的重要更新。

## [Unreleased] - 2026-06-26

### 变更
- 移除根目录兼容 wrapper（`sysinfo.sh`、`sysinfo_core.sh` 等），统一使用 `src/` 和 `scripts/` 目录。
- 更新 README / CODEBUDDY 文档，补充完整目录结构说明。
- 实时监控改为单 shell 刷新循环，降低 CPU 占用。
- `install.sh` 同时将 `sysinfo_core.sh` 安装到 `/usr/local/bin/` 与 `/etc/profile.d/`。

## [Unreleased] - 2026-03-02

### 新增
- 新增了 流量统计 (上传/下载,  双向/单向 统计, 百分比显示, 流量重置)
- 新增了 限速设置 (单向/双向)
- 新增了 NAT 端口设置

### 变更
- 配置方式已统一为 YAML-only，旧版 `--nat`、`--traffic`、`--limit` CLI 参数已废弃。
- 通过编辑 `/etc/sysinfo/config.yaml` 后执行 `sysinfo -r` 应用 NAT、流量统计和限速配置。

Examples:
  sysinfo -c /etc/sysinfo/config.yaml
  sysinfo -r
  sysinfo --reset-traffic