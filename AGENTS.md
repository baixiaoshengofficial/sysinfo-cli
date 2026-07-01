# Repository Guidelines

This is the single contributor and coding-agent guide for **sysinfo-cli**. Keep it concise, practical, and aligned with the current Bash codebase.

For project context and philosophy, see `README.md` / `README_zh.md`; for release notes, see `CHANGELOG.md`.

## What This Project Is

**sysinfo-cli** is a lightweight **Bash** system-status dashboard for **Linux** SSH login and live terminal monitoring.

Core capabilities:

- SSH login banner via `/etc/profile.d` and zsh profile hooks.
- Real-time `sysinfo` monitor without `watch` respawning.
- Traffic accounting with monthly quotas.
- Linux `tc` throttling when quota thresholds are reached.
- NAT display.
- Bark push notifications and rule engine.
- Bilingual English / Chinese UI.

Target distros include Debian, Ubuntu, RHEL, Fedora, Alpine, Arch, openSUSE, Gentoo, OpenWrt, and similar Linux systems. macOS is useful for editing, but it is not a supported runtime target.

## Project Structure & Module Organization

```text
sysinfo-cli/
├── src/                       # Source of truth; edit here, not installed copies
│   ├── sysinfo.sh             # CLI entry: args, -c/-r config apply, live loop
│   ├── sysinfo_core.sh        # Engine: metrics, traffic, tc throttling, rendering
│   ├── sysinfo_notify.sh      # Bark push notifications + rule engine
│   ├── sysinfo_banner.sh      # SSH login banner (bash /etc/profile.d)
│   └── sysinfo_banner_shim.sh
├── scripts/                   # Development aids (docker-cmd.sh, test_throttle.sh)
├── tests/                     # test_sysinfo.sh, server_validate.sh, docker_distros.sh
├── docs/                      # Static site (index.html, wiki.html, wiki.css/js, assets/)
├── docker/                    # Per-distro Dockerfiles and build helpers
├── install.sh / uninstall.sh  # One-shot installer and remover
├── config.yaml.example
├── Dockerfile
├── Makefile
└── AGENTS.md                  # This file
```

Do not commit local scratch files such as `CODEBUDDY.md` or generated test artifacts under `tests/*.log`.

## Runtime & Installed Paths

Runtime config lives in `/etc/sysinfo/config.yaml`; UI language lives in `/etc/sysinfo-lang`.

| Installed artifact | Path |
|-------------------|------|
| CLI wrapper | `/usr/local/bin/sysinfo` |
| Main config | `/etc/sysinfo/config.yaml` |
| UI language marker | `/etc/sysinfo-lang` |
| Traffic/throttle state | `/etc/sysinfo-traffic.json` |
| Flat traffic config | `/etc/sysinfo-traffic` |
| NAT mappings | `/etc/sysinfo-nat` |
| Login banner | `/usr/local/lib/sysinfo/sysinfo_banner.sh` |

## Build, Test, and Development Commands

All common commands are dispatched through the `Makefile`.

| Task | Command | Notes |
|------|---------|-------|
| Show all targets | `make` | Help with per-target descriptions |
| Run one-shot dashboard | `make run` | Uses `RUN_TIMEOUT`, default 5s |
| Run live interactive monitor | `make run-live` | Ctrl+C to exit |
| CLI help | `make help-cli` | Runs `src/sysinfo.sh -h` |
| Bash syntax check | `make syntax` | Covers `src/*.sh`, installer, scripts, tests |
| Unit tests | `make test` | Runs `tests/test_sysinfo.sh` |
| Full validation | `make validate` | Runs `tests/server_validate.sh` |
| Install (keep config) | `sudo ./install.sh` | Linux target |
| Install + reset config | `sudo ./install.sh --overwrite-config` | Backs up old config |
| Reload system config | `sudo sysinfo -r` | Applies `/etc/sysinfo/config.yaml` |
| Throttle diagnostic | `bash scripts/test_throttle.sh` | Manual diagnostic |
| Notification test | `sysinfo --notify-test` | Requires configured Bark key |
| Notification rule check | `sysinfo --notify-check` | Cron-friendly |
| HTML docs preview | `make docs-serve` | Serves on port 8099 and auto-frees if busy |
| Single-distro Docker test | `make docker-test` | Docker required |
| Multi-distro smoke test | `make docker-test-distros` | Uses `scripts/docker-cmd.sh` |
| Build per-distro images | `make docker-build-distros` | Includes OpenWrt |
| Deploy locally | `make deploy` | test -> validate -> install |
| Ship | `make push` | Pushes current branch |

## Architecture Overview

`sysinfo.sh` is the CLI entrypoint. It sources `sysinfo_core.sh` for rendering, metrics, traffic state, and throttling. It optionally sources `sysinfo_notify.sh` for Bark notifications.

Configuration is YAML-only and parsed with mikefarah `yq`, preferring `/usr/local/bin/yq`. The installer downloads the correct yq binary per `uname -m`.

`-c` and `-r` flatten YAML into plain state files under `/etc/`. The core reads those state files with simple `grep` extraction rather than a JSON parser. During config application, `get_applied_config()` reads only from the file being applied so `-c` / `-r` cannot silently fall back to `~/.config`.

Throttling uses Linux `tc`: HTB + fq_codel for upload, IFB for download. Gateway hosts are skipped unless `network.force_gateway_throttle: true`; throttle rates are floored at 64 kbit.

Notifications are edge-triggered with cooldown. State is kept in `/var/tmp/sysinfo-notify-state-<user>`.

## Install Script Notes

Important installer functions:

- `require_linux()` rejects unsupported non-Linux runtime installs.
- `detect_pkg_manager()` and `pkg_install()` handle apt, dnf, yum, opkg, apk, pacman, zypper, and emerge.
- `detect_yq_asset()` and `install_yq_binary()` select the correct yq binary for amd64, arm64, or arm.
- `download_file()` uses curl or wget for remote install paths.

Remote install via `curl .../install.sh | bash` must work without a full git checkout.

## Coding Style & Naming Conventions

- Bash 4+, `#!/bin/bash` shebang.
- Edit `src/` only; never edit installed copies under `/usr/local/bin`, `/usr/local/lib`, or `/etc/profile.d`.
- Keep diffs minimal. Avoid drive-by refactors and unnecessary abstractions.
- Use 2-space indentation.
- Do not add `set -e` to production scripts; prefer explicit checks, `2>/dev/null`, and fallbacks.
- Prefer portable shell tools where reasonable: `sed` over `grep -oP`, avoid GNU-only options when a short portable alternative exists.
- Command names use kebab-case, such as `sysinfo-cli` and `docker-cmd.sh`.
- Environment variables use `SCREAMING_SNAKE_CASE`, such as `SYSINFO_CONFIG` and `SYSINFO_LANG`.
- UI labels use `${L_FOO:=default}` defaults.
- Language fallback chain: `SYSINFO_LANG` -> `/etc/sysinfo-lang` -> locale.

## Testing Guidelines

Tests are plain Bash scripts driven by `make`.

Primary suites:

- `tests/test_sysinfo.sh`: help text, dashboard output, YAML config parsing, traffic counters, throttle diagnostics.
- `tests/server_validate.sh`: stricter production-style validation.
- `tests/docker_distros.sh`: multi-distro install smoke test.
- `scripts/test_throttle.sh`: manual throttle diagnostic, not a unit test.

All shell scripts should pass `make syntax` before submitting. On macOS, some Linux runtime checks may fail because `/proc`, `timeout`, `free`, `tc`, or yq may be missing; use Docker or a Linux host for runtime validation.

## Commit & Pull Request Guidelines

Follow the imperative, short-subject style used in history:

- `Add OpenWrt support and streamline Docker multi-distro testing.`
- `Fix yq install on ARM by downloading the correct CPU binary.`
- `Fix sysinfo -r ignoring display.language in /etc/sysinfo/config.yaml.`

User-visible changes require bilingual entries under `[Unreleased]` in `CHANGELOG.md`.

Pull requests should describe what changed and why, the distros/devices tested, and any backward incompatibility around config keys, CLI flags, or install paths.

Ask before creating commits or pushing unless the user explicitly requested it.

## Security & Configuration Tips

- `install.sh` is the only entry point that should write under `/etc/` and `/usr/local/`.
- `scripts/docker-cmd.sh` may read `.docker-sudo` or `DOCKER_SUDO_PASSWORD`; never commit real passwords.
- Bark keys and notification tokens live in `/etc/sysinfo/config.yaml`; do not log or commit them.
- Throttling modifies `tc` qdiscs. Validate with `scripts/test_throttle.sh` on a non-production host first.

## Common Troubleshooting

| Symptom | Likely cause |
|---------|--------------|
| `language: zh` ignored after `-r` | Broken/wrong-arch yq, or config path shadowing |
| `yq: Exec format error` | amd64 yq on ARM; reinstall with `install.sh` |
| No SSH banner | scp/sftp session, missing zsh hook, or non-login shell |
| Throttle not applied | Gateway `ip_forward`, missing `tc`, insufficient privileges |
| No push alerts | `notify.enabled`, missing `bark.key`, or `--notify-test` not run |
| CPU core count wrong | Check `/proc/cpuinfo`, `/sys/devices/system/cpu/online`, and container CPU limits |

## Docs Site

- `docs/index.html`: bilingual landing page.
- `docs/wiki.html`, `docs/wiki.css`, `docs/wiki.js`: documentation wiki.
- `docs/assets/`: visual assets.

Keep docs edits scoped and avoid mixing site redesigns into unrelated code fixes.
