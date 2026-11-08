#!/bin/bash
# asigna las claves de bodega_app y bodega_lectura tomandolas de variables de entorno
set -e

: "${APP_DB_PASSWORD:?falta la variable APP_DB_PASSWORD}"
: "${LECTURA_DB_PASSWORD:?falta la variable LECTURA_DB_PASSWORD}"

psql -v ON_ERROR_STOP=1 \
     --username "${PGUSER:-$POSTGRES_USER}" \
     --dbname "${PGDATABASE:-$POSTGRES_DB}" \
     -v clave_app="$APP_DB_PASSWORD" \
     -v clave_lectura="$LECTURA_DB_PASSWORD" <<'EOSQL'
ALTER ROLE bodega_app PASSWORD :'clave_app';
ALTER ROLE bodega_lectura PASSWORD :'clave_lectura';
EOSQL
