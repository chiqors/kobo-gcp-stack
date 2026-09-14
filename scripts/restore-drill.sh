#!/usr/bin/env bash
set -euo pipefail
: "${RESTORE_MONGO_URI:?set an isolated RESTORE_MONGO_URI}"
: "${MONGO_BACKUP_OBJECT:?set a gs:// backup object}"
[[ "$RESTORE_MONGO_URI" == *production* ]] && { echo 'Refusing a URI containing production' >&2; exit 1; }
work=$(mktemp -d /tmp/kobo-mongo-restore.XXXXXX)
trap 'find "$work" -type f -delete; rmdir "$work"' EXIT
gcloud storage cp "$MONGO_BACKUP_OBJECT" "$work/restore.archive.gz"
docker run --rm --network host -v "$work:/restore:ro" mongo:8.0 mongorestore --uri="$RESTORE_MONGO_URI" --archive=/restore/restore.archive.gz --gzip --drop
echo 'isolated MongoDB restore completed'
