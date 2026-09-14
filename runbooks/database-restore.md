# Database Restore

Restore Cloud SQL using point-in-time recovery into a new instance. Restore
MongoDB into an isolated replica set using `scripts/restore-drill.sh`. Validate
document counts, migrations, service health, sample projects, submissions, and
attachments before changing application endpoints.

Never restore directly over the only production copy. Record recovery time and
the last recoverable transaction to verify the stated RTO and RPO.
