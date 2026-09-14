#!/usr/bin/env bash
set -euo pipefail
mkdir -p /media/kpi /media/kobocat
if [[ "${GCS_FUSE_ENABLED:-0}" == 1 ]]; then
  mountpoint -q /media || { echo 'GCS media mount is not mounted; refusing startup' >&2; exit 1; }
fi
for d in /media/kpi /media/kobocat; do
  test -w "$d" || { echo "$d is not writable" >&2; exit 1; }
done
probe="/media/kpi/.kobo-storage-preflight-$$"
trap 'rm -f "$probe" "$probe.renamed"' EXIT
printf 'kobo-storage-preflight' > "$probe"
[[ "$(cat "$probe")" == kobo-storage-preflight ]] || { echo 'Media read probe failed' >&2; exit 1; }
mv "$probe" "$probe.renamed"
[[ "$(cat "$probe.renamed")" == kobo-storage-preflight ]] || { echo 'Media rename probe failed' >&2; exit 1; }
rm "$probe.renamed"
echo 'preflight passed'
