#!/usr/bin/env bash
set -euo pipefail
command -v gcsfuse >/dev/null || { echo 'gcsfuse is missing from GCS_FUSE_IMAGE' >&2; exit 1; }
mkdir -p /mnt/media/kpi /mnt/media/kobocat
mountpoint -q /mnt/media && { echo 'media mount already exists'; tail -f /dev/null; }
gcsfuse --implicit-dirs --foreground --uid 1000 --gid 1000 --file-mode 0664 --dir-mode 0775 "${GCS_BUCKET_NAME}" /mnt/media
