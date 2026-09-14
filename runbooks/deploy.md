# Deploy

1. Back up PostgreSQL, MongoDB, Redis main, and media metadata.
2. Validate the candidate release in staging with `tests/upgrade-smoke.sh`.
3. Update pinned image references and run `make config`.
4. Run `scripts/deploy.sh pull`, then `scripts/deploy.sh up`.
5. Run `tests/connectivity.sh`, `tests/media-semantics.sh`, and `make smoke`.
6. Confirm Celery queues drain and inspect error rates before closing the
   maintenance window.

Never run two `kpi` initialization containers concurrently. The `kpi` service
is the migration owner; workers wait for its health check.
