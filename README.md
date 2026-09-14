# Kobo Nextgen Deployment Notes

This directory is the design workspace for a custom, production-oriented Kobo
deployment. It does not replace or modify the current `kobo-install` flow yet.

## Target topology

```text
Internet
   |
Pangolin (TLS and public routing)
   |
Newt tunnel on Kobo application VM
   +-- shared external Docker network
          |
       Kobo NGINX (kobo-nginx:80)
   +-- KPI web
   +-- KPI/KoboCAT workers and Celery beat
   +-- Enketo
   +-- Redis cache (local, disposable)
   +-- Cloud SQL Auth Proxy
   +-- GCS FUSE media mount

Private services
   +-- Cloud SQL for PostgreSQL 14 + PostGIS
   +-- MongoDB 8 VM
   +-- external Redis main, or optional local Redis main
   +-- GCS bucket for KPI and KoboCAT media
```

In GCP mode, the application VM will not run PostgreSQL or MongoDB. Redis cache
stays local because it is disposable and latency-sensitive. Redis main defaults
to an external service, with a local persistent service available as an option.

## Fresh local test

Prerequisites are Docker Engine or Docker Desktop with Compose v2, at least 4 GB
of memory available to Docker, and an unused local port `8080`. From the
repository root:

```bash
cd nextgen
./install.sh
```

At `Deployment mode (local/gcp) [local]:`, press Enter. Local mode creates a
`.env` with random database and Redis passwords, renders the runtime files, and
configures these local services:

- PostgreSQL 14 with PostGIS and the `koboform` and `kobocat` databases
- MongoDB 8
- Redis main and Redis cache
- KPI, KoboCAT workers, Celery beat, Enketo, and NGINX
- media directories under `nextgen/runtime/media-mount/`

Start the stack:

```bash
./scripts/deploy.sh up
```

The first start pulls several images, initializes both databases, runs all Kobo
migrations, creates the superuser, and builds/copies static files. It can take
several minutes. Follow KPI startup in another terminal with:

```bash
docker compose --env-file .env -f compose/compose.yaml logs -f kpi
```

After startup finishes, verify every dependency and public route:

```bash
./scripts/smoke-test.sh
```

Open the local sites; `*.localhost` normally resolves to `127.0.0.1` without a
hosts-file entry:

```text
KoboForm: http://kf.localhost:8080
KoboCAT:  http://kc.localhost:8080
Enketo:   http://ee.localhost:8080
```

Read the generated administrator credentials with:

```bash
sed -n '/^KOBO_SUPERUSER_USERNAME=/p' .env
sed -n '/^KOBO_SUPERUSER_PASSWORD=/p' runtime/secrets/generated.env
```

Stop containers while preserving local database volumes and media:

```bash
./scripts/deploy.sh down
```

To discard a local test completely, first remove its containers and named
volumes, then move the generated configuration aside before running the
installer again:

```bash
docker compose --env-file .env -f compose/compose.yaml \
  --profile local-db --profile local-redis-main down --volumes
mv .env .env.previous
mv runtime runtime.previous
./install.sh
```

The two `mv` operations retain the old media, logs, and secrets for inspection.
Do not use that reset procedure for a production deployment.

## Documents

- [TREE.md](TREE.md): proposed repository and deployment-template tree.
- [ARCHITECTURE.md](ARCHITECTURE.md): service boundaries and configuration.
- [DECISIONS.md](DECISIONS.md): decisions, risks, and open questions.
- [ROLLOUT.md](ROLLOUT.md): phased implementation and acceptance gates.

## Current recommendation

Build directly from the pinned upstream Kobo Compose definitions, but own one
generated Compose file and the environment files in this directory. Do not continue to
use `python3 run.py --setup` for this deployment: it assumes a Kobo-managed
backend topology and can overwrite generated configuration.

No secret values should be committed. Runtime secrets should come from Google
Secret Manager or root-owned files created during deployment.

The initial scaffold is intentionally infrastructure-aware but not provider
complete: image digests, GCP resource identifiers, IAM grants, Pangolin network
name, and service-account file must be supplied in `.env` and runtime secrets.
Run `make config` before any start operation; it validates Compose expansion
without contacting external services.

## Installer modes

Run `./install.sh` and choose one mode:

- `local`: local PostGIS/PostgreSQL 14, MongoDB 8, Redis main/cache, local media
  directories, and HTTP endpoints at `kf.localhost:8080`,
  `kc.localhost:8080`, and `ee.localhost:8080`.
- `gcp`: external MongoDB, selectable external/local Redis main, optional Cloud
  SQL Proxy, optional GCS FUSE, and optional Pangolin/Newt edge networking.

With external proxying disabled, Compose creates the named edge network and the
sites are available on the configured loopback port. With Pangolin/Newt enabled,
the installer lists the existing user-defined Docker bridge networks. Select
the network containing the Newt container, enter its name directly, or use the
conventional `newt` name when that network already exists. The selected name is
written to `NEWT_DOCKER_NETWORK`; setup verifies that a Newt container is
attached before continuing. The installer also records the Pangolin private DNS
server in `KPI_DNS_SERVER` so KPI and its workers can resolve private resource
aliases. Point the Pangolin resource at `http://kobo-nginx:80`.

Cloud SQL Proxy runs as its native non-root UID `65532`. When Cloud SQL is
enabled, host preflight requires the shared credential file to be owned by that
UID with mode `0600`. Cloud SQL Proxy mounts that file directly, while privileged
GCS FUSE mounts the containing mode-`0700` directory and uses the same credential.

All combinations render the same `compose/compose.yaml`; Compose profiles only
control which optional services start.

The installer prompts separately for the KoboForm, KoboCAT, and Enketo
subdomains. Defaults are `kf`, `kc`, and `ee`, but labels such as `kobo`,
`kobocat`, and `enketo` are supported.
