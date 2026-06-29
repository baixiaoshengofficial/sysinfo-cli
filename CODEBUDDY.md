# CODEBUDDY.md

This file provides guidance to CodeBuddy Code when working with code in this repository.

## Project Overview

sysinfo-cli is a lightweight Bash-based system status dashboard for Debian/Ubuntu. It displays real-time CPU/memory/disk/network info on SSH login (via `/etc/profile.d/` for bash and `/etc/zsh/zprofile` for zsh) and through an interactive `sysinfo` command. It also implements monthly traffic accounting, `tc`-based bandwidth throttling when traffic exceeds configurable thresholds, and modular push notifications (Bark).

## Commands

- **Run tests:** `bash tests/test_sysinfo.sh` (generates `tests/test_report.md`)
- **Single test:** The test script has no single-test mode. Test individual binaries directly: `./src/sysinfo.sh -h`, `timeout 3 ./src/sysinfo.sh`, `./src/sysinfo.sh -c /path/to/config.yaml`
- **Install locally:** `./install.sh` (installs deps + scripts to system paths, generates `/etc/sysinfo/config.yaml`)
- **Install with language:** `./install.sh --lang zh|en`
- **Reset config on reinstall:** `./install.sh --overwrite-config` (default keeps existing config; old one is backed up)
- **Test notifications:** `./src/sysinfo.sh --notify-test` (channel) / `--notify-check` (evaluate rules)
- **Uninstall:** `./uninstall.sh`
- **Lint:** No linter configured. Consider `shellcheck` for manual checks.

## Architecture

### Source layout

All **edits go in `src/` and `scripts/`**. There are no root-level wrappers; `install.sh`/`uninstall.sh` deploy `src/` to system paths.

| Path | Role |
|---|---|
| `src/sysinfo.sh` | CLI entry point. Parses args, loads YAML config, runs the in-place live loop or a one-shot render. |
| `src/sysinfo_core.sh` | Core engine (sourced, not exec'd). Data collection, traffic stats, `tc` throttling, dashboard rendering. |
| `src/sysinfo_notify.sh` | Push notification module (sourced on demand). Bark provider + rule engine (cpu/net/nic/throttle/disk) with edge+cooldown dedup. |
| `src/sysinfo_banner.sh` | Lightweight one-shot SSH login banner (bash renderer) — no traffic accounting or throttling. |
| `src/sysinfo_banner_shim.sh` | POSIX shim sourced by `/etc/profile.d/` (bash) and `/etc/zsh/zprofile` (zsh); detects login shell then execs the bash banner. |
| `scripts/test_throttle.sh` | Throttle diagnostic (tc/gateway/IFB/qdisc checks) — for human triage, not a unit test. |

### Rendering / sourcing model

`sysinfo_core.sh` is **sourced** into `sysinfo.sh`. It defines functions plus `sysinfo_render` (wrapped so sourcing has no side effects). Interactive terminals use `sysinfo_live_loop` (alternate screen + in-place line rewrite, sourced once) instead of `watch`, to avoid respawning bash and re-sourcing every tick. `sysinfo_notify.sh` is sourced after the core so `sysinfo_render` can call `notify_check` at the end of each render.

### Configuration flow

- Config is YAML-only, parsed with `yq eval`. Legacy CLI flags (`--nat`, `--traffic`, `--limit`) are deprecated.
- `-c`/`-r` flattens YAML into state files (`/etc/sysinfo-traffic.json`, `/etc/sysinfo-nat`) read by the core via `grep -o` field extraction (not a real JSON parser).
- `get_config()` tries the `-c` path first, then the user/system `config.yaml` (`~/.config/sysinfo/config.yaml` for non-root, else `/etc/sysinfo/config.yaml`; override with `SYSINFO_CONFIG`), then hardcoded defaults. `get_config_list()` reads YAML sequences (e.g. `disk.paths`).

### Privilege escalation

`run_privileged()` runs directly if EUID==0, else `sudo -n` (non-interactive). The core version falls back to interactive `sudo`. Used for all `tc`, `ip`, `modprobe`, and writes to `/etc/` and `/var/tmp/`.

### Internationalization

Bilingual English/Chinese. Priority: explicit `SYSINFO_LANG` env (exported by the CLI from `display.language`) → `/etc/sysinfo-lang` → locale vars. `apply_config` (`-c`/`-r`) persists `display.language` to `/etc/sysinfo-lang` (or removes it for `auto`). Labels use `: "${L_FOO:=default}"` parameter-default pattern.

### Notifications

- `notify_check` runs at the end of `sysinfo_render` and via `sysinfo --notify-check` (cron entrypoint, which primes a net sample first so the `nic` rate rule works on a single invocation).
- Providers live in `sysinfo_notify.sh` (`notify_send_bark` → `notify_dispatch`); add a provider by extending `notify_dispatch`.
- Rules: `cpu`/`net`/`disk` (% threshold, `disk.paths` optional), `nic` (per-direction % of custom rate or NIC link speed, `mode` upload/download/both), `throttle` (active state).
- Edge-triggered + cooldown dedup; state in `/var/tmp/sysinfo-notify-state-<user>` (per-user to avoid root/user ownership clashes in sticky `/var/tmp`).

### Throttling (safety-critical)

- Uses Linux `tc` with HTB + fq_codel for upload; IFB (`ifb_sysinfo0`) redirect for download.
- **Gateway guard:** `is_gateway_mode()` checks `net.ipv4.ip_forward`; throttling is skipped unless `force_gateway_throttle: true`.
- **Minimum rate floor:** Rates below 64 kbit are rejected to avoid breaking SSH.
- **Unknown qdisc protection:** `apply_rate_limit` refuses to overwrite non-default root qdiscs.
- **Idempotency:** State file `/var/tmp/sysinfo_throttle_state` (`ready`/`limited`) prevents redundant `tc` ops; synced against actual `tc` state each cycle.
- **Interface selection:** Only physical NICs (`en*`/`eth*`) on default route; skips virtual/bridge/tunnel interfaces.

### State file conventions

- `/etc/sysinfo*` — persistent config/state, root required (`config.yaml`, `sysinfo-traffic.json`, `sysinfo-nat`, `sysinfo-lang`)
- `/var/tmp/sysinfo_*` / `/var/tmp/sysinfo-notify-state-<user>` — per-user runtime state (speed deltas, throttle state, notification dedup/cooldown)
- Banner uses separate `/var/tmp/sysinfo_banner_net_stats_*` files to avoid clashing with the monitor.

## Key runtime dependencies

- `yq` (mikefarah/yq) — YAML parsing (downloaded by `install.sh`)
- `iproute2` (`tc`, `ip`) — traffic control / interface introspection
- `bc` (optional, `awk` fallback) — large-number math

## Coding conventions

- All scripts `#!/bin/bash`; bashisms used freely (`[[ ]]`, arrays, `<<<`, `(( ))`)
- Functions use `local` variables
- No `set -e`/`set -u` in production scripts; per-command fallbacks (`2>/dev/null`, `|| echo "fallback"`)
- `timeout 1` guards slow external commands
- JSON hand-assembled via string concatenation (no serializer)
- UTF-8 aware column alignment: `display_width()` counts non-ASCII as width 2
