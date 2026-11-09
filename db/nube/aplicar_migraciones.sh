#!/bin/bash
# aplica las migraciones en orden sobre una base remota vacia con el rol propietario.
# toma la conexion de PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD y PGSSLMODE
# uso, desde la raiz del repo: bash db/nube/aplicar_migraciones.sh
set -e

: "${PGHOST:?falta PGHOST}"
: "${PGDATABASE:?falta PGDATABASE}"
: "${PGUSER:?falta PGUSER}"
: "${PGPASSWORD:?falta PGPASSWORD}"
export PGSSLMODE=${PGSSLMODE:-require}

for archivo in db/migrations/*.sql; do
  echo "aplicando $archivo"
  psql -v ON_ERROR_STOP=1 -q -f "$archivo"
done

echo "asignando las claves de los roles"
bash db/migrations/009_claves_roles.sh

psql -v ON_ERROR_STOP=1 -f db/nube/ver_conexion.sql
