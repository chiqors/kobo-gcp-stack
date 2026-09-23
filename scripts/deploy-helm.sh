#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
action=${1:-up}
chart="$root/helm/kobo-nextgen"

set -a
source "$root/.env"
set +a
release=${HELM_RELEASE:-kobo}
namespace=${HELM_NAMESPACE:-kobo}
if [[ "$action" != down ]]; then
  [[ "${DEPLOY_TARGET:-docker}" == helm ]] || {
    echo 'DEPLOY_TARGET must be helm; rerun install.sh and select the helm target.' >&2
    exit 2
  }
  [[ "${DEPLOY_MODE:-local}" == gcp ]] || {
    echo 'The Helm chart currently supports gcp mode only.' >&2
    exit 2
  }
  "$root/scripts/render-config.sh" "$root/.env"
fi

helm_args=(
  "$release" "$chart"
  --namespace "$namespace"
)
if [[ -n "${HELM_VALUES_FILE:-}" ]]; then
  [[ -f "$HELM_VALUES_FILE" ]] || { echo "Helm values file not found: $HELM_VALUES_FILE" >&2; exit 1; }
  helm_args+=(-f "$HELM_VALUES_FILE")
fi
helm_args+=(
  --set-file "config.koboEnv=$root/runtime/kobo.env"
  --set-file "config.enketoEnv=$root/runtime/enketo.env"
  --set-file "config.enketoJson=$root/runtime/config/enketo/config.json"
  --set-file "config.nginxConf=$root/runtime/config/nginx/nginx.conf"
  --set-string "cloudSqlProxy.instanceConnectionName=${CLOUD_SQL_INSTANCE_CONNECTION_NAME:-}"
  --set-string "gcsFuse.bucketName=${GCS_BUCKET_NAME:-}"
  --set "cloudSqlProxy.enabled=$([[ ${CLOUD_SQL_ENABLED:-0} == 1 ]] && echo true || echo false)"
  --set "gcsFuse.enabled=$([[ ${GCS_FUSE_ENABLED:-0} == 1 ]] && echo true || echo false)"
  --set "redisMain.enabled=$([[ ${LOCAL_REDIS_MAIN:-0} == 1 ]] && echo true || echo false)"
  --set-string "ingress.hosts[0]=${KOBOFORM_PUBLIC_SUBDOMAIN}.${PUBLIC_DOMAIN_NAME}"
  --set-string "ingress.hosts[1]=${KOBOCAT_PUBLIC_SUBDOMAIN}.${PUBLIC_DOMAIN_NAME}"
  --set-string "ingress.hosts[2]=${ENKETO_PUBLIC_SUBDOMAIN}.${PUBLIC_DOMAIN_NAME}"
)
if [[ "${HELM_PROFILE:-basic}" == gke ]]; then
  helm_args+=(
    --set-string "ingress.className="
    --set "ingress.gce=true"
    --set-string "ingress.staticIpName=${GKE_STATIC_IP_NAME:?GKE_STATIC_IP_NAME is required for the gke profile}"
    --set "managedCertificate.enabled=$([[ ${GKE_MANAGED_CERTIFICATE_ENABLED:-0} == 1 ]] && echo true || echo false)"
    --set-string "managedCertificate.name=${GKE_MANAGED_CERTIFICATE_NAME:-kobo-managed-certificate}"
    --set-string "managedCertificate.domains[0]=${KOBOFORM_PUBLIC_SUBDOMAIN}.${PUBLIC_DOMAIN_NAME}"
    --set-string "managedCertificate.domains[1]=${KOBOCAT_PUBLIC_SUBDOMAIN}.${PUBLIC_DOMAIN_NAME}"
    --set-string "managedCertificate.domains[2]=${ENKETO_PUBLIC_SUBDOMAIN}.${PUBLIC_DOMAIN_NAME}"
    --set-string "serviceAccount.name=${GKE_KSA_NAME:-kobo-kobo-nextgen}"
    --set-string "serviceAccount.annotations.iam\\.gke\\.io/gcp-service-account=${GKE_SERVICE_ACCOUNT_EMAIL:?GKE_SERVICE_ACCOUNT_EMAIL is required for the gke profile}"
    --set-string "persistence.static.storageClass=${GKE_STATIC_STORAGE_CLASS:-standard-rwx}"
  )
fi

case "$action" in
  up)
    helm upgrade --install "${helm_args[@]}" --create-namespace --atomic
    ;;
  down)
    helm uninstall "$release" --namespace "$namespace"
    ;;
  config)
    helm template "${helm_args[@]}" >/dev/null
    echo 'Helm configuration is valid'
    ;;
  *) echo "usage: $0 {up|down|config}" >&2; exit 2 ;;
esac