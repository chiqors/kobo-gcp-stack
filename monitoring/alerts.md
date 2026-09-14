# Monitoring Contract

The Compose stack deliberately does not bundle a monitoring server. Export
metrics to the existing monitoring platform and apply `prometheus-rules.yaml`
only after its metric names are connected to real exporters.

Required signals include public synthetic checks for all three hostnames,
container restarts, worker queue depth, GCS FUSE mount/read/write probes, Cloud
SQL saturation and errors, MongoDB replication/backup health, Redis memory and
evictions, disk usage, certificate expiry at Pangolin, and backup age.

Alerts must route to an attended channel and include links to the runbooks.
