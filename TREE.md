# Implemented Tree

```text
nextgen/
|-- install.sh                         # interactive local/GCP installer
|-- Makefile
|-- .env.example
|-- .gitignore
|-- README.md
|-- ARCHITECTURE.md
|-- DECISIONS.md
|-- ROLLOUT.md
|-- compose/
|   |-- compose.yaml                  # the only Compose file
|   `-- versions.env
|-- config/
|   |-- enketo/config.json.tpl
|   `-- nginx/nginx.conf.tpl
|-- images/gcsfuse/Dockerfile
|-- scripts/
|   |-- bootstrap-host.sh
|   |-- render-config.sh
|   |-- preflight-host.sh
|   |-- preflight.sh
|   |-- deploy.sh
|   |-- smoke-test.sh
|   |-- wait_for_mongo.sh
|   |-- wait_for_postgres.sh
|   |-- gcsfuse-mount.sh
|   |-- init-local-postgres.sh
|   |-- provision-cloud-sql.sql
|   |-- backup-mongodb.sh
|   `-- restore-drill.sh
|-- secrets/README.md
|-- systemd/
|   |-- kobo-nextgen.service
|   `-- kobo-media-mount.service
|-- monitoring/
|   |-- prometheus-rules.yaml
|   `-- alerts.md
|-- runbooks/
|   |-- deploy.md
|   |-- rollback.md
|   |-- database-restore.md
|   |-- media-recovery.md
|   `-- incident-response.md
|-- tests/
|   |-- compose-config.sh
|   |-- connectivity.sh
|   |-- media-semantics.sh
|   `-- upgrade-smoke.sh
`-- runtime/                           # generated and ignored
    |-- kobo.env
    |-- enketo.env
    |-- config/
    |-- logs/
    |-- static/
    |-- media-mount/
    `-- secrets/
        |-- generated.env
        `-- google/service-account.json
```

Local and GCP installations use the same `compose/compose.yaml`. Profiles
select `local-db`, `local-redis-main`, `cloud-sql`, and `gcsfuse` services.
Rendered files, credentials, media, logs, and generated secrets are kept under
the ignored `runtime/` boundary.
