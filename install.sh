#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd)
env_file="$root/.env"

choose() {
  local prompt="$1" default="$2" answer
  read -r -p "$prompt [$default]: " answer || true
  printf '%s' "${answer:-$default}"
}

choose_secret() {
  local prompt="$1" answer
  read -r -s -p "$prompt (leave empty when AUTH is disabled): " answer || true
  printf '\n' >&2
  printf '%s' "$answer"
}

choose_newt_network() {
  local default="$1" answer selected index=1
  local -a networks=()

  while IFS= read -r selected; do
    [[ -n "$selected" && "$selected" != bridge ]] && networks+=("$selected")
  done < <(docker network ls --filter driver=bridge --format '{{.Name}}' 2>/dev/null | sort)

  printf 'Pangolin/Newt network:\n' >&2
  printf '  Enter "newt" to use the conventional network name.\n' >&2
  if ((${#networks[@]})); then
    printf '  Or select an existing Docker bridge network:\n' >&2
    for selected in "${networks[@]}"; do
      printf '    %d) %s\n' "$index" "$selected" >&2
      ((index += 1))
    done
  else
    printf '  No user-defined Docker bridge networks were detected.\n' >&2
  fi

  read -r -p "Network number or name [$default]: " answer || true
  answer=${answer:-$default}
  if [[ "$answer" =~ ^[0-9]+$ ]] && ((answer >= 1 && answer <= ${#networks[@]})); then
    answer=${networks[answer-1]}
  fi
  [[ "$answer" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || {
    echo 'Docker network names may contain only letters, numbers, period, underscore, and hyphen.' >&2
    return 2
  }
  printf '%s' "$answer"
}

if [[ ! -f "$env_file" ]]; then
  cp "$root/.env.example" "$env_file"
fi

deployment_target=$(choose 'Deployment target (docker/helm)' 'docker')
[[ "$deployment_target" == docker || "$deployment_target" == helm ]] || {
  echo 'Choose docker or helm' >&2
  exit 2
}
mode=$(choose 'Deployment mode (local/gcp)' 'local')
[[ "$mode" == local || "$mode" == gcp ]] || { echo 'Choose local or gcp' >&2; exit 2; }
if [[ "$deployment_target" == helm && "$mode" != gcp ]]; then
  echo 'The Helm chart currently supports gcp mode only.' >&2
  exit 2
fi
helm_profile=basic
gke_static_ip_name=''
gke_managed_certificate_enabled=no
gke_managed_certificate_name=''
gke_service_account_email=''
gke_static_storage_class=''
redis_backend=local
gke_resource_action=existing
gcp_project_id=''
gcp_region=''
gke_cluster_name=''
gcp_network=''
gcp_subnetwork=''
gke_subnet_range=''
memorystore_connectivity=same-vpc
memorystore_instance_name=''
memorystore_tier=basic
memorystore_size_gb=5
memorystore_port=6379
memorystore_host=''
memorystore_tls_enabled=0
memorystore_auth=''
psc_service_attachment=''
psc_endpoint_name=''
psc_subnet_name=''
psc_subnet_range=''
gke_manage_dns=0
gcp_dns_zone_name=''
mongodb_backend=existing
if [[ "$deployment_target" == helm ]]; then
  helm_profile=$(choose 'Kubernetes profile (basic/gke)' 'gke')
  [[ "$helm_profile" == basic || "$helm_profile" == gke ]] || {
    echo 'Choose basic or gke' >&2
    exit 2
  }
fi

current_koboform_subdomain=$(sed -n 's/^KOBOFORM_PUBLIC_SUBDOMAIN=//p' "$env_file" | tail -1)
current_kobocat_subdomain=$(sed -n 's/^KOBOCAT_PUBLIC_SUBDOMAIN=//p' "$env_file" | tail -1)
current_enketo_subdomain=$(sed -n 's/^ENKETO_PUBLIC_SUBDOMAIN=//p' "$env_file" | tail -1)
koboform_subdomain=$(choose 'KoboForm subdomain' "${current_koboform_subdomain:-kf}")
kobocat_subdomain=$(choose 'KoboCAT subdomain' "${current_kobocat_subdomain:-kc}")
enketo_subdomain=$(choose 'Enketo subdomain' "${current_enketo_subdomain:-ee}")
for subdomain in "$koboform_subdomain" "$kobocat_subdomain" "$enketo_subdomain"; do
  [[ "$subdomain" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || {
    echo "Invalid DNS subdomain label: $subdomain" >&2
    exit 2
  }
done

if [[ "$mode" == gcp ]]; then
  gcs_default=yes
  sql_default=yes
  if [[ "$deployment_target" == helm && "$helm_profile" == basic ]]; then
    gcs_default=no
    sql_default=no
  fi
  gcs=$(choose 'Enable GCS FUSE? (yes/no)' "$gcs_default")
  sql=$(choose 'Enable Cloud SQL Proxy? (yes/no)' "$sql_default")
  if [[ "$helm_profile" == gke ]]; then
    redis_backend=$(choose 'Redis main backend (memorystore/external/local)' 'memorystore')
    [[ "$redis_backend" == memorystore || "$redis_backend" == external || "$redis_backend" == local ]] || {
      echo 'Choose memorystore, external, or local' >&2
      exit 2
    }
    [[ "$redis_backend" == local ]] && local_redis=yes || local_redis=no
  else
    redis_backend=external
    local_redis=$(choose 'Run Redis main locally? (yes/no)' 'no')
    [[ "$local_redis" == yes || "$local_redis" == y ]] && redis_backend=local
  fi
  if [[ "$deployment_target" == docker ]]; then
    proxy=$(choose 'Use external Pangolin/Newt proxy network? (yes/no)' 'yes')
  else
    proxy=no
  fi
  if [[ "$deployment_target" == helm || "$proxy" == yes || "$proxy" == y ]]; then
    public_domain=$(choose 'Public base domain (for example kobo.example.org)' 'example.org')
  fi
  if [[ "$helm_profile" == gke ]]; then
    gke_resource_action=$(choose 'GCP resources (existing/create)' 'existing')
    [[ "$gke_resource_action" == existing || "$gke_resource_action" == create ]] || {
      echo 'Choose existing or create' >&2
      exit 2
    }
    current_project=$(gcloud config get-value project 2>/dev/null || true)
    gcp_project_id=$(choose 'GCP project ID' "${current_project:-project-id}")
    gcp_region=$(choose 'GCP region' 'us-central1')
    gke_cluster_name=$(choose 'GKE Autopilot cluster name' 'kobo')
    gcp_network=$(choose 'GKE VPC network name' 'kobo-vpc')
    gcp_subnetwork=$(choose 'GKE subnet name' 'kobo-gke')
    if [[ "$gke_resource_action" == create ]]; then
      gke_subnet_range=$(choose 'GKE subnet IPv4 range' '10.20.0.0/20')
    fi
    gke_static_ip_name=$(choose 'GCP global static IP resource name' 'kobo-public-ip')
    [[ "$gke_static_ip_name" =~ ^[a-z]([-a-z0-9]*[a-z0-9])?$ ]] || {
      echo 'The static IP resource name must be a lowercase GCP resource name.' >&2
      exit 2
    }
    gke_managed_certificate_enabled=$(choose 'Create a Google-managed certificate? (yes/no)' 'yes')
    if [[ "$gke_managed_certificate_enabled" == yes || "$gke_managed_certificate_enabled" == y ]]; then
      gke_managed_certificate_name=$(choose 'Google-managed certificate name' 'kobo-managed-certificate')
    fi
    gke_service_account_email=$(choose 'Google service account email for Workload Identity' "kobo@${gcp_project_id}.iam.gserviceaccount.com")
    [[ "$gke_service_account_email" =~ ^[^[:space:]@]+@[^[:space:]@]+\.iam\.gserviceaccount\.com$ ]] || {
      echo 'Enter a Google service account email ending in .iam.gserviceaccount.com.' >&2
      exit 2
    }
    gke_static_storage_class=$(choose 'GKE RWX storage class for static files' 'standard-rwx')
    printf 'GKE public hosts: %s.%s, %s.%s, %s.%s\n' \
      "$koboform_subdomain" "$public_domain" \
      "$kobocat_subdomain" "$public_domain" \
      "$enketo_subdomain" "$public_domain"
    manage_dns=$(choose 'Manage these records in Cloud DNS? (yes/no)' 'no')
    if [[ "$manage_dns" == yes || "$manage_dns" == y ]]; then
      gke_manage_dns=1
      gcp_dns_zone_name=$(choose 'Cloud DNS managed zone name' 'kobo-public')
    fi
  fi
  if [[ "$proxy" == yes || "$proxy" == y ]]; then
    current_newt_network=$(sed -n 's/^NEWT_DOCKER_NETWORK=//p' "$env_file" | tail -1)
    newt_network=$(choose_newt_network "${current_newt_network:-newt}")
    kpi_dns_server=$(choose 'Pangolin private DNS server' '100.96.128.1')
  else
    public_domain=${public_domain:-localhost}
    newt_network=newt
    if [[ "$deployment_target" == helm ]]; then
      kpi_dns_server=kube-dns.kube-system.svc.cluster.local
    else
      kpi_dns_server=127.0.0.11
    fi
  fi
  if [[ "$deployment_target" == helm ]]; then
    mongodb_backend=$(choose 'MongoDB backend (existing/cluster)' 'existing')
    [[ "$mongodb_backend" == existing || "$mongodb_backend" == cluster ]] || {
      echo 'Choose existing or cluster' >&2
      exit 2
    }
    if [[ "$mongodb_backend" == cluster ]]; then
      mongo_url='mongodb://provisioned'
    else
      mongo_url=$(choose 'MongoDB 8 connection URI' 'mongodb://kobo:password@mongodb.internal:27017/formhub?authSource=admin')
    fi
  else
    mongo_url=$(choose 'MongoDB 8 connection URI' 'mongodb://kobo:password@mongodb.internal:27017/formhub?authSource=admin')
  fi
  if [[ "$redis_backend" == local ]]; then
    redis_url=''
  elif [[ "$redis_backend" == memorystore ]]; then
    memorystore_connectivity=$(choose 'Memorystore connectivity (same-vpc/psc)' 'same-vpc')
    [[ "$memorystore_connectivity" == same-vpc || "$memorystore_connectivity" == psc ]] || {
      echo 'Choose same-vpc or psc' >&2
      exit 2
    }
    memorystore_port=$(choose 'Memorystore port' '6379')
    [[ "$memorystore_port" =~ ^[0-9]+$ ]] && ((memorystore_port >= 1 && memorystore_port <= 65535)) || {
      echo 'Memorystore port must be between 1 and 65535.' >&2
      exit 2
    }
    memorystore_tls=$(choose 'Use TLS for Memorystore? (yes/no)' 'no')
    [[ "$memorystore_tls" == yes || "$memorystore_tls" == y ]] && memorystore_tls_enabled=1
    if [[ "$memorystore_connectivity" == same-vpc ]]; then
      memorystore_instance_name=$(choose 'Memorystore instance name' 'kobo-redis')
      if [[ "$gke_resource_action" == create ]]; then
        memorystore_tier=$(choose 'Memorystore tier (basic/standard)' 'basic')
        [[ "$memorystore_tier" == basic || "$memorystore_tier" == standard ]] || {
          echo 'Choose basic or standard' >&2
          exit 2
        }
        memorystore_size_gb=$(choose 'Memorystore capacity in GiB' '5')
      fi
      memorystore_host=provisioning.invalid
    else
      psc_service_attachment=$(choose 'Redis PSC service attachment URI' 'projects/producer/regions/us-central1/serviceAttachments/redis')
      psc_endpoint_name=$(choose 'PSC endpoint name' 'kobo-redis-psc')
      psc_subnet_name=$(choose 'PSC subnet name' 'kobo-psc')
      psc_subnet_range=$(choose 'PSC subnet IPv4 range' '10.20.240.0/24')
      memorystore_auth=$(choose_secret 'Memorystore AUTH string')
      memorystore_host=provisioning.invalid
    fi
    redis_scheme=redis
    [[ "$memorystore_tls" == yes || "$memorystore_tls" == y ]] && redis_scheme=rediss
    if [[ -n "$memorystore_auth" ]]; then
      encoded_memorystore_auth=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$memorystore_auth")
      redis_url="${redis_scheme}://:${encoded_memorystore_auth}@${memorystore_host}:${memorystore_port}/0"
    else
      redis_url="${redis_scheme}://${memorystore_host}:${memorystore_port}/0"
    fi
  else
    redis_url=$(choose 'External Redis-main URL' 'rediss://:password@redis.internal:6379/0')
  fi
  if [[ "$sql" == yes || "$sql" == y ]]; then
    cloud_sql_instance=$(choose 'Cloud SQL instance connection name' 'project:region:instance')
    postgres_host=cloud-sql-proxy
    postgres_port=5432
  else
    cloud_sql_instance=''
    postgres_host=$(choose 'PostgreSQL host' 'postgres.internal')
    postgres_port=$(choose 'PostgreSQL port' '5432')
  fi
  if [[ "$gcs" == yes || "$gcs" == y ]]; then
    gcs_bucket=$(choose 'GCS media bucket name' 'project-kobo-media')
  else
    gcs_bucket=''
  fi
else
  gcs=no
  sql=no
  proxy=no
  local_redis=yes
  public_domain=localhost
  mongo_url=''
  redis_url=''
  cloud_sql_instance=''
  gcs_bucket=''
  postgres_host=postgres-local
  postgres_port=5432
  newt_network=newt
  kpi_dns_server=127.0.0.11
fi

python3 - "$env_file" "$mode" "$gcs" "$sql" "$proxy" "$local_redis" "$public_domain" "$mongo_url" "$redis_url" "$cloud_sql_instance" "$gcs_bucket" "$postgres_host" "$postgres_port" "$newt_network" "$kpi_dns_server" "$koboform_subdomain" "$kobocat_subdomain" "$enketo_subdomain" "$deployment_target" "$helm_profile" "$gke_static_ip_name" "$gke_managed_certificate_enabled" "$gke_managed_certificate_name" "$redis_backend" "$gke_service_account_email" "$gke_static_storage_class" "$gke_resource_action" "$gcp_project_id" "$gcp_region" "$gke_cluster_name" "$gcp_network" "$gcp_subnetwork" "$gke_subnet_range" "$memorystore_connectivity" "$memorystore_instance_name" "$memorystore_tier" "$memorystore_size_gb" "$memorystore_port" "$memorystore_tls_enabled" "$memorystore_auth" "$psc_service_attachment" "$psc_endpoint_name" "$psc_subnet_name" "$psc_subnet_range" "$gke_manage_dns" "$gcp_dns_zone_name" "$mongodb_backend" <<'PY'
import pathlib, secrets, shlex, sys, urllib.parse
p = pathlib.Path(sys.argv[1])
values = {}
for line in p.read_text().splitlines():
    if line and not line.startswith('#') and '=' in line:
        k, v = line.split('=', 1); values[k] = v
values['DEPLOY_MODE'] = sys.argv[2]
values['DEPLOY_TARGET'] = sys.argv[19]
values['HELM_PROFILE'] = sys.argv[20]
values['GKE_STATIC_IP_NAME'] = sys.argv[21]
values['GKE_MANAGED_CERTIFICATE_ENABLED'] = '1' if sys.argv[22].lower() in ('y', 'yes', '1') else '0'
values['GKE_MANAGED_CERTIFICATE_NAME'] = sys.argv[23]
values['REDIS_BACKEND'] = sys.argv[24]
values['GKE_SERVICE_ACCOUNT_EMAIL'] = sys.argv[25]
values['GKE_STATIC_STORAGE_CLASS'] = sys.argv[26]
values['GKE_RESOURCE_ACTION'] = sys.argv[27]
values['GCP_PROJECT_ID'] = sys.argv[28]
values['GCP_REGION'] = sys.argv[29]
values['GKE_CLUSTER_NAME'] = sys.argv[30]
values['GCP_NETWORK'] = sys.argv[31]
values['GCP_SUBNETWORK'] = sys.argv[32]
values['GKE_SUBNET_RANGE'] = sys.argv[33]
values['MEMORYSTORE_CONNECTIVITY'] = sys.argv[34]
values['MEMORYSTORE_INSTANCE_NAME'] = sys.argv[35]
values['MEMORYSTORE_TIER'] = sys.argv[36]
values['MEMORYSTORE_SIZE_GB'] = sys.argv[37]
values['MEMORYSTORE_PORT'] = sys.argv[38]
values['MEMORYSTORE_TLS_ENABLED'] = sys.argv[39]
values['MEMORYSTORE_AUTH_STRING'] = shlex.quote(sys.argv[40]) if sys.argv[40] else ''
values['PSC_SERVICE_ATTACHMENT'] = sys.argv[41]
values['PSC_ENDPOINT_NAME'] = sys.argv[42]
values['PSC_SUBNET_NAME'] = sys.argv[43]
values['PSC_SUBNET_RANGE'] = sys.argv[44]
values['GKE_MANAGE_DNS'] = sys.argv[45]
values['GCP_DNS_ZONE_NAME'] = sys.argv[46]
values['MONGODB_BACKEND'] = sys.argv[47]
values['GCS_FUSE_ENABLED'] = '1' if sys.argv[3].lower() in ('y', 'yes', '1') else '0'
values['CLOUD_SQL_ENABLED'] = '1' if sys.argv[4].lower() in ('y', 'yes', '1') else '0'
values['EXTERNAL_PROXY_ENABLED'] = '1' if sys.argv[5].lower() in ('y', 'yes', '1') else '0'
values['NEWT_NETWORK_EXTERNAL'] = 'true' if values['EXTERNAL_PROXY_ENABLED'] == '1' else 'false'
values['LOCAL_REDIS_MAIN'] = '1' if sys.argv[6].lower() in ('y', 'yes', '1') else '0'
values['PUBLIC_DOMAIN_NAME'] = sys.argv[7]
values['POSTGRES_HOST'] = sys.argv[12]
values['POSTGRES_PORT'] = sys.argv[13]
values['NEWT_DOCKER_NETWORK'] = sys.argv[14]
values['KPI_DNS_SERVER'] = sys.argv[15]
values['KOBOFORM_PUBLIC_SUBDOMAIN'] = sys.argv[16]
values['KOBOCAT_PUBLIC_SUBDOMAIN'] = sys.argv[17]
values['ENKETO_PUBLIC_SUBDOMAIN'] = sys.argv[18]
for key in ('MONGO_ROOT_PASSWORD', 'MONGO_USER_PASSWORD', 'REDIS_CACHE_PASSWORD'):
    if values.get(key) in (None, '', 'CHANGE_ME'):
        values[key] = secrets.token_hex(24)
if values['REDIS_BACKEND'] == 'local':
  if values.get('REDIS_MAIN_PASSWORD') in (None, '', 'CHANGE_ME'):
    values['REDIS_MAIN_PASSWORD'] = secrets.token_hex(24)
else:
  redis_uri = urllib.parse.urlsplit(sys.argv[9])
  redis_password = urllib.parse.unquote(redis_uri.password or '')
  values['REDIS_MAIN_PASSWORD'] = shlex.quote(redis_password) if redis_password else ''
if values.get('POSTGRES_PASSWORD') in (None, '', 'CHANGE_ME'):
    values['POSTGRES_PASSWORD'] = 'Kobo-9z-' + secrets.token_urlsafe(32)
if values['DEPLOY_MODE'] == 'local':
    values['PUBLIC_DOMAIN_NAME'] = 'localhost'
    values['PUBLIC_REQUEST_SCHEME'] = 'http'
    values['POSTGRES_HOST'] = 'postgres-local'
    mongo_user = urllib.parse.quote_plus(values['MONGO_ROOT_USERNAME'])
    mongo_password = urllib.parse.quote_plus(values['MONGO_ROOT_PASSWORD'])
    values['MONGO_DB_URL'] = f"'mongodb://{mongo_user}:{mongo_password}@mongo-local:27017/formhub?authSource=admin'"
    values['GCS_FUSE_ENABLED'] = '0'
    values['CLOUD_SQL_ENABLED'] = '0'
    values['NGINX_BIND_ADDRESS'] = '127.0.0.1'
    values['NGINX_BIND_PORT'] = '8080'
    values['NGINX_INTERNAL_API_PORT'] = '8080'
    values['KOBOFORM_DOCKER_ALIAS'] = f"{values['KOBOFORM_PUBLIC_SUBDOMAIN']}.localhost"
    values['KOBOCAT_DOCKER_ALIAS'] = f"{values['KOBOCAT_PUBLIC_SUBDOMAIN']}.localhost"
    values['ENKETO_DOCKER_ALIAS'] = f"{values['ENKETO_PUBLIC_SUBDOMAIN']}.localhost"
else:
    values['PUBLIC_REQUEST_SCHEME'] = 'https' if values['EXTERNAL_PROXY_ENABLED'] == '1' or values['DEPLOY_TARGET'] == 'helm' else 'http'
    if values['MONGODB_BACKEND'] == 'cluster':
        values['MONGODB_ENABLED'] = '1'
        mongo_user = urllib.parse.quote_plus(values['MONGO_ROOT_USERNAME'])
        mongo_password = urllib.parse.quote_plus(values['MONGO_ROOT_PASSWORD'])
        values['MONGO_DB_URL'] = f"'mongodb://{mongo_user}:{mongo_password}@mongo:27017/formhub?authSource=admin'"
    else:
        values['MONGODB_ENABLED'] = '0'
        values['MONGO_DB_URL'] = shlex.quote(sys.argv[8])
    if values['LOCAL_REDIS_MAIN'] == '0':
        values['REDIS_MAIN_URL'] = shlex.quote(sys.argv[9])
    if values['CLOUD_SQL_ENABLED'] == '1':
        values['CLOUD_SQL_INSTANCE_CONNECTION_NAME'] = sys.argv[10]
    if values['GCS_FUSE_ENABLED'] == '1':
        values['GCS_BUCKET_NAME'] = sys.argv[11]
    if values['EXTERNAL_PROXY_ENABLED'] == '1':
        values['NGINX_BIND_ADDRESS'] = '127.0.0.1'
        values['NGINX_BIND_PORT'] = '8080'
    values['NGINX_INTERNAL_API_PORT'] = '8080'
    values['KOBOFORM_DOCKER_ALIAS'] = f"{values['KOBOFORM_PUBLIC_SUBDOMAIN']}.{values['INTERNAL_DOMAIN_NAME']}"
    values['KOBOCAT_DOCKER_ALIAS'] = f"{values['KOBOCAT_PUBLIC_SUBDOMAIN']}.{values['INTERNAL_DOMAIN_NAME']}"
    values['ENKETO_DOCKER_ALIAS'] = f"{values['ENKETO_PUBLIC_SUBDOMAIN']}.{values['INTERNAL_DOMAIN_NAME']}"
if values['LOCAL_REDIS_MAIN'] == '1':
    redis_password = urllib.parse.quote(values['REDIS_MAIN_PASSWORD'], safe='')
    values['REDIS_MAIN_URL'] = f'redis://:{redis_password}@redis-main:6379/0'
p.write_text('\n'.join(f'{k}={v}' for k, v in values.items()) + '\n')
PY
chmod 600 "$env_file"

if [[ "$deployment_target" == helm && "$helm_profile" == gke ]]; then
  command -v gcloud >/dev/null || { echo 'Google Cloud CLI is required for the gke profile.' >&2; exit 1; }
  command -v kubectl >/dev/null || { echo 'kubectl is required for the gke profile.' >&2; exit 1; }
  provision_action=validate
  [[ "$gke_resource_action" == create ]] && provision_action=apply
  "$root/scripts/provision-gke.sh" "$provision_action" "$env_file"
fi

if [[ "$deployment_target" == docker && ( "$proxy" == yes || "$proxy" == y ) ]]; then
  docker network inspect "$newt_network" >/dev/null 2>&1 || {
    echo "The selected Pangolin/Newt Docker network does not exist: $newt_network" >&2
    echo 'Create/attach the Newt network first, then rerun the installer and select it.' >&2
    echo 'Existing user-defined bridge networks:' >&2
    docker network ls --filter driver=bridge --format '  {{.Name}}' | sed '/  bridge$/d' >&2
    exit 1
  }
  newt_attached=0
  while IFS= read -r container; do
    [[ -n "$container" ]] || continue
    image=$(docker inspect --format '{{.Config.Image}}' "$container" 2>/dev/null || true)
    if [[ "$container" == *newt* || "$image" == fosrl/newt* ]]; then
      newt_attached=1
      break
    fi
  done < <(docker network inspect --format '{{range .Containers}}{{println .Name}}{{end}}' "$newt_network")
  if [[ "$newt_attached" != 1 ]]; then
    echo "No Newt container is attached to the selected network: $newt_network" >&2
    echo 'Attach Newt to this network, then rerun the installer.' >&2
    exit 1
  fi
fi

mkdir -p "$root/runtime/secrets/google"
"$root/scripts/render-config.sh" "$env_file"
if [[ "$deployment_target" == docker ]]; then
  "$root/scripts/bootstrap-host.sh"
  profiles=()
  grep -q '^DEPLOY_MODE=local$' "$env_file" && profiles+=(--profile local-db)
  grep -q '^CLOUD_SQL_ENABLED=1$' "$env_file" && profiles+=(--profile cloud-sql)
  grep -q '^GCS_FUSE_ENABLED=1$' "$env_file" && profiles+=(--profile gcsfuse)
  grep -q '^LOCAL_REDIS_MAIN=1$' "$env_file" && profiles+=(--profile local-redis-main)
  docker compose --env-file "$env_file" -f "$root/compose/compose.yaml" "${profiles[@]}" config >/dev/null
else
  command -v helm >/dev/null || { echo 'Helm 3 is required for the helm target.' >&2; exit 1; }
  "$root/scripts/deploy-helm.sh" config
fi
echo "Configuration written to $env_file"
if [[ "$deployment_target" == docker ]] && grep -q '^CLOUD_SQL_ENABLED=1$\|^GCS_FUSE_ENABLED=1$' "$env_file"; then
  echo 'Place the shared key at runtime/secrets/google/service-account.json.'
fi
if [[ "$deployment_target" == helm ]]; then
  if [[ "$helm_profile" == gke ]]; then
    echo 'Next: point the public DNS records at GKE_STATIC_IP_ADDRESS, then run scripts/deploy-helm.sh up.'
  else
    echo 'Next: configure Kubernetes storage and ingress, then run scripts/deploy-helm.sh up.'
  fi
else
  echo 'Next: run scripts/deploy.sh up.'
fi
