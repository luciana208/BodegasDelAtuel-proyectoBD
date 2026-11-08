#!/bin/bash
# genera el volcado completo de la base cargada con pg_dump del contenedor db
# uso, desde la raiz del repo: bash db/seed/generar_dump.sh
set -e

destino=${1:-db/seed/dump_completo.sql.gz}
docker compose exec -T db pg_dump -U "${POSTGRES_USER:-bodega_owner}" -d "${POSTGRES_DB:-bodegas}" \
  --no-owner | gzip > "$destino"
ls -lh "$destino"
