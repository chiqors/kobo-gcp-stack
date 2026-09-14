\set ON_ERROR_STOP on

-- Run as a Cloud SQL administrative user with variables:
-- psql ... -v app_user=kobo -v app_password='...' -v kpi_db=koboform -v kc_db=kobocat -f provision-cloud-sql.sql
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'app_user', :'app_password')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'app_user') \gexec
SELECT format('CREATE DATABASE %I OWNER %I', :'kpi_db', :'app_user')
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = :'kpi_db') \gexec
SELECT format('CREATE DATABASE %I OWNER %I', :'kc_db', :'app_user')
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = :'kc_db') \gexec

\connect :kpi_db
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_topology;
CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;
CREATE EXTENSION IF NOT EXISTS postgis_tiger_geocoder;

\connect :kc_db
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_topology;
CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;
CREATE EXTENSION IF NOT EXISTS postgis_tiger_geocoder;
