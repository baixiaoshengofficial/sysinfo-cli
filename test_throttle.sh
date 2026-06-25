#!/bin/bash
# Compatibility wrapper for the relocated throttle diagnostic script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/scripts/test_throttle.sh" "$@"
