#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
command -v docker >/dev/null || { echo 'docker is required' >&2; exit 1; }
docker compose version >/dev/null || { echo 'Docker Compose v2 is required' >&2; exit 1; }
[[ -f "$root/.env" ]] || { echo "Create $root/.env from .env.example" >&2; exit 1; }
if grep -En 'CHANGE_ME' "$root/.env"; then
  echo 'Replace every placeholder in .env before deployment' >&2
  exit 1
fi
if grep -q '^CLOUD_SQL_ENABLED=1$' "$root/.env" && grep -q 'CLOUD_SQL_INSTANCE_CONNECTION_NAME=project:region:instance' "$root/.env"; then
  echo 'Set CLOUD_SQL_INSTANCE_CONNECTION_NAME before deployment' >&2
  exit 1
fi
if grep -q '^DEPLOY_MODE=gcp$' "$root/.env" && grep -q '^PUBLIC_DOMAIN_NAME=example.org$' "$root/.env"; then
  echo 'Set the production PUBLIC_DOMAIN_NAME before deployment' >&2
  exit 1
fi
network=$(sed -n 's/^NEWT_DOCKER_NETWORK=//p' "$root/.env" | tail -1)
if grep -q '^EXTERNAL_PROXY_ENABLED=1$' "$root/.env"; then
  grep -q '^NEWT_NETWORK_EXTERNAL=true$' "$root/.env" || { echo 'Set NEWT_NETWORK_EXTERNAL=true when external proxying is enabled' >&2; exit 1; }
  docker network inspect "${network:-newt}" >/dev/null || { echo "External Newt network is missing: ${network:-newt}" >&2; exit 1; }
elif ! grep -q '^NEWT_NETWORK_EXTERNAL=false$' "$root/.env"; then
  echo 'Set NEWT_NETWORK_EXTERNAL=false when external proxying is disabled' >&2
  exit 1
fi
if grep -q '^CLOUD_SQL_ENABLED=1$' "$root/.env" || grep -q '^GCS_FUSE_ENABLED=1$' "$root/.env"; then
  credential="$root/runtime/secrets/google/service-account.json"
  [[ -f "$credential" ]] || { echo "Missing runtime credential: $credential" >&2; exit 1; }
  [[ "$(stat -c '%a' "$credential" 2>/dev/null || stat -f '%Lp' "$credential")" == 600 ]] || { echo "Credential must be mode 600: $credential" >&2; exit 1; }
fi
if grep -q '^CLOUD_SQL_ENABLED=1$' "$root/.env"; then
  credential_dir="$root/runtime/secrets/google"
  credential="$credential_dir/service-account.json"
  owner_uid=$(stat -c '%u' "$credential" 2>/dev/null || stat -f '%u' "$credential")
  if [[ "$owner_uid" != 65532 ]]; then
    echo 'Cloud SQL Proxy runs as UID 65532 and cannot read its credential.' >&2
    echo "Run: sudo chown 65532:65532 '$credential'" >&2
    exit 1
  fi
  [[ "$(stat -c '%a' "$credential_dir" 2>/dev/null || stat -f '%Lp' "$credential_dir")" == 700 ]] || {
    echo "Credential directory must be mode 700: $credential_dir" >&2
    exit 1
  }
fi
if grep -q '^GCS_FUSE_ENABLED=1$' "$root/.env"; then
  [[ "$(uname -s)" == Linux ]] || { echo 'Containerized GCS FUSE requires a Linux deployment host' >&2; exit 1; }
  propagation=$(findmnt -no PROPAGATION --target "$root/runtime/media-mount" 2>/dev/null | tail -1 || true)
  [[ "$propagation" == shared || "$propagation" == rshared ]] || {
    echo "The media bind mount is not shared: $root/runtime/media-mount" >&2
    echo "Run: sudo mount --bind '$root/runtime/media-mount' '$root/runtime/media-mount'" >&2
    echo "Then: sudo mount --make-shared '$root/runtime/media-mount'" >&2
    exit 1
  }
fi
echo 'host preflight passed'
