# AGENT.md — AI / IDE context for sysinfo-cli

This file helps **any** coding agent (Cursor, Copilot, Claude Code, CodeBuddy, Windsurf, etc.) work on this repository. Keep changes minimal and match existing Bash style.

> 中文说明见 [README_zh.md](README_zh.md) · English: [README.md](README.md) · Changelog: [CHANGELOG.md](CHANGELOG.md)

---

## What this project is

**sysinfo-cli** is a lightweight **Bash** system dashboard for **Linux** (not macOS):

- **SSH login banner** — one-shot status on login (`/etc/profile.d/`, `/etc/zsh/zprofile`)
- **`sysinfo` command** — live refreshing monitor (in-place, no `watch` respawn)
- **Traffic accounting** + **`tc` throttling** when quota threshold is hit
- **NAT display**, **YAML config**, **Bark push notifications**

Target distros: Debian, Ubuntu, RHEL, Fedora, Alpine, Arch, openSUSE, Gentoo, etc.  
CLI command name: **`sysinfo`** · Repo / package name: **`sysinfo-cli`**

---

## Repository layout

```
sysinfo-cli/
├── src/                    # ← EDIT HERE
│   ├── sysinfo.sh          # CLI: args, config apply, live loop
│   ├── sysinfo_core.sh     # Engine: metrics, traffic, tc, render
│   ├── sysinfo_notify.sh   # Bark + rule engine (sourced on demand)
│   ├── sysinfo_banner.sh   # SSH login banner (bash)
│   └── sysinfo_banner_shim.sh
├── scripts/test_throttle.sh
├── tests/test_sysinfo.sh, server_validate.sh
├── install.sh, uninstall.sh
├── config.yaml.example
├── docs/                   # Static site (index.html, wiki.html, assets/)
├── Makefile
└── AGENT.md                # This file (committed)
```

**Do not commit:** `CODEBUDDY.md` (local CodeBuddy notes only, listed in `.gitignore`).

See also [docs/PROJECT_STRUCTURE.md](docs/PROJECT_STRUCTURE.md).

---

## Common commands

| Task | Command |
|------|---------|
| Help | `./src/sysinfo.sh -h` |
| One-shot dashboard | `timeout 3 ./src/sysinfo.sh` |
| Syntax check all scripts | `make syntax` |
| Unit tests | `make test` |
| Full validation | `make validate` |
| Install (keeps config) | `sudo ./install.sh` |
| Install + reset config | `sudo ./install.sh --overwrite-config` |
| Reload system config | `sudo sysinfo -r` |
| Notify test / cron check | `sysinfo --notify-test` / `sysinfo --notify-check` |
| Docs preview | `make docs-serve` (port `8099`, auto-frees if busy) |
| Docker test image | `make docker-test` |
| **Multi-distro install smoke test** | `make docker-test-distros` (uses `scripts/docker-cmd.sh`; `.docker-sudo` or `docker` group) |
| **Build per-distro install images** | `make docker-build-distros` (`docker/Dockerfile.install-test`, 8 distros incl. OpenWrt) |

---

## Architecture (short)

1. **`sysinfo.sh`** sources **`sysinfo_core.sh`** (and optionally **`sysinfo_notify.sh`**).
2. Config is **YAML-only**, parsed with **mikefarah `yq`** at `/usr/local/bin/yq` when present.
3. **`-c` / `-r`** flatten YAML into state files under `/etc/` (`sysinfo-traffic.json`, `sysinfo-nat`, `sysinfo-lang`). Core reads them via `grep` extraction (not a JSON parser).
4. **`get_applied_config()`** reads only from the file being applied — no silent fallback to `~/.config` during `-c`/`-r`.
5. **Throttling** uses Linux `tc` (HTB + fq_codel upload, IFB download). Skips gateway hosts unless `network.force_gateway_throttle: true`. Min rate 64 kbit.
6. **Notifications**: edge-triggered rules + cooldown; state in `/var/tmp/sysinfo-notify-state-<user>`.

---

## Install script notes

- **`require_linux()`** — rejects macOS.
- **`detect_pkg_manager()`** + **`pkg_install()`** — iproute2 / iproute / ip-full+tc-full (opkg), curl/wget.
- **`detect_yq_asset()`** + **`install_yq_binary()`** — yq per `uname -m`.
- **`download_file()`** — curl or wget for scripts and yq.
- Remote install: `curl …/install.sh | bash` (no full git checkout).

---

## Coding conventions

- Bash 4+ style; `#!/bin/bash`; edit **`src/`** not installed copies under `/usr/local/bin/`.
- **Minimal diffs** — no drive-by refactors or extra abstractions.
- No `set -e` in production scripts; use `2>/dev/null` / fallbacks.
- Avoid **GNU-only** tools where easy (`grep -oP` → `sed`).
- i18n: `SYSINFO_LANG` → `/etc/sysinfo-lang` → locale; labels via `${L_FOO:=default}`.
- Tests: `bash tests/test_sysinfo.sh`; throttle diag is `scripts/test_throttle.sh` (manual, not unit test).

---

## Installed paths (after `install.sh`)

| Path | Role |
|------|------|
| `/usr/local/bin/sysinfo` | Wrapper → `sysinfo-cli.sh` |
| `/etc/sysinfo/config.yaml` | Main config |
| `/etc/sysinfo-lang` | UI language from `display.language` |
| `/etc/sysinfo-traffic.json` | Traffic + throttle state |
| `/usr/local/lib/sysinfo/sysinfo_banner.sh` | Login banner |

---

## When fixing user reports

| Symptom | Likely cause |
|---------|----------------|
| `language: zh` ignored after `-r` | Broken/wrong-arch `yq`, or config path shadowing |
| `yq: Exec format error` | amd64 yq on ARM — reinstall via `install.sh` |
| No SSH banner | scp/sftp session, or zsh hook missing — re-run `install.sh` |
| Throttle not applied | Gateway `ip_forward`, missing `tc`, or not root |
| No push alerts | `notify.enabled`, `bark.key`, or run `--notify-test` first |

---

## Docs / marketing site

- `docs/index.html` — bilingual landing (data-en / data-zh + JS toggle)
- `docs/wiki.html` + `wiki.css` + `wiki.js`
- Assets: `docs/assets/` (e.g. Bark iPhone mockup)

Do not edit generated test artifacts under `tests/*.log` or `tests/test_report.md`.

---

## Git / release

- Update **[CHANGELOG.md](CHANGELOG.md)** (bilingual entries) for user-visible changes.
- **Do not** add `CODEBUDDY.md` to commits.
- User asks before creating git commits or pushing.
