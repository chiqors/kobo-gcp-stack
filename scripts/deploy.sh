#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
action=${1:-up}
cd "$root"
source .env
./scripts/render-config.sh .env
./scripts/preflight-host.sh
profiles=()
[[ "${DEPLOY_MODE:-local}" == local ]] && profiles+=(--profile local-db)
[[ "${CLOUD_SQL_ENABLED:-0}" == 1 ]] && profiles+=(--profile cloud-sql)
[[ "${GCS_FUSE_ENABLED:-0}" == 1 ]] && profiles+=(--profile gcsfuse)
[[ "${LOCAL_REDIS_MAIN:-0}" == 1 ]] && profiles+=(--profile local-redis-main)
case "$action" in
  up)
    if [[ "${GCS_FUSE_ENABLED:-0}" == 1 ]]; then
      docker compose --env-file .env -f compose/compose.yaml --profile gcsfuse up -d gcsfuse
      for _ in $(seq 1 60); do
        [[ "$(findmnt -n -o FSTYPE --target runtime/media-mount 2>/dev/null | tail -1 || true)" == fuse.gcsfuse ]] && break
        sleep 2
      done
      [[ "$(findmnt -n -o FSTYPE --target runtime/media-mount 2>/dev/null | tail -1 || true)" == fuse.gcsfuse ]] || {
        echo 'GCS FUSE bucket mount did not become ready' >&2
        exit 1
      }
    fi
    docker compose --env-file .env -f compose/compose.yaml "${profiles[@]}" up -d
    if [[ "${GCS_FUSE_ENABLED:-0}" == 1 ]]; then
      docker compose --env-file .env -f compose/compose.yaml "${profiles[@]}" \
        up -d --force-recreate kpi worker worker-low worker-long worker-kobocat beat nginx
    fi
    ;;
  down) docker compose --env-file .env -f compose/compose.yaml "${profiles[@]}" down ;;
  pull) docker compose --env-file .env -f compose/compose.yaml "${profiles[@]}" pull ;;
  config) docker compose --env-file .env -f compose/compose.yaml config ;;
  *) echo "usage: $0 {up|down|pull|config}" >&2; exit 2 ;;
esac
