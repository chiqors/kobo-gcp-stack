#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
command -v docker >/dev/null || { echo 'Install Docker Engine and Compose v2 first' >&2; exit 1; }
mkdir -p "$root/runtime"/{config/{nginx,enketo},logs/{kpi,nginx},static,media-mount/{kpi,kobocat},secrets/google}
chmod 700 "$root/runtime/secrets" "$root/runtime/secrets/google"
chmod 770 "$root/runtime/media-mount" "$root/runtime/media-mount/kpi" "$root/runtime/media-mount/kobocat"
gcs_enabled=$(sed -n 's/^GCS_FUSE_ENABLED=//p' "$root/.env" 2>/dev/null | tail -1)
if [[ "$gcs_enabled" == 1 && $(uname -s) != Linux ]]; then
  echo 'warning: GCS FUSE can be configured here but deployed only on a Linux host' >&2
fi
if [[ "$gcs_enabled" == 1 && "$(findmnt -no PROPAGATION --target "$root/runtime/media-mount" 2>/dev/null | tail -1 || true)" != shared ]]; then
  echo "Run: sudo mount --bind '$root/runtime/media-mount' '$root/runtime/media-mount'" >&2
  echo "Then: sudo mount --make-shared '$root/runtime/media-mount'" >&2
  echo 'Shared mount propagation is required for containerized GCS FUSE.' >&2
fi
echo 'host directories initialized'
