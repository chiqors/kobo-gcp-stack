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

## Media remount

The GCS FUSE prefixes must be mounted before the application containers start.
If the `gcsfuse` container is recreated, the running consumers keep pointing at
the dead mount and media returns `Transport endpoint is not connected`. Recovery
is:

```bash
scripts/deploy.sh remount
```

This force-recreates the FUSE container, waits for both prefix mounts, and
recreates `kpi`, the workers, `beat`, and NGINX. Do not use
`docker compose restart gcsfuse`; it leaves stale mounts and does not recreate
the consumers.

## Boot ordering

`sudo scripts/install-systemd.sh` installs the units that bring the stack up in
order after a VM reboot: `kobo-media-bind.service` (shared bind, before Docker),
`kobo-media-mount.service` (GCS FUSE prefixes ready), then
`kobo-nextgen.service` (`scripts/deploy.sh up`). After a reboot, confirm with:

```bash
systemctl status kobo-media-bind.service kobo-media-mount.service kobo-nextgen.service
findmnt -o TARGET,FSTYPE,PROPAGATION | grep media-mount
```
