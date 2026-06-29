#!/bin/bash

run_privileged() {
    if [ "$EUID" -eq 0 ]; then
        "$@"
    else
        sudo -n "$@"
    fi
}

echo "Uninstalling sysinfo-cli..."

# Remove installed scripts
run_privileged rm -f /etc/profile.d/sysinfo.sh
run_privileged rm -f /etc/profile.d/sysinfo_core.sh
run_privileged rm -f /etc/profile.d/sysinfo-banner.sh
run_privileged rm -f /etc/profile.d/sysinfo-banner-bash.sh
run_privileged rm -f /etc/profile.d/sysinfo_banner.sh
run_privileged rm -rf /usr/local/lib/sysinfo

# Remove zsh zprofile hook added by install.sh
if [ -f /etc/zsh/zprofile ]; then
    run_privileged sed -i '/# sysinfo-cli banner/,+1d' /etc/zsh/zprofile 2>/dev/null || true
fi

# Remove sysinfo commands
run_privileged rm -f /usr/local/bin/sysinfo
run_privileged rm -f /usr/local/bin/sysinfo-cli.sh
run_privileged rm -f /usr/local/bin/sysinfo_core.sh
run_privileged rm -f /usr/local/bin/sysinfo_notify.sh

# Remove configuration files
run_privileged rm -f /etc/sysinfo-nat
run_privileged rm -f /etc/sysinfo-traffic /etc/sysinfo-traffic.json
run_privileged rm -f /etc/sysinfo-lang
run_privileged rm -rf /etc/sysinfo
run_privileged rm -f /var/tmp/sysinfo_net_stats_*
run_privileged rm -f /var/tmp/sysinfo_throttle_state
run_privileged rm -f /var/tmp/sysinfo-notify-state

echo "Done! sysinfo-cli has been completely removed."

echo ""
echo "To reinstall, run:"
echo "  sudo ./install.sh"
