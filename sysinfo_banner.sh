#!/bin/bash
# Compatibility wrapper for the relocated SSH banner implementation.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/src/sysinfo_banner.sh" "$@"
