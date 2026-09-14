#!/usr/bin/env bash
set -euo pipefail
for database in "$KPI_POSTGRES_DB" "$KC_POSTGRES_DB"; do
  exists=$(psql --username "$POSTGRES_USER" --dbname postgres --tuples-only --command "SELECT 1 FROM pg_database WHERE datname = '$database'" | tr -d '[:space:]')
  [[ "$exists" == 1 ]] || psql --set ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres --command "CREATE DATABASE \"$database\" OWNER \"$POSTGRES_USER\""
done
for database in "$KPI_POSTGRES_DB" "$KC_POSTGRES_DB"; do
  psql --set ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$database" <<SQL
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_topology;
CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;
CREATE EXTENSION IF NOT EXISTS postgis_tiger_geocoder;
SQL
done
