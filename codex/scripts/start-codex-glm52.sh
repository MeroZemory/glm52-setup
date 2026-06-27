#!/usr/bin/env bash
# Start proxy then launch codex with glm52 profile (Linux/macOS)
set -euo pipefail
"$(dirname "${BASH_SOURCE[0]}")/start-proxy.sh"
exec codex --profile glm52 "$@"