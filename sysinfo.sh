#!/bin/bash
# Compatibility wrapper for the relocated CLI implementation.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/src/sysinfo.sh" "$@"
