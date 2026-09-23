#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
action=${1:-validate}
env_file=${2:-$root/.env}
[[ "$action" == validate || "$action" == apply ]] || {
  echo "usage: $0 {validate|apply} [env-file]" >&2
  exit 2
}

set -a
source "$env_file"
set +a

require() {
  local name="$1"
  [[ -n "${!name:-}" ]] || { echo "$name is required" >&2; exit 2; }
}

require_command() {
  command -v "$1" >/dev/null || { echo "$1 is required for GKE provisioning" >&2; exit 1; }
}

create_or_fail() {
  local description="$1"
  shift
  if [[ "$action" != apply ]]; then
    echo "$description does not exist; rerun with GKE_RESOURCE_ACTION=create" >&2
    exit 1
  fi
  echo "Creating $description"
  "$@"
}

set_env() {
  python3 - "$env_file" "$1" "$2" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
key, value = sys.argv[2:4]
lines = path.read_text().splitlines()
for index, line in enumerate(lines):
    if line.startswith(key + '='):
        lines[index] = f'{key}={value}'
        break
else:
    lines.append(f'{key}={value}')
path.write_text('\n'.join(lines) + '\n')
PY
}

require_command gcloud
require_command kubectl
for name in GCP_PROJECT_ID GCP_REGION GKE_CLUSTER_NAME GCP_NETWORK GCP_SUBNETWORK; do
  require "$name"
done

gcloud auth list --filter=status:ACTIVE --format='value(account)' | grep -q . || {
  echo 'No active gcloud account. Run gcloud auth login first.' >&2
  exit 1
}
gcloud projects describe "$GCP_PROJECT_ID" >/dev/null
gcloud config set project "$GCP_PROJECT_ID" >/dev/null

if [[ "$action" == apply ]]; then
  gcloud services enable \
    container.googleapis.com compute.googleapis.com file.googleapis.com \
    iamcredentials.googleapis.com redis.googleapis.com \
    servicenetworking.googleapis.com sqladmin.googleapis.com \
    storage.googleapis.com dns.googleapis.com --project "$GCP_PROJECT_ID"
fi

if ! gcloud compute networks describe "$GCP_NETWORK" --project "$GCP_PROJECT_ID" >/dev/null 2>&1; then
  create_or_fail "VPC network $GCP_NETWORK" \
    gcloud compute networks create "$GCP_NETWORK" --subnet-mode=custom --project "$GCP_PROJECT_ID"
fi

if ! gcloud compute networks subnets describe "$GCP_SUBNETWORK" --region "$GCP_REGION" --project "$GCP_PROJECT_ID" >/dev/null 2>&1; then
  require GKE_SUBNET_RANGE
  create_or_fail "subnet $GCP_SUBNETWORK" \
    gcloud compute networks subnets create "$GCP_SUBNETWORK" \
      --network "$GCP_NETWORK" --range "$GKE_SUBNET_RANGE" \
      --region "$GCP_REGION" --enable-private-ip-google-access \
      --project "$GCP_PROJECT_ID"
fi
subnet_network=$(gcloud compute networks subnets describe "$GCP_SUBNETWORK" \
  --region "$GCP_REGION" --project "$GCP_PROJECT_ID" --format='value(network)')
[[ "${subnet_network##*/}" == "$GCP_NETWORK" ]] || {
  echo "Subnet $GCP_SUBNETWORK is attached to ${subnet_network##*/}, not $GCP_NETWORK" >&2
  exit 1
}

if ! gcloud container clusters describe "$GKE_CLUSTER_NAME" --region "$GCP_REGION" --project "$GCP_PROJECT_ID" >/dev/null 2>&1; then
  create_or_fail "Autopilot cluster $GKE_CLUSTER_NAME" \
    gcloud container clusters create-auto "$GKE_CLUSTER_NAME" \
      --region "$GCP_REGION" --network "$GCP_NETWORK" \
      --subnetwork "$GCP_SUBNETWORK" \
      --project "$GCP_PROJECT_ID"
fi
cluster_network=$(gcloud container clusters describe "$GKE_CLUSTER_NAME" \
  --region "$GCP_REGION" --project "$GCP_PROJECT_ID" --format='value(network)')
cluster_subnetwork=$(gcloud container clusters describe "$GKE_CLUSTER_NAME" \
  --region "$GCP_REGION" --project "$GCP_PROJECT_ID" --format='value(subnetwork)')
[[ "${cluster_network##*/}" == "$GCP_NETWORK" && "${cluster_subnetwork##*/}" == "$GCP_SUBNETWORK" ]] || {
  echo "Cluster $GKE_CLUSTER_NAME is not attached to $GCP_NETWORK/$GCP_SUBNETWORK" >&2
  exit 1
}
workload_pool=$(gcloud container clusters describe "$GKE_CLUSTER_NAME" \
  --region "$GCP_REGION" --project "$GCP_PROJECT_ID" \
  --format='value(workloadIdentityConfig.workloadPool)')
[[ "$workload_pool" == "${GCP_PROJECT_ID}.svc.id.goog" ]] || {
  echo "Cluster Workload Identity pool is $workload_pool, expected ${GCP_PROJECT_ID}.svc.id.goog" >&2
  exit 1
}
gcloud container clusters get-credentials "$GKE_CLUSTER_NAME" \
  --region "$GCP_REGION" --project "$GCP_PROJECT_ID"
if [[ "$action" == apply ]]; then
  gcloud container clusters update "$GKE_CLUSTER_NAME" --region "$GCP_REGION" \
    --update-addons=GcsFuseCsiDriver=ENABLED,GcpFilestoreCsiDriver=ENABLED \
    --project "$GCP_PROJECT_ID" --quiet
fi

require GKE_STATIC_IP_NAME
if ! gcloud compute addresses describe "$GKE_STATIC_IP_NAME" --global --project "$GCP_PROJECT_ID" >/dev/null 2>&1; then
  create_or_fail "global static IP $GKE_STATIC_IP_NAME" \
    gcloud compute addresses create "$GKE_STATIC_IP_NAME" \
      --global --ip-version=IPV4 --project "$GCP_PROJECT_ID"
fi
public_ip=$(gcloud compute addresses describe "$GKE_STATIC_IP_NAME" \
  --global --project "$GCP_PROJECT_ID" --format='value(address)')
set_env GKE_STATIC_IP_ADDRESS "$public_ip"

if [[ "${GKE_MANAGE_DNS:-0}" == 1 ]]; then
  require GCP_DNS_ZONE_NAME
  require PUBLIC_DOMAIN_NAME
  if ! gcloud dns managed-zones describe "$GCP_DNS_ZONE_NAME" --project "$GCP_PROJECT_ID" >/dev/null 2>&1; then
    create_or_fail "Cloud DNS zone $GCP_DNS_ZONE_NAME" \
      gcloud dns managed-zones create "$GCP_DNS_ZONE_NAME" \
        --dns-name="${PUBLIC_DOMAIN_NAME}." --visibility=public \
        --project "$GCP_PROJECT_ID"
  fi
  zone_dns_name=$(gcloud dns managed-zones describe "$GCP_DNS_ZONE_NAME" \
    --project "$GCP_PROJECT_ID" --format='value(dnsName)')
  [[ "$zone_dns_name" == "${PUBLIC_DOMAIN_NAME}." ]] || {
    echo "Cloud DNS zone $GCP_DNS_ZONE_NAME serves $zone_dns_name, not ${PUBLIC_DOMAIN_NAME}." >&2
    exit 1
  }
  for subdomain in "$KOBOFORM_PUBLIC_SUBDOMAIN" "$KOBOCAT_PUBLIC_SUBDOMAIN" "$ENKETO_PUBLIC_SUBDOMAIN"; do
    record="${subdomain}.${PUBLIC_DOMAIN_NAME}."
    if [[ "$action" == apply ]]; then
      gcloud dns record-sets update "$record" --type=A --ttl=300 \
        --rrdatas="$public_ip" --zone="$GCP_DNS_ZONE_NAME" --project "$GCP_PROJECT_ID"
    else
      record_ip=$(gcloud dns record-sets describe "$record" --type=A \
        --zone="$GCP_DNS_ZONE_NAME" --project "$GCP_PROJECT_ID" --format='value(rrdatas[0])')
      [[ "$record_ip" == "$public_ip" ]] || {
        echo "$record points to $record_ip, expected $public_ip" >&2
        exit 1
      }
    fi
  done
fi

if [[ "${GCS_FUSE_ENABLED:-0}" == 1 ]]; then
  require GCS_BUCKET_NAME
  if ! gcloud storage buckets describe "gs://$GCS_BUCKET_NAME" --project "$GCP_PROJECT_ID" >/dev/null 2>&1; then
    create_or_fail "GCS bucket $GCS_BUCKET_NAME" \
      gcloud storage buckets create "gs://$GCS_BUCKET_NAME" \
        --location "$GCP_REGION" --uniform-bucket-level-access \
        --project "$GCP_PROJECT_ID"
  fi
fi

require GKE_SERVICE_ACCOUNT_EMAIL
gsa_name=${GKE_SERVICE_ACCOUNT_EMAIL%@*}
gsa_project=${GKE_SERVICE_ACCOUNT_EMAIL#*@}
gsa_project=${gsa_project%.iam.gserviceaccount.com}
if ! gcloud iam service-accounts describe "$GKE_SERVICE_ACCOUNT_EMAIL" --project "$gsa_project" >/dev/null 2>&1; then
  create_or_fail "service account $GKE_SERVICE_ACCOUNT_EMAIL" \
    gcloud iam service-accounts create "$gsa_name" \
      --display-name='Kobo GKE workload' --project "$gsa_project"
fi
sql_project=$GCP_PROJECT_ID
if [[ "${CLOUD_SQL_ENABLED:-0}" == 1 ]]; then
  require CLOUD_SQL_INSTANCE_CONNECTION_NAME
  sql_project=${CLOUD_SQL_INSTANCE_CONNECTION_NAME%%:*}
fi
if [[ "$action" == apply ]]; then
  if [[ "${CLOUD_SQL_ENABLED:-0}" == 1 ]]; then
    gcloud projects add-iam-policy-binding "$sql_project" \
      --member="serviceAccount:$GKE_SERVICE_ACCOUNT_EMAIL" \
      --role=roles/cloudsql.client --condition=None --quiet >/dev/null
  fi
  if [[ "${GCS_FUSE_ENABLED:-0}" == 1 ]]; then
    gcloud storage buckets add-iam-policy-binding "gs://$GCS_BUCKET_NAME" \
      --member="serviceAccount:$GKE_SERVICE_ACCOUNT_EMAIL" \
      --role=roles/storage.objectAdmin --quiet >/dev/null
  fi
  ksa_name=${GKE_KSA_NAME:-kobo-kobo-nextgen}
  gcloud iam service-accounts add-iam-policy-binding "$GKE_SERVICE_ACCOUNT_EMAIL" \
    --role=roles/iam.workloadIdentityUser \
    --member="serviceAccount:${GCP_PROJECT_ID}.svc.id.goog[${HELM_NAMESPACE:-kobo}/$ksa_name]" \
    --project "$gsa_project" --quiet >/dev/null
else
  ksa_name=${GKE_KSA_NAME:-kobo-kobo-nextgen}
  wi_member="serviceAccount:${GCP_PROJECT_ID}.svc.id.goog[${HELM_NAMESPACE:-kobo}/$ksa_name]"
  gcloud iam service-accounts get-iam-policy "$GKE_SERVICE_ACCOUNT_EMAIL" \
    --project "$gsa_project" --flatten='bindings[].members' \
    --filter="bindings.role=roles/iam.workloadIdentityUser AND bindings.members=$wi_member" \
    --format='value(bindings.role)' | grep -qx roles/iam.workloadIdentityUser || {
      echo "Missing Workload Identity binding for $wi_member" >&2
      exit 1
    }
  if [[ "${CLOUD_SQL_ENABLED:-0}" == 1 ]]; then
    gcloud projects get-iam-policy "$sql_project" --flatten='bindings[].members' \
      --filter="bindings.role=roles/cloudsql.client AND bindings.members=serviceAccount:$GKE_SERVICE_ACCOUNT_EMAIL" \
      --format='value(bindings.role)' | grep -qx roles/cloudsql.client || {
        echo "Missing roles/cloudsql.client for $GKE_SERVICE_ACCOUNT_EMAIL" >&2
        exit 1
      }
  fi
  if [[ "${GCS_FUSE_ENABLED:-0}" == 1 ]]; then
    gcloud storage buckets get-iam-policy "gs://$GCS_BUCKET_NAME" --flatten='bindings[].members' \
      --filter="bindings.role=roles/storage.objectAdmin AND bindings.members=serviceAccount:$GKE_SERVICE_ACCOUNT_EMAIL" \
      --format='value(bindings.role)' | grep -qx roles/storage.objectAdmin || {
        echo "Missing bucket roles/storage.objectAdmin for $GKE_SERVICE_ACCOUNT_EMAIL" >&2
        exit 1
      }
  fi
fi

if [[ "${CLOUD_SQL_ENABLED:-0}" == 1 ]]; then
  sql_remainder=${CLOUD_SQL_INSTANCE_CONNECTION_NAME#*:}
  sql_instance=${sql_remainder#*:}
  gcloud sql instances describe "$sql_instance" --project "$sql_project" >/dev/null || {
    echo "Cloud SQL instance not found: $CLOUD_SQL_INSTANCE_CONNECTION_NAME" >&2
    exit 1
  }
fi

redis_host=''
redis_port=${MEMORYSTORE_PORT:-6379}
if [[ "${REDIS_BACKEND:-external}" == memorystore ]]; then
  case "${MEMORYSTORE_CONNECTIVITY:-same-vpc}" in
    same-vpc)
      require MEMORYSTORE_INSTANCE_NAME
      if ! gcloud redis instances describe "$MEMORYSTORE_INSTANCE_NAME" --region "$GCP_REGION" --project "$GCP_PROJECT_ID" >/dev/null 2>&1; then
        [[ "$action" == apply ]] || { echo "Memorystore instance not found: $MEMORYSTORE_INSTANCE_NAME" >&2; exit 1; }
        psa_range=${MEMORYSTORE_PSA_RANGE_NAME:-kobo-memorystore-range}
        if ! gcloud compute addresses describe "$psa_range" --global --project "$GCP_PROJECT_ID" >/dev/null 2>&1; then
          gcloud compute addresses create "$psa_range" --global \
            --purpose=VPC_PEERING --prefix-length="${MEMORYSTORE_PSA_PREFIX_LENGTH:-24}" \
            --network="$GCP_NETWORK" --project "$GCP_PROJECT_ID"
        fi
        gcloud services vpc-peerings connect --service=servicenetworking.googleapis.com \
          --ranges="$psa_range" --network="$GCP_NETWORK" --project "$GCP_PROJECT_ID" --quiet
        redis_create=(gcloud redis instances create "$MEMORYSTORE_INSTANCE_NAME"
          --region "$GCP_REGION" --size "${MEMORYSTORE_SIZE_GB:-5}"
          --redis-version redis_7_2 --network "$GCP_NETWORK"
          --connect-mode private-service-access --enable-auth
          --project "$GCP_PROJECT_ID" --quiet)
        [[ "${MEMORYSTORE_TIER:-basic}" == standard ]] && redis_create+=(--tier standard)
        [[ "${MEMORYSTORE_TLS_ENABLED:-0}" == 1 ]] && redis_create+=(--transit-encryption-mode=SERVER_AUTHENTICATION)
        "${redis_create[@]}"
      fi
      redis_host=$(gcloud redis instances describe "$MEMORYSTORE_INSTANCE_NAME" \
        --region "$GCP_REGION" --project "$GCP_PROJECT_ID" --format='value(host)')
      redis_port=$(gcloud redis instances describe "$MEMORYSTORE_INSTANCE_NAME" \
        --region "$GCP_REGION" --project "$GCP_PROJECT_ID" --format='value(port)')
      if [[ -z "${MEMORYSTORE_AUTH_STRING:-}" ]]; then
        MEMORYSTORE_AUTH_STRING=$(gcloud redis instances get-auth-string "$MEMORYSTORE_INSTANCE_NAME" \
          --region "$GCP_REGION" --project "$GCP_PROJECT_ID" --format='value(authString)')
        set_env MEMORYSTORE_AUTH_STRING "$MEMORYSTORE_AUTH_STRING"
      fi
      ;;
    psc)
      for name in PSC_SERVICE_ATTACHMENT PSC_ENDPOINT_NAME PSC_SUBNET_NAME PSC_SUBNET_RANGE; do require "$name"; done
      if ! gcloud compute networks subnets describe "$PSC_SUBNET_NAME" --region "$GCP_REGION" --project "$GCP_PROJECT_ID" >/dev/null 2>&1; then
        create_or_fail "PSC subnet $PSC_SUBNET_NAME" \
          gcloud compute networks subnets create "$PSC_SUBNET_NAME" \
            --network "$GCP_NETWORK" --region "$GCP_REGION" \
            --range "$PSC_SUBNET_RANGE" --purpose=PRIVATE_SERVICE_CONNECT \
            --project "$GCP_PROJECT_ID"
      fi
      psc_address_name="${PSC_ENDPOINT_NAME}-ip"
      if ! gcloud compute addresses describe "$psc_address_name" --region "$GCP_REGION" --project "$GCP_PROJECT_ID" >/dev/null 2>&1; then
        create_or_fail "PSC endpoint address $psc_address_name" \
          gcloud compute addresses create "$psc_address_name" --region "$GCP_REGION" \
            --subnet "$PSC_SUBNET_NAME" --project "$GCP_PROJECT_ID"
      fi
      if ! gcloud compute forwarding-rules describe "$PSC_ENDPOINT_NAME" --region "$GCP_REGION" --project "$GCP_PROJECT_ID" >/dev/null 2>&1; then
        create_or_fail "PSC endpoint $PSC_ENDPOINT_NAME" \
          gcloud compute forwarding-rules create "$PSC_ENDPOINT_NAME" \
            --region "$GCP_REGION" --network "$GCP_NETWORK" \
            --address "$psc_address_name" \
            --target-service-attachment "$PSC_SERVICE_ATTACHMENT" \
            --allow-psc-global-access --project "$GCP_PROJECT_ID"
      fi
      psc_status=$(gcloud compute forwarding-rules describe "$PSC_ENDPOINT_NAME" \
        --region "$GCP_REGION" --project "$GCP_PROJECT_ID" --format='value(pscConnectionStatus)')
      [[ "$psc_status" == ACCEPTED ]] || { echo "PSC endpoint status is $psc_status, expected ACCEPTED" >&2; exit 1; }
      redis_host=$(gcloud compute addresses describe "$psc_address_name" \
        --region "$GCP_REGION" --project "$GCP_PROJECT_ID" --format='value(address)')
      ;;
    *) echo 'MEMORYSTORE_CONNECTIVITY must be same-vpc or psc' >&2; exit 2 ;;
  esac

  redis_scheme=redis
  [[ "${MEMORYSTORE_TLS_ENABLED:-0}" == 1 ]] && redis_scheme=rediss
  redis_auth=''
  if [[ -n "${MEMORYSTORE_AUTH_STRING:-}" ]]; then
    redis_auth=$(python3 -c 'import sys, urllib.parse; print(":" + urllib.parse.quote(sys.argv[1], safe="") + "@")' "$MEMORYSTORE_AUTH_STRING")
  fi
  set_env REDIS_MAIN_URL "${redis_scheme}://${redis_auth}${redis_host}:${redis_port}/0"
  set_env REDIS_MAIN_PASSWORD "${MEMORYSTORE_AUTH_STRING:-}"
  set_env MEMORYSTORE_HOST "$redis_host"
  set_env MEMORYSTORE_PORT "$redis_port"

  probe_name="kobo-redis-probe-$$"
  kubectl run "$probe_name" --namespace default --restart=Never --rm --attach \
    --image=busybox:1.36 --command -- nc -zvw 10 "$redis_host" "$redis_port"
fi

storage_class=${GKE_STATIC_STORAGE_CLASS:-standard-rwx}
storage_ready=0
for _ in $(seq 1 30); do
  if kubectl get storageclass "$storage_class" >/dev/null 2>&1; then
    storage_ready=1
    break
  fi
  sleep 5
done
[[ "$storage_ready" == 1 ]] || {
  echo "GKE storage class is not available: $storage_class" >&2
  exit 1
}
if [[ "${GCS_FUSE_ENABLED:-0}" == 1 ]]; then
  kubectl get csidriver gcsfuse.csi.storage.gke.io >/dev/null 2>&1 || {
    echo 'GKE Cloud Storage FUSE CSI driver is not available' >&2
    exit 1
  }
fi

echo "GKE resources are valid. Public IP: $public_ip"