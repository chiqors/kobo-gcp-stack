#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
test_env=$(mktemp)
trap 'rm -f "$test_env"' EXIT
sed \
  -e 's/^DEPLOY_TARGET=.*/DEPLOY_TARGET=helm/' \
  -e 's/^DEPLOY_MODE=.*/DEPLOY_MODE=gcp/' \
  -e 's/^KPI_DNS_SERVER=.*/KPI_DNS_SERVER=kube-dns.kube-system.svc.cluster.local/' \
  "$root/.env.example" > "$test_env"
"$root/scripts/render-config.sh" "$test_env"
grep -q 'resolver kube-dns.kube-system.svc.cluster.local' "$root/runtime/config/nginx/nginx.conf"
helm lint "$root/helm/kobo-nextgen" \
  --set-file "config.koboEnv=$root/runtime/kobo.env" \
  --set-file "config.enketoEnv=$root/runtime/enketo.env" \
  --set-file "config.enketoJson=$root/runtime/config/enketo/config.json" \
  --set-file "config.nginxConf=$root/runtime/config/nginx/nginx.conf"
helm template kobo "$root/helm/kobo-nextgen" \
  --set-file "config.koboEnv=$root/runtime/kobo.env" \
  --set-file "config.enketoEnv=$root/runtime/enketo.env" \
  --set-file "config.enketoJson=$root/runtime/config/enketo/config.json" \
  --set-file "config.nginxConf=$root/runtime/config/nginx/nginx.conf" >/dev/null
gke_manifest=$(mktemp)
trap 'rm -f "$test_env" "$gke_manifest"' EXIT
helm template kobo "$root/helm/kobo-nextgen" \
  -f "$root/helm/values.gke.example.yaml" \
  --set-file "config.koboEnv=$root/runtime/kobo.env" \
  --set-file "config.enketoEnv=$root/runtime/enketo.env" \
  --set-file "config.enketoJson=$root/runtime/config/enketo/config.json" \
  --set-file "config.nginxConf=$root/runtime/config/nginx/nginx.conf" > "$gke_manifest"
grep -q 'kubernetes.io/ingress.class: gce' "$gke_manifest"
grep -q 'kubernetes.io/ingress.global-static-ip-name: "kobo-public-ip"' "$gke_manifest"
grep -q 'kind: ManagedCertificate' "$gke_manifest"
grep -q 'iam.gke.io/gcp-service-account' "$gke_manifest"
echo 'Helm configuration is valid'