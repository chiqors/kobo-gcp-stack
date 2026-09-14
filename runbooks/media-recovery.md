# Media Recovery

If the GCS mount disappears, stop all KPI and worker services immediately. The
preflight is designed to prevent new starts, but it cannot stop already-running
processes after a mount failure.

Confirm the service-account key, bucket IAM, network access, and mount process.
Remount and run `tests/media-semantics.sh` before restarting application
writers. Check the underlying host mount directory for accidental local files
and reconcile them explicitly; never overwrite the bucket blindly.
