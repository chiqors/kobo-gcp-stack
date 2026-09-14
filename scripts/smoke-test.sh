#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
source "$root/.env"
scheme=${PUBLIC_REQUEST_SCHEME:-https}
port=''
[[ "${EXTERNAL_PROXY_ENABLED:-0}" == 0 ]] && port=":${NGINX_BIND_PORT:-8080}"
curl --fail --silent --show-error --max-time 20 "${scheme}://${KOBOFORM_PUBLIC_SUBDOMAIN}.${PUBLIC_DOMAIN_NAME}${port}/service_health/" >/dev/null
curl --fail --silent --show-error --max-time 20 "${scheme}://${KOBOFORM_PUBLIC_SUBDOMAIN}.${PUBLIC_DOMAIN_NAME}${port}/static/js/global_t.js" >/dev/null
curl --fail --silent --show-error --max-time 20 "${scheme}://${KOBOCAT_PUBLIC_SUBDOMAIN}.${PUBLIC_DOMAIN_NAME}${port}/service_health/minimal/" >/dev/null
curl --fail --silent --show-error --max-time 20 "${scheme}://${ENKETO_PUBLIC_SUBDOMAIN}.${PUBLIC_DOMAIN_NAME}${port}/" >/dev/null
echo 'public endpoint smoke checks passed'
