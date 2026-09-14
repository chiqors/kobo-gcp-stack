#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd)
env_file="$root/.env"

choose() {
  local prompt="$1" default="$2" answer
  read -r -p "$prompt [$default]: " answer || true
  printf '%s' "${answer:-$default}"
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

mode=$(choose 'Deployment mode (local/gcp)' 'local')
[[ "$mode" == local || "$mode" == gcp ]] || { echo 'Choose local or gcp' >&2; exit 2; }

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
  gcs=$(choose 'Enable GCS FUSE? (yes/no)' 'yes')
  sql=$(choose 'Enable Cloud SQL Proxy? (yes/no)' 'yes')
  proxy=$(choose 'Use external Pangolin/Newt proxy network? (yes/no)' 'yes')
  local_redis=$(choose 'Run Redis main locally? (yes/no)' 'no')
  if [[ "$proxy" == yes || "$proxy" == y ]]; then
    public_domain=$(choose 'Public base domain (for example kobo.example.org)' 'example.org')
    current_newt_network=$(sed -n 's/^NEWT_DOCKER_NETWORK=//p' "$env_file" | tail -1)
    newt_network=$(choose_newt_network "${current_newt_network:-newt}")
    kpi_dns_server=$(choose 'Pangolin private DNS server' '100.96.128.1')
  else
    public_domain=localhost
    newt_network=newt
    kpi_dns_server=127.0.0.11
  fi
  mongo_url=$(choose 'MongoDB 8 connection URI' 'mongodb://kobo:password@mongodb.internal:27017/formhub?authSource=formhub')
  if [[ "$local_redis" == yes || "$local_redis" == y ]]; then
    redis_url=''
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

python3 - "$env_file" "$mode" "$gcs" "$sql" "$proxy" "$local_redis" "$public_domain" "$mongo_url" "$redis_url" "$cloud_sql_instance" "$gcs_bucket" "$postgres_host" "$postgres_port" "$newt_network" "$kpi_dns_server" "$koboform_subdomain" "$kobocat_subdomain" "$enketo_subdomain" <<'PY'
import pathlib, secrets, shlex, sys, urllib.parse
p = pathlib.Path(sys.argv[1])
values = {}
for line in p.read_text().splitlines():
    if line and not line.startswith('#') and '=' in line:
        k, v = line.split('=', 1); values[k] = v
values['DEPLOY_MODE'] = sys.argv[2]
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
for key in ('MONGO_ROOT_PASSWORD', 'MONGO_USER_PASSWORD', 'REDIS_MAIN_PASSWORD', 'REDIS_CACHE_PASSWORD'):
    if values.get(key) in (None, '', 'CHANGE_ME'):
        values[key] = secrets.token_hex(24)
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
    values['PUBLIC_REQUEST_SCHEME'] = 'https' if values['EXTERNAL_PROXY_ENABLED'] == '1' else 'http'
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

if [[ "$proxy" == yes || "$proxy" == y ]]; then
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
"$root/scripts/bootstrap-host.sh"
"$root/scripts/render-config.sh" "$env_file"
profiles=()
grep -q '^DEPLOY_MODE=local$' "$env_file" && profiles+=(--profile local-db)
grep -q '^CLOUD_SQL_ENABLED=1$' "$env_file" && profiles+=(--profile cloud-sql)
grep -q '^GCS_FUSE_ENABLED=1$' "$env_file" && profiles+=(--profile gcsfuse)
grep -q '^LOCAL_REDIS_MAIN=1$' "$env_file" && profiles+=(--profile local-redis-main)
docker compose --env-file "$env_file" -f "$root/compose/compose.yaml" "${profiles[@]}" config >/dev/null
echo "Configuration written to $env_file"
if grep -q '^CLOUD_SQL_ENABLED=1$\|^GCS_FUSE_ENABLED=1$' "$env_file"; then
  echo 'Place the shared key at runtime/secrets/google/service-account.json.'
fi
echo 'Next: run scripts/deploy.sh up.'
