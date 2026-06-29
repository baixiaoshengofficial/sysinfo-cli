# Project Structure (sysinfo-cli)

```
sysinfo-cli/
├── src/                        # Application source (edit here)
│   ├── sysinfo.sh              # CLI entry point
│   ├── sysinfo_core.sh         # Core engine
│   ├── sysinfo_notify.sh       # Push notification module (Bark)
│   ├── sysinfo_banner.sh       # SSH login banner (bash renderer)
│   └── sysinfo_banner_shim.sh  # Login banner shim (bash + zsh)
├── scripts/                    # Utilities
│   └── test_throttle.sh        # Throttle diagnostic
├── tests/                      # Test suites
│   ├── test_sysinfo.sh
│   └── server_validate.sh
├── install.sh                  # Install / update (sudo)
├── uninstall.sh
└── config.yaml.example
```

## Quick commands

```bash
./src/sysinfo.sh -h                 # Help
timeout 3 ./src/sysinfo.sh          # One-shot dashboard
bash tests/server_validate.sh       # Full validation
sudo ./install.sh                   # Install or update
```

## Installed layout (after `install.sh`)

| Path | Purpose |
|------|---------|
| `/usr/local/bin/sysinfo` | Wrapper → `sysinfo-cli.sh` |
| `/usr/local/bin/sysinfo-cli.sh` | CLI (copy of `src/sysinfo.sh`) |
| `/usr/local/bin/sysinfo_core.sh` | Core (co-installed for discovery) |
| `/usr/local/bin/sysinfo_notify.sh` | Push notification module |
| `/usr/local/lib/sysinfo/sysinfo_banner.sh` | SSH banner renderer (bash) |
| `/etc/profile.d/sysinfo-banner.sh` | Login banner shim (sourced by bash) |
| `/etc/profile.d/sysinfo_core.sh` | Core (profile.d legacy path) |
| `/etc/zsh/zprofile` | Banner hook appended for zsh login shells |
| `/etc/sysinfo/config.yaml` | System configuration |
| `/etc/sysinfo-lang` | Persisted UI language (from `display.language`) |
| `/etc/sysinfo-traffic.json` | Traffic counters + throttle state |
| `/etc/sysinfo-nat` | Active NAT mappings (for display) |
| `/var/tmp/sysinfo-notify-state-<user>` | Per-user notification dedup/cooldown state |
