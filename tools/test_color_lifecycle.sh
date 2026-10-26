#!/usr/bin/env bash
# Compatibility entry point for the 0.3.1 regression command.
set -euo pipefail
exec bash "$(dirname "$0")/test_native_lifecycle.sh"
