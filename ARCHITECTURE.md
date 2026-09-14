# Architecture

## Application VM

The first implementation should preserve the service layout from
`kobotoolbox/kpi:2.026.33a` and `kobotoolbox/enketo-express-extra-widgets:7.6.3`:

- `kpi`: web application, migrations, superuser initialization, static build.
- `worker`, `worker-low`, `worker-long`, `worker-kobocat`: Celery workloads.
- `beat`: singleton Celery scheduler.
- `enketo`: form rendering and offline-capable form services.
- `nginx`: internal HTTP origin for Pangolin/Newt.
- `redis-cache`: local cache and session Redis.
- `redis-main`: optional local Celery/Enketo Redis, enabled by a Compose
  profile when an external Redis URL is not supplied.
- `cloud-sql-proxy`: authenticated private connection to Cloud SQL.
- `gcsfuse`: mounts the media bucket for all writers and NGINX readers.

When external proxying is enabled, Newt and Kobo NGINX join an existing external
Docker network. Newt forwards the three public hostnames directly to
`http://kobo-nginx:80`; Pangolin owns TLS. Kobo must still be configured with
public scheme `https` and the real public hostnames so generated URLs and secure
cookies are correct. Without Newt, Compose owns the edge network and publishes
NGINX only on the configured loopback address and port.

```text
kf.<base-domain> --+
kc.<base-domain> --+--> Pangolin --> Newt == edge network ==> kobo-nginx:80
ee.<base-domain> --+
```

The original `Host`, `X-Forwarded-Proto: https`, client IP headers, request body
limits, streaming behavior, and WebSocket upgrades must survive the proxy path.
Only `kobo-nginx` joins the edge network. KPI, workers, Enketo, Redis, Cloud SQL
Proxy, and GCS FUSE stay on Kobo's private bridge network. That bridge permits
outbound traffic because the proxy, GCS FUSE, MongoDB, and Redis may need GCP
or VPC endpoints; no service on it publishes a host port. The edge network name
is a deployment setting and the Newt deployment must create it before Kobo
starts.

## Compose ownership

There is exactly one Compose file: `compose/compose.yaml`. Optional behavior is
expressed with environment-rendered settings and Compose profiles, not overlay
files. The file owns application services, both Redis modes, Cloud SQL Proxy,
GCS FUSE, networks, volumes, health checks, and optional monitoring agents.

## PostgreSQL

Use Cloud SQL for PostgreSQL 14 initially because the released Kobo stack is
based on PostgreSQL 14. Required properties:

- Two databases: `koboform` for KPI and `kobocat` for KoboCAT.
- A least-privilege application role with access to both databases.
- PostGIS extensions required by the upstream initialization script:
  `postgis`, `postgis_topology`, `fuzzystrmatch`, and
  `postgis_tiger_geocoder`.
- Private IP and Cloud SQL Auth Proxy; no public database exposure.
- Automated backups, point-in-time recovery, deletion protection, maintenance
  window, and tested restore procedure.

The application URLs remain separate:

```text
KPI_DATABASE_URL=postgis://...@cloud-sql-proxy:5432/koboform
KC_DATABASE_URL=postgis://...@cloud-sql-proxy:5432/kobocat
DATABASE_URL=postgis://...@cloud-sql-proxy:5432/koboform
```

Database and extension creation belongs to provisioning, not application
startup. The application role should not need `CREATEDB` in steady state.

## MongoDB

Run MongoDB 8 on its own VM, matching the released Kobo backend. Use a private
address, authentication, TLS, and firewall rules that only allow the
application VM. Prefer a replica set even if it begins as a single member: it
provides an upgrade path and enables standard operational tooling.

The target connection is passed as `MONGO_DB_URL`; no Mongo compatibility proxy
is used. Backups require both automated snapshots and logical backup/restore
drills. A single Mongo VM remains a single point of failure until replica-set
members are added in separate zones.

## Redis

Redis main holds Celery broker state plus Enketo state. It is not equivalent to
a disposable cache. Production defaults to an external Redis with
authentication, TLS where supported, persistence, HA/failover, and private
networking.

A local `redis-main` service is available as an explicit Compose profile for
smaller deployments. It must use a persistent volume, authentication, a health
check, and no published host port. Application services consume a rendered
Redis-main URL, so selecting local or external mode does not require another
Compose file. Validation must reject enabling local mode while an external URL
is configured.

Redis cache runs locally with a persistent named volume only if session
survival across container restarts is desired. It serves Django sessions/cache
and Enketo cache. Do not expose either Redis endpoint publicly.

Keep the upstream logical separation and database numbers when rendering:

```text
CELERY_BROKER_URL=redis://.../1
REDIS_SESSION_URL=redis://redis-cache:6379/2
CACHE_URL=redis://redis-cache:6379/5
ENKETO_REDIS_MAIN_URL=<same selected Redis main endpoint>/0
```

## GCS FUSE media

The released KPI container expects two writable filesystem trees:

```text
/srv/src/kpi/media
/srv/src/kobocat/media
```

NGINX also needs read-only access to KoboCAT media and KPI public media. Mount
one bucket at `runtime/media-mount`, with separate `kpi/` and `kobocat/`
prefixes, then bind those prefixes into every application worker and NGINX.
Static files and logs remain on local persistent disk.

Containerized GCS FUSE needs `/dev/fuse`, `SYS_ADMIN`, mount propagation, and a
shared host bind mount. This is elevated infrastructure, so the FUSE container
must be isolated from the public network. It reads the same mounted JSON key as
Cloud SQL Proxy, matching the single-credential design for this stack.

Application containers must not start merely because the FUSE process exists.
A preflight/init gate must verify all of the following:

1. The path is a real mount point.
2. Both media prefixes exist with UID/GID 1000 write access.
3. A create/read/rename/delete probe succeeds.
4. The probe object can be deleted cleanly.

Fail closed if any check fails. Otherwise Docker could write media into the
underlying local directory while GCS is unmounted, producing split storage.

GCS FUSE is a compatibility layer, not full POSIX storage. Before production,
test Kobo uploads, large attachments, Unicode filenames, concurrent workers,
rename/delete behavior, exports, thumbnails, and restart/recovery. Prefer a
hierarchical-namespace bucket and enable object versioning and retention
appropriate to the recovery policy.

## Secrets and identity

- Use the single shared service-account JSON selected for this stack for Cloud
  SQL Proxy and GCS FUSE.
- Deliver it out of band to `runtime/secrets/google/service-account.json`, make
  it root-owned with mode `0600`, and rotate it on a defined schedule.
- Never place credentials in Compose YAML, Git, image layers, or command-line
  arguments visible in process listings.
- Limit the shared Google service account to Cloud SQL Client plus
  bucket-scoped media access; do not grant broad project storage roles.
- Pin images by version and digest, and record the upstream source revision.
