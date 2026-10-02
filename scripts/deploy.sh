#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
action=${1:-up}
cd "$root"
source .env
./scripts/render-config.sh .env
./scripts/preflight-host.sh
profiles=()

media_ready() {
  local d
  for d in runtime/media-mount/kpi runtime/media-mount/kobocat; do
    [[ "$(findmnt -n -o FSTYPE --target "$d" 2>/dev/null | tail -1 || true)" == fuse.gcsfuse ]] || return 1
    # findmnt still reports fuse.gcsfuse for a stale mount, so probe liveness.
    stat "$d" >/dev/null 2>&1 || return 1
  done
}

# GCS FUSE mounts must be present before the application containers are created.
# A container that binds a live FUSE mount keeps pointing at that mount forever;
# it only follows later mounts if it bound a plain directory (slave propagation).
# So after any (re)mount the media consumers must be recreated.
wait_for_media() {
  local _
  for _ in $(seq 1 60); do
    if media_ready; then return 0; fi
    sleep 2
  done
  echo 'GCS FUSE media mounts did not become ready' >&2
  return 1
}

recreate_media_consumers() {
  docker compose --env-file .env -f compose/compose.yaml "${profiles[@]}" \
    up -d --force-recreate kpi worker worker-low worker-long worker-kobocat beat nginx
}

[[ "${DEPLOY_MODE:-local}" == local ]] && profiles+=(--profile local-db)
[[ "${CLOUD_SQL_ENABLED:-0}" == 1 ]] && profiles+=(--profile cloud-sql)
[[ "${GCS_FUSE_ENABLED:-0}" == 1 ]] && profiles+=(--profile gcsfuse)
[[ "${LOCAL_REDIS_MAIN:-0}" == 1 ]] && profiles+=(--profile local-redis-main)

case "$action" in
  up)
    if [[ "${GCS_FUSE_ENABLED:-0}" == 1 ]]; then
      docker compose --env-file .env -f compose/compose.yaml --profile gcsfuse up -d gcsfuse
      wait_for_media
    fi
    docker compose --env-file .env -f compose/compose.yaml "${profiles[@]}" up -d
    if [[ "${GCS_FUSE_ENABLED:-0}" == 1 ]]; then
      recreate_media_consumers
    fi
    ;;
  remount)
    [[ "${GCS_FUSE_ENABLED:-0}" == 1 ]] || { echo 'GCS_FUSE_ENABLED is not 1' >&2; exit 2; }
    docker compose --env-file .env -f compose/compose.yaml --profile gcsfuse up -d --force-recreate gcsfuse
    wait_for_media
    recreate_media_consumers
    ;;
  down) docker compose --env-file .env -f compose/compose.yaml "${profiles[@]}" down ;;
  pull) docker compose --env-file .env -f compose/compose.yaml "${profiles[@]}" pull ;;
  config) docker compose --env-file .env -f compose/compose.yaml "${profiles[@]}" config ;;
  *) echo "usage: $0 {up|remount|down|pull|config}" >&2; exit 2 ;;
esac
