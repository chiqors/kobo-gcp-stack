#!/usr/bin/env bash
set -euo pipefail
python - <<'PY'
import os, socket, urllib.parse
u = urllib.parse.urlparse(os.environ["MONGO_DB_URL"])
host, port = u.hostname, u.port or 27017
for _ in range(60):
    try:
        with socket.create_connection((host, port), timeout=2):
            raise SystemExit(0)
    except OSError:
        import time; time.sleep(2)
raise SystemExit("MongoDB is unavailable at %s:%s" % (host, port))
PY
