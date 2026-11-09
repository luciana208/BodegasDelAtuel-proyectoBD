#!/bin/bash
# muestra que un texto malicioso en un filtro se trata como texto comun
# uso, con la api levantada: bash api/demo_inyeccion.sh [url de la api]
api=${1:-http://localhost:8000}

pedir() {
  echo "GET /vinos?$1"
  curl -s -G "$api/vinos" --data-urlencode "$1" --data-urlencode "tamanio=3" -w '\nhttp %{http_code}\n\n'
}

echo "total de vinos antes:"
curl -s "$api/vinos?tamanio=1" | grep -o '"total":[0-9]*'
echo

pedir "nombre=Malbec"
pedir "nombre=' OR '1'='1"
pedir "nombre='; DROP TABLE vino; --"
pedir "tipo=tinto' OR '1'='1"

echo "total de vinos despues:"
curl -s "$api/vinos?tamanio=1" | grep -o '"total":[0-9]*'
