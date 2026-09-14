#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
"$root/tests/compose-config.sh"
"$root/scripts/smoke-test.sh"
echo 'upgrade smoke checks passed'
