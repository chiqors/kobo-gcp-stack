#!/usr/bin/env bash
set -euo pipefail
command -v gcsfuse >/dev/null || { echo 'gcsfuse is missing from GCS_FUSE_IMAGE' >&2; exit 1; }
mkdir -p /mnt/media
filesystem=$(findmnt -n -o FSTYPE --target /mnt/media 2>/dev/null | tail -1 || true)
if [[ "$filesystem" == fuse.gcsfuse ]]; then
  echo 'GCS bucket is already mounted'
  tail -f /dev/null
fi
exec gcsfuse --implicit-dirs --foreground --uid 1000 --gid 1000 \
  --file-mode 0664 --dir-mode 0775 --o allow_other \
  "${GCS_BUCKET_NAME}" /mnt/media
