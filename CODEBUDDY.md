# CODEBUDDY.md

This file provides guidance to CodeBuddy Code when working with code in this repository.

## Project Overview

sysinfo-cli is a lightweight Bash-based system status dashboard for Debian/Ubuntu. It displays real-time CPU/memory/disk/network info on SSH login (via `/etc/profile.d/` banner) and through an interactive `sysinfo` command. It also implements monthly traffic accounting and `tc`-based bandwidth throttling when traffic exceeds configurable thresholds.

## Commands

- **Run tests:** `bash tests/test_sysinfo.sh` (generates `tests/test_report.md`)
- **Single test:** The test script has no single-test mode. Test individual binaries directly: `./src/sysinfo.sh -h`, `timeout 3 ./src/sysinfo.sh`, `./src/sysinfo.sh -c /path/to/config.yaml`
- **Install locally:** `./install.sh` (installs deps + scripts to system paths, generates `/etc/sysinfo/config.yaml`)
- **Install with language:** `./install.sh --lang zh|en`
- **Uninstall:** `./uninstall.sh`
- **Lint:** No linter configured. Consider `shellcheck` for manual checks.

## Architecture

### Source layout

All **edits go in `src/` and `scripts/`**, not in the root wrappers.

| Path | Role |
|---|---|
| `src/sysinfo.sh` | CLI entry point. Parses args, loads YAML config, launches `watch` loop or one-shot render. |
| `src/sysinfo_core.sh` | Core engine (sourced, not exec'd). Data collection, traffic stats, `tc` throttling, dashboard rendering. |
| `src/sysinfo_banner.sh` | Lightweight one-shot SSH login banner — no traffic accounting or throttling. |
| `scripts/test_throttle.sh` | Throttle diagnostic (tc/gateway/IFB/qdisc checks) — for human triage, not a unit test. |
| `sysinfo.sh`, `sysinfo_core.sh`, `sysinfo_banner.sh`, `test_throttle.sh` | Root compat wrappers that delegate to `src/` and `scripts/`. |

### Sourcing model

`sysinfo_core.sh` is **sourced** into `sysinfo.sh` (via `watch ... source`). It both defines functions and runs top-level rendering code on source — there is no `return` guard for re-sourcing. Functions are redefined each time.

### Configuration flow

- Config is YAML-only, parsed with `yq eval`. Legacy CLI flags (`--nat`, `--traffic`, `--limit`) are deprecated.
- `-c`/`-r` flattens YAML into flat state files (`/etc/sysinfo-traffic`, `/etc/sysinfo-nat`) read by the core via `grep -o` field extraction (not a real JSON parser).
- `get_config()` tries the `-c` path first, then `/etc/sysinfo/config.yaml`, then hardcoded defaults.

### Privilege escalation

`run_privileged()` runs directly if EUID==0, else `sudo -n` (non-interactive). The core version falls back to interactive `sudo`. Used for all `tc`, `ip`, `modprobe`, and writes to `/etc/` and `/var/tmp/`.

### Internationalization

Bilingual English/Chinese. `detect_lang()` checks `/etc/sysinfo-lang` then locale vars. Labels use `: "${L_FOO:=default}"` parameter-default pattern.

### Throttling (safety-critical)

- Uses Linux `tc` with HTB + fq_codel for upload; IFB (`ifb_sysinfo0`) redirect for download.
- **Gateway guard:** `is_gateway_mode()` checks `net.ipv4.ip_forward`; throttling is skipped unless `force_gateway_throttle: true`.
- **Minimum rate floor:** Rates below 64 kbit are rejected to avoid breaking SSH.
- **Unknown qdisc protection:** `apply_rate_limit` refuses to overwrite non-default root qdiscs.
- **Idempotency:** State file `/var/tmp/sysinfo_throttle_state` (`ready`/`limited`) prevents redundant `tc` ops; synced against actual `tc` state each cycle.
- **Interface selection:** Only physical NICs (`en*`/`eth*`) on default route; skips virtual/bridge/tunnel interfaces.

### State file conventions

- `/etc/sysinfo*` — persistent config/state (root required)
- `/var/tmp/sysinfo_*` — per-user runtime state (speed deltas, throttle state)
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
