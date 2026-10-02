#!/usr/bin/env bash
# Install and enable the systemd units that boot the Kobo stack in order:
#   1. kobo-media-bind.service  (before docker: shared bind mount)
#   2. kobo-media-mount.service (after docker:  GCS FUSE prefixes ready)
#   3. kobo-nextgen.service     (after media:   application containers)
#
# Run with sudo from the repository root: sudo scripts/install-systemd.sh
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
[[ $EUID -eq 0 ]] || { echo 'Run with sudo so units can be installed' >&2; exit 1; }

kobo_user=${SUDO_USER:-}
if [[ -z "$kobo_user" || "$kobo_user" == root ]]; then
  kobo_user=$(stat -c '%U' "$root" 2>/dev/null || echo root)
fi
[[ "$kobo_user" != root ]] || {
  echo "Could not determine the non-root user that owns $root; set SUDO_USER" >&2
  exit 1
}
id "$kobo_user" >/dev/null 2>&1 || { echo "Unknown user: $kobo_user" >&2; exit 1; }

gcs_enabled=$(sed -n 's/^GCS_FUSE_ENABLED=//p' "$root/.env" 2>/dev/null | tail -1 || true)
gcs_enabled=${gcs_enabled:-0}

units=(kobo-nextgen)
[[ "$gcs_enabled" == 1 ]] && units=(kobo-media-bind kobo-media-mount "${units[@]}")

for unit in "${units[@]}"; do
  src="$root/systemd/$unit.service"
  [[ -f "$src" ]] || { echo "Missing unit template: $src" >&2; exit 1; }
  sed -e "s|__KOBO_ROOT__|$root|g" -e "s|__KOBO_USER__|$kobo_user|g" \
    "$src" > "/etc/systemd/system/$unit.service"
  chmod 644 "/etc/systemd/system/$unit.service"
  echo "Installed /etc/systemd/system/$unit.service (user=$kobo_user root=$root)"
done
# Remove units that no longer apply (e.g. GCS was disabled).
for unit in kobo-media-bind kobo-media-mount; do
  if [[ " ${units[*]} " != *" $unit "* && -f "/etc/systemd/system/$unit.service" ]]; then
    systemctl disable --now "$unit.service" >/dev/null 2>&1 || true
    rm -f "/etc/systemd/system/$unit.service"
    echo "Removed stale /etc/systemd/system/$unit.service"
  fi
done

systemctl daemon-reload
for unit in "${units[@]}"; do
  systemctl enable "$unit.service"
done
echo 'Enable complete. Units start automatically on boot; start now with:'
echo '  sudo systemctl start kobo-nextgen.service'
