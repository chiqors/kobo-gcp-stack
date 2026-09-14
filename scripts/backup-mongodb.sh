#!/usr/bin/env bash
set -euo pipefail
: "${MONGO_DB_URL:?set MONGO_DB_URL}"
: "${MONGO_BACKUP_BUCKET:?set MONGO_BACKUP_BUCKET}"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
archive="mongo-formhub-${stamp}.archive.gz"
work=$(mktemp -d /tmp/kobo-mongo-backup.XXXXXX)
trap 'find "$work" -type f -delete; rmdir "$work"' EXIT
docker run --rm --network host -v "$work:/backup" mongo:8.0 mongodump --uri="$MONGO_DB_URL" --archive="/backup/$archive" --gzip
gcloud storage cp "$work/$archive" "gs://$MONGO_BACKUP_BUCKET/mongodb/$archive"
echo "uploaded gs://$MONGO_BACKUP_BUCKET/mongodb/$archive"
