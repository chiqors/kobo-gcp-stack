#!/usr/bin/env bash
set -euo pipefail

command -v gcsfuse >/dev/null || { echo 'gcsfuse is missing from GCS_FUSE_IMAGE' >&2; exit 1; }

bucket="${GCS_BUCKET_NAME:?GCS_BUCKET_NAME must be set}"
mount_root="${GCS_MOUNT_PATH:-/mnt/media}"
pids=()

is_mounted() {
  [[ "$(findmnt -n -o FSTYPE --target "$1" 2>/dev/null | tail -1 || true)" == fuse.gcsfuse ]]
}

# A FUSE mount whose daemon died stays in the mount table but returns ENOTCONN.
# findmnt still reports fuse.gcsfuse for it, so probe for liveness as well.
is_healthy() {
  is_mounted "$1" && stat "$1" >/dev/null 2>&1
}

# A previous container may leave a live or stale mount behind. Always take
# ownership of the mount point instead of trusting an existing mount: the old
# FUSE daemon can still answer briefly while it is being torn down.
clear_mount() {
  local target="$1"
  is_mounted "$target" || return 0
  echo "Clearing existing GCS FUSE mount at ${target}" >&2
  umount -l "$target" 2>/dev/null \
    || fusermount -u "$target" 2>/dev/null \
    || umount "$target" 2>/dev/null \
    || true
  sleep 1
}

# Kobo keeps KPI and KoboCAT media under separate prefixes of one bucket. Each
# prefix must be mounted *directly* on the directory that compose binds into the
# application containers. A bind mount only receives mount events for the mount
# point it was created from, so binding a subdirectory of a single bucket-root
# mount (or mounting the parent after the containers start) never propagates.
mount_prefix() {
  local prefix="$1" target="$2"
  clear_mount "$target"
  mkdir -p "$target"
  echo "Mounting gs://${bucket}/${prefix} at ${target}"
  gcsfuse --implicit-dirs --foreground --uid 1000 --gid 1000 \
    --file-mode 0664 --dir-mode 0775 --o allow_other \
    --only-dir "$prefix" "$bucket" "$target" &
  pids+=("$!")
}

# Forward the container's SIGTERM so gcsfuse unmounts before it is killed.
# Without this the FUSE daemon is SIGKILLed and the host keeps a stale mount.
shutdown() {
  echo 'Received SIGTERM; unmounting GCS FUSE prefixes' >&2
  local p
  for p in "${pids[@]}"; do kill -TERM "$p" 2>/dev/null || true; done
  for p in "${pids[@]}"; do wait "$p" 2>/dev/null || true; done
  exit 0
}

trap shutdown TERM INT

mount_prefix kpi "${mount_root}/kpi"
mount_prefix kobocat "${mount_root}/kobocat"

for _ in $(seq 1 60); do
  if is_healthy "${mount_root}/kpi" && is_healthy "${mount_root}/kobocat"; then
    break
  fi
  sleep 1
done
if ! is_healthy "${mount_root}/kpi" || ! is_healthy "${mount_root}/kobocat"; then
  echo 'GCS FUSE prefix mounts did not become ready' >&2
  exit 1
fi

# Stay alive while both mounts are healthy. If either gcsfuse process exits, the
# container exits too so the orchestrator restarts it and re-establishes media.
wait -n || true
echo 'A gcsfuse process exited; restarting container to remount media' >&2
exit 1
