#!/bin/bash
# genera un backup con pg_dump en formato custom de la base indicada por las variables PG*
# uso, desde la raiz del repo: bash db/nube/backup.sh [archivo]
set -e

export PGSSLMODE=${PGSSLMODE:-require}
archivo=${1:-backups/bodegas_$(date +%Y%m%d_%H%M%S).dump}
mkdir -p "$(dirname "$archivo")"
pg_dump --format=custom --no-owner --file="$archivo"
ls -lh "$archivo"
