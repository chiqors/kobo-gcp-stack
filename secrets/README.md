# Runtime Credentials

Place credentials on the host; do not commit them here.

```text
nextgen/runtime/secrets/google/service-account.json
```

The file must be readable by Docker but restricted on the host (`chmod 600`)
and owned by root or the deployment operator. Both Cloud SQL Proxy and GCS FUSE
mount the same file read-only. The service account needs Cloud SQL Client access
and object access scoped to the Kobo media bucket. Avoid project-wide storage
roles when a bucket-level grant is sufficient.

The application does not use the JSON file directly. KPI and KoboCAT continue
to use their regular PostgreSQL variables:

```text
POSTGRES_HOST=cloud-sql-proxy
POSTGRES_PORT=5432
KPI_DATABASE_URL=postgis://user:password@cloud-sql-proxy:5432/koboform
KC_DATABASE_URL=postgis://user:password@cloud-sql-proxy:5432/kobocat
```

The proxy listens on `cloud-sql-proxy:5432` inside the private Docker network
and forwards to the configured Cloud SQL instance. No Cloud SQL port is
published by the Compose stack.

Rotate the JSON key and audit its use. An attached VM identity remains safer
than a long-lived key, but this layout intentionally supports the single JSON
credential selected for this deployment.
