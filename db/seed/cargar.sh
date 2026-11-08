#!/bin/bash
# genera y carga los datos y despues corre las consultas de control
set -e

python cargar.py
psql -v ON_ERROR_STOP=1 -f control.sql > "${RESULTADOS:-/resultados}/carga_control.txt"
psql -v ON_ERROR_STOP=1 -f huella.sql > "${RESULTADOS:-/resultados}/carga_huella.txt"
echo "resultados en docs/resultados: carga_tiempos.txt, carga_control.txt y carga_huella.txt"
