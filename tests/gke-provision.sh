#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT
mkdir -p "$temp_dir/bin"

cat > "$temp_dir/bin/gcloud" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${GCLOUD_LOG:?}"
args=" $* "
if [[ "$args" == *' auth list '* ]]; then
  echo test@example.com
elif [[ "$args" == *' config get-value project '* ]]; then
  echo test-project
elif [[ "$args" == *' compute networks subnets describe kobo-gke '* && "$args" == *' --format=value(network) '* ]]; then
  echo projects/test-project/global/networks/kobo-vpc
elif [[ "$args" == *' container clusters describe kobo '* && "$args" == *' --format=value(network) '* ]]; then
  echo projects/test-project/global/networks/kobo-vpc
elif [[ "$args" == *' container clusters describe kobo '* && "$args" == *' --format=value(subnetwork) '* ]]; then
  echo projects/test-project/regions/us-central1/subnetworks/kobo-gke
elif [[ "$args" == *' container clusters describe kobo '* && "$args" == *' --format=value(workloadIdentityConfig.workloadPool) '* ]]; then
  echo test-project.svc.id.goog
elif [[ "$args" == *' iam service-accounts get-iam-policy '* ]]; then
  echo roles/iam.workloadIdentityUser
elif [[ "$args" == *' projects get-iam-policy '* ]]; then
  echo roles/cloudsql.client
elif [[ "$args" == *' storage buckets get-iam-policy '* ]]; then
  echo roles/storage.objectAdmin
elif [[ "$args" == *' compute networks subnets describe kobo-psc '* ]]; then
  exit 1
elif [[ "$args" == *' compute addresses describe kobo-redis-psc-ip '* && "$args" == *' --format=value(address) '* ]]; then
  echo 10.40.0.10
elif [[ "$args" == *' compute addresses describe kobo-redis-psc-ip '* ]]; then
  exit 1
elif [[ "$args" == *' compute forwarding-rules describe kobo-redis-psc '* && "$args" == *' --format=value(pscConnectionStatus) '* ]]; then
  echo ACCEPTED
elif [[ "$args" == *' compute forwarding-rules describe kobo-redis-psc '* ]]; then
  exit 1
elif [[ "$args" == *' compute addresses describe kobo-public-ip '* ]]; then
  echo 34.10.20.30
elif [[ "$args" == *' redis instances describe kobo-redis '* && "$args" == *' --format=value(host) '* ]]; then
  echo 10.30.0.5
elif [[ "$args" == *' redis instances describe kobo-redis '* && "$args" == *' --format=value(port) '* ]]; then
  echo 6379
elif [[ "$args" == *' redis instances get-auth-string kobo-redis '* ]]; then
  echo generated-auth
fi
MOCK
chmod +x "$temp_dir/bin/gcloud"

cat > "$temp_dir/bin/kubectl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${KUBECTL_LOG:?}"
MOCK
chmod +x "$temp_dir/bin/kubectl"

base_env="$temp_dir/base.env"
cat > "$base_env" <<'EOF'
GCP_PROJECT_ID=test-project
GCP_REGION=us-central1
GKE_CLUSTER_NAME=kobo
GCP_NETWORK=kobo-vpc
GCP_SUBNETWORK=kobo-gke
GKE_SUBNET_RANGE=10.20.0.0/20
GKE_STATIC_IP_NAME=kobo-public-ip
GKE_SERVICE_ACCOUNT_EMAIL=kobo@test-project.iam.gserviceaccount.com
GKE_KSA_NAME=kobo-kobo-nextgen
HELM_NAMESPACE=kobo
GCS_FUSE_ENABLED=1
GCS_BUCKET_NAME=test-kobo-media
CLOUD_SQL_ENABLED=1
CLOUD_SQL_INSTANCE_CONNECTION_NAME=test-project:us-central1:kobo
REDIS_BACKEND=memorystore
MEMORYSTORE_CONNECTIVITY=same-vpc
MEMORYSTORE_INSTANCE_NAME=kobo-redis
MEMORYSTORE_PORT=6379
MEMORYSTORE_TLS_ENABLED=0
MEMORYSTORE_AUTH_STRING=
EOF

export PATH="$temp_dir/bin:$PATH"
export GCLOUD_LOG="$temp_dir/gcloud.log" KUBECTL_LOG="$temp_dir/kubectl.log"
"$root/scripts/provision-gke.sh" validate "$base_env" >/dev/null
grep -q '^REDIS_MAIN_URL=redis://:generated-auth@10.30.0.5:6379/0$' "$base_env"
grep -q '^GKE_STATIC_IP_ADDRESS=34.10.20.30$' "$base_env"
grep -q 'nc -zvw 10 10.30.0.5 6379' "$KUBECTL_LOG"

psc_env="$temp_dir/psc.env"
cp "$base_env" "$psc_env"
cat >> "$psc_env" <<'EOF'
MEMORYSTORE_CONNECTIVITY=psc
MEMORYSTORE_AUTH_STRING=psc-auth
PSC_SERVICE_ATTACHMENT=projects/producer/regions/us-central1/serviceAttachments/redis
PSC_ENDPOINT_NAME=kobo-redis-psc
PSC_SUBNET_NAME=kobo-psc
PSC_SUBNET_RANGE=10.40.0.0/24
EOF
"$root/scripts/provision-gke.sh" apply "$psc_env" >/dev/null
grep -q '^REDIS_MAIN_URL=redis://:psc-auth@10.40.0.10:6379/0$' "$psc_env"
grep -q 'forwarding-rules create kobo-redis-psc' "$GCLOUD_LOG"
grep -q 'target-service-attachment projects/producer/regions/us-central1/serviceAttachments/redis' "$GCLOUD_LOG"

install_root="$temp_dir/install"
mkdir -p "$install_root"
rsync -a --exclude .git --exclude .env --exclude runtime "$root/" "$install_root/"
printf '%s\n' \
  helm gcp gke kf kc ee yes yes memorystore example.org existing \
  test-project us-central1 kobo kobo-vpc kobo-gke kobo-public-ip \
  yes kobo-managed-certificate kobo@test-project.iam.gserviceaccount.com \
  standard-rwx no \
  'mongodb://kobo:password@mongodb.internal:27017/formhub?authSource=formhub' \
  same-vpc 6379 no kobo-redis test-project:us-central1:kobo test-kobo-media \
  | "$install_root/install.sh" >/dev/null
grep -q '^GKE_RESOURCE_ACTION=existing$' "$install_root/.env"
grep -q '^MEMORYSTORE_CONNECTIVITY=same-vpc$' "$install_root/.env"
grep -q '^REDIS_MAIN_URL=redis://:generated-auth@10.30.0.5:6379/0$' "$install_root/.env"
grep -q '^GKE_STATIC_IP_ADDRESS=34.10.20.30$' "$install_root/.env"

echo 'GKE provisioning validation is valid'