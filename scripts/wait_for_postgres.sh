#!/usr/bin/env bash
set -euo pipefail
host="${POSTGRES_HOST:-cloud-sql-proxy}"
port="${POSTGRES_PORT:-5432}"
for _ in $(seq 1 60); do
  (echo >/dev/tcp/$host/$port) >/dev/null 2>&1 && exit 0
  sleep 2
done
echo "PostgreSQL is unavailable at $host:$port" >&2
exit 1
