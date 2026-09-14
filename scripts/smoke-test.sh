#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
source "$root/.env"
scheme=${PUBLIC_REQUEST_SCHEME:-https}
port=''
[[ "${EXTERNAL_PROXY_ENABLED:-0}" == 0 ]] && port=":${NGINX_BIND_PORT:-8080}"
curl_check() {
  local subdomain="$1" path="$2"
  local host="${subdomain}.${PUBLIC_DOMAIN_NAME}"
  if [[ "${EXTERNAL_PROXY_ENABLED:-0}" == 1 ]]; then
    curl --fail --silent --show-error --max-time 20 \
      --header "Host: $host" \
      "http://127.0.0.1:${NGINX_BIND_PORT:-8080}${path}" >/dev/null
  else
    curl --fail --silent --show-error --max-time 20 \
      "${scheme}://${host}${port}${path}" >/dev/null
  fi
}

curl_check "$KOBOFORM_PUBLIC_SUBDOMAIN" /service_health/
curl_check "$KOBOFORM_PUBLIC_SUBDOMAIN" /static/js/global_t.js
curl_check "$KOBOCAT_PUBLIC_SUBDOMAIN" /service_health/minimal/
curl_check "$ENKETO_PUBLIC_SUBDOMAIN" /
echo 'endpoint smoke checks passed'
