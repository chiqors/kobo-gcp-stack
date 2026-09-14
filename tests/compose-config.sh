#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
"$root/scripts/render-config.sh" "$root/.env.example"
docker compose --env-file "$root/.env.example" -f "$root/compose/compose.yaml" \
  --profile local-db \
  --profile local-redis-main \
  --profile cloud-sql \
  --profile gcsfuse \
  config >/dev/null
echo 'Compose configuration is valid'
