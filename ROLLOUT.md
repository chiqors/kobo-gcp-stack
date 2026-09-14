# Rollout Plan

## Phase 1: Pin and render

- Pin the Kobo/KPI, Enketo, NGINX, Redis, Cloud SQL Proxy, and GCS FUSE images
  by digest.
- Render one `compose/compose.yaml`; do not rely on Compose overlays.
- Build environment templates from the released `kobo-docker` version.
- Generate secrets outside Git and render root-owned runtime files.
- Make `docker compose config` and secret-placeholder checks mandatory.

Acceptance gate: configuration renders reproducibly with no embedded secret or
unpinned production image.

## Phase 2: Provision stateful services

- Create Cloud SQL, both databases, roles, and required PostGIS extensions.
- Deploy MongoDB 8 with authentication, TLS, private firewalling, monitoring,
  and backups.
- Provision external Redis main with private connectivity and persistence, or
  explicitly select the persistent local `redis-main` profile.
- Create the GCS bucket, prefixes, IAM, versioning, and lifecycle rules.

Acceptance gate: automated connectivity checks succeed from the application VM
and restore tests succeed for PostgreSQL and MongoDB.

## Phase 3: Prove the media layer

- Mount GCS FUSE through the isolated mount service.
- Implement the fail-closed mount preflight.
- Exercise create/read/rename/delete, Unicode names, large files, concurrent
  writers, mount restart, network interruption, and VM reboot.
- Run actual Kobo form-media, submission-attachment, export, thumbnail, and
  deletion workflows.

Acceptance gate: no local fallback writes, no lost objects, and acceptable
latency under expected concurrency. If this fails, stop and use persistent disk
plus replication rather than weakening the gate.

## Phase 4: Start the application

- Start Cloud SQL Proxy, GCS FUSE, Redis cache, KPI, workers, beat, Enketo, and
  NGINX in dependency order.
- Run migrations once as an explicit deployment job before rolling services.
- Attach only `kobo-nginx` to Newt's existing external Docker network.
- Configure Pangolin resources for `kf`, `kc`, and `ee`, all targeting
  `http://kobo-nginx:80` through Newt.
- Verify forwarded scheme/host, secure cookies, upload sizes, timeouts,
  streaming downloads, and WebSockets.

Acceptance gate: health endpoints, login, project creation, form deployment,
Enketo rendering, submission, attachment upload/download, and export pass.

## Phase 5: Operational readiness

- Add service, disk, mount, database, queue-depth, and synthetic-user alerts.
- Document deploy, rollback, secret rotation, restore, and mount-recovery
  procedures.
- Run a full restore into an isolated environment.
- Record capacity baselines and load-test the expected workload.

Acceptance gate: documented RPO/RTO is demonstrated, not assumed.
