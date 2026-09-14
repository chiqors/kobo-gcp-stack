# Decisions and Open Questions

## Accepted direction

| Area | Direction | Status |
|---|---|---|
| Public ingress | Pangolin TLS with Newt on application VM | Chosen |
| Proxy connectivity | Existing edge network; target `kobo-nginx:80` | Chosen |
| Application packaging | Docker Compose using pinned upstream images | Chosen |
| Compose layout | One `compose/compose.yaml` for the full stack | Chosen |
| PostgreSQL | Cloud SQL PostgreSQL 14 with PostGIS | Validate extensions |
| MongoDB | Real MongoDB 8 on dedicated VM | Chosen |
| Redis main | External by default; optional local profile | Provider/SKU undecided |
| Redis cache | Local application-VM container | Chosen |
| Media | GCS through a shared GCS FUSE mount | Prototype and test |
| Static/logs | Local persistent disk; logs shipped externally | Chosen |
| TLS inside tunnel | HTTP to `kobo-nginx:80` over edge network | Chosen |

## Important risks

### GCS FUSE semantics

Kobo believes it is writing to a normal filesystem. GCS FUSE cannot guarantee
every POSIX behavior, and metadata-heavy directory operations can be slow or
costly. This is the highest application-compatibility risk in the design. The
fallback is local persistent disk with scheduled GCS replication, or a custom
KPI image with a native supported object-storage backend.

### MongoDB availability

One MongoDB VM externalizes storage but does not make it highly available.
Production-grade availability needs a three-member replica set across failure
domains or a supported managed MongoDB service.

### Cross-service latency

KPI and workers make frequent PostgreSQL, MongoDB, and Redis calls. All private
services should be in the same GCP region, preferably with measured low
latency. Egress paths must not traverse Pangolin.

### Upstream upgrade compatibility

Kobo images and schema migrations are tightly coupled. Each upgrade must pin a
Kobo release, inspect upstream Compose/environment changes, back up all state,
and pass a staging upgrade test before production rollout.

## Questions to settle before implementation

1. GCP project, region, VPC, and DNS strategy.
2. Exact public base domain and the three Kobo hostnames.
3. Cloud SQL instance tier, HA mode, storage growth, and connection limits.
4. Confirmation that all four required extensions are available on the chosen
   Cloud SQL PostgreSQL version.
5. MongoDB VM sizing, replica-set plan, backup target, and recovery objectives.
6. External Redis product, TLS/auth model, persistence, and failover behavior.
7. GCS bucket name, region, hierarchical namespace, retention, and lifecycle.
8. Required maximum attachment size and expected upload concurrency.
9. RPO/RTO, monitoring destination, and alert delivery channel.
10. Whether a short maintenance window is acceptable for upgrades.
11. Existing Newt edge-network name and which deployment creates it.
