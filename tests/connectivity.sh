#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
docker compose --env-file .env -f compose/compose.yaml exec kpi python - <<'PY'
import os, socket, urllib.parse
import requests
targets = [('PostgreSQL', os.environ['POSTGRES_HOST'], int(os.environ['POSTGRES_PORT']))]
u = urllib.parse.urlparse(os.environ['MONGO_DB_URL'])
targets.append(('MongoDB', u.hostname, u.port or 27017))
for name, host, port in targets:
    with socket.create_connection((host, port), timeout=5):
        print(f'{name}: connected to {host}:{port}')

response = requests.get(os.environ['ENKETO_URL'], timeout=10)
response.raise_for_status()
print(f"Enketo: reached {os.environ['ENKETO_URL']} from KPI")
PY
