#!/usr/bin/env bash
# Make the shared media directory its own shared mount so that GCS FUSE mounts
# propagate into the application containers. Idempotent; safe to run every boot.
#
# systemd runs this before docker.service (kobo-media-bind.service) so the
# propagation chain exists before any container is started. Requires root.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
target="$root/runtime/media-mount"

[[ -d "$target" ]] || { echo "Missing media directory: $target" >&2; exit 1; }

# Only create the self-bind when the directory is not already its own mount.
# `findmnt --target` returns the enclosing mount, which is `/` when there is no
# dedicated bind, so comparing the reported TARGET against the path is reliable.
own=$(findmnt -no TARGET --target "$target" 2>/dev/null | tail -1 || true)
if [[ "$own" != "$target" ]]; then
  mount --bind "$target" "$target"
fi
mount --make-shared "$target"

propagation=$(findmnt -no PROPAGATION --target "$target" 2>/dev/null | tail -1 || true)
[[ "$propagation" == shared ]] || {
  echo "Failed to make $target a shared mount (propagation: ${propagation:-unknown})" >&2
  exit 1
}
echo "Media directory $target is shared"
