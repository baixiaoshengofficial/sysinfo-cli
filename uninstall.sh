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
run_privileged rm -f /etc/profile.d/sysinfo_banner.sh

# Remove sysinfo commands
run_privileged rm -f /usr/local/bin/sysinfo
run_privileged rm -f /usr/local/bin/sysinfo-cli.sh

# Remove configuration files
run_privileged rm -f /etc/sysinfo-nat
run_privileged rm -f /etc/sysinfo-traffic /etc/sysinfo-traffic.json
run_privileged rm -f /etc/sysinfo-lang
run_privileged rm -rf /etc/sysinfo
run_privileged rm -f /var/tmp/sysinfo_net_stats_*
run_privileged rm -f /var/tmp/sysinfo_throttle_state

echo "Done! sysinfo-cli has been completely removed."

echo ""
echo "To reinstall, run:"
echo "  bash ./install.sh"
echo "Or for direct installation, copy src/sysinfo.sh to /usr/local/bin/sysinfo-cli.sh"
echo "and src/sysinfo_core.sh/src/sysinfo_banner.sh to /etc/profile.d/."
