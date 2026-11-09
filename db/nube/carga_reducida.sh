#!/bin/bash
# carga reducida para el plan gratuito y consultas de control, con la misma semilla
# uso, desde la raiz del repo: bash db/nube/carga_reducida.sh
set -e

export PGSSLMODE=${PGSSLMODE:-require}
export CANT_CLIENTES=${CANT_CLIENTES:-3000}
export CANT_COMPROBANTES=${CANT_COMPROBANTES:-15000}
export CANT_INGRESOS=${CANT_INGRESOS:-600}
export TRANSFERENCIAS_POR_SALA=${TRANSFERENCIAS_POR_SALA:-40}
export RESULTADOS=${RESULTADOS:-docs/resultados/nube}
mkdir -p "$RESULTADOS"

python db/seed/cargar.py
psql -v ON_ERROR_STOP=1 -f db/seed/control.sql > "$RESULTADOS/carga_control.txt"
echo "controles en $RESULTADOS/carga_control.txt"
