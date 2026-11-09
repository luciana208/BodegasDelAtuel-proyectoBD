#!/bin/bash
# restaura un backup en una base nueva del mismo servidor y compara los conteos con la base de origen
# uso, desde la raiz del repo: bash db/nube/restaurar.sh archivo.dump [base_nueva]
set -e

export PGSSLMODE=${PGSSLMODE:-require}
archivo=${1:?falta el archivo del backup}
destino=${2:-${PGDATABASE}_restaurada}
salida=${RESULTADOS:-docs/resultados/nube}
mkdir -p "$salida"

createdb "$destino"
pg_restore --no-owner --exit-on-error --dbname="$destino" "$archivo"

psql -At -v ON_ERROR_STOP=1 -f db/nube/conteos.sql > "$salida/conteos_origen.txt"
PGDATABASE="$destino" psql -At -v ON_ERROR_STOP=1 -f db/nube/conteos.sql > "$salida/conteos_restaurada.txt"

if diff "$salida/conteos_origen.txt" "$salida/conteos_restaurada.txt"; then
  echo "los conteos de las $(wc -l < "$salida/conteos_origen.txt") tablas coinciden entre $PGDATABASE y $destino"
else
  echo "los conteos no coinciden"
  exit 1
fi
