#!/bin/bash
# corre las dos sesiones al mismo tiempo contra el contenedor db y guarda la salida
# uso, desde la raiz del repo: bash db/tests/concurrencia/demo.sh
set -e

dir=db/tests/concurrencia
salida=docs/resultados
mkdir -p "$salida"

psql_db() {
  docker compose exec -T db psql -U "${POSTGRES_USER:-bodega_owner}" -d "${POSTGRES_DB:-bodegas}" -f - "$@"
}

psql_db < "$dir/preparar.sql"

psql_db < "$dir/sesion_a.sql" > "$salida/concurrencia_sesion_a.txt" 2>&1 &
pid_a=$!
psql_db < "$dir/sesion_b.sql" > "$salida/concurrencia_sesion_b.txt" 2>&1 &
pid_b=$!
wait $pid_a $pid_b

psql_db < "$dir/limpiar.sql" > /dev/null

echo "salida en $salida/concurrencia_sesion_a.txt y $salida/concurrencia_sesion_b.txt"
