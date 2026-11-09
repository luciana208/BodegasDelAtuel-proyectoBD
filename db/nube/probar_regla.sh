#!/bin/bash
# intenta vender por la api un vino sin stock en la sala 1 y muestra el rechazo de la base
# uso: bash db/nube/probar_regla.sh https://url-de-la-api
api=${1:?falta la url de la api}

echo "GET /salud"
curl -s "$api/salud"
echo

vino=$(curl -s "$api/reportes/vinos-sin-stock?sala=1" | grep -o '"cod_vino":[0-9]*' | head -1 | cut -d: -f2)
echo "vino sin stock en la sala 1: $vino"
echo "POST /comprobantes"
curl -s -X POST "$api/comprobantes" -H 'Content-Type: application/json' \
  -d "{\"id_cliente\": 1, \"id_sala\": 1, \"renglones\": [{\"cod_vino\": $vino, \"cantidad\": 1}]}" \
  -w '\nhttp %{http_code}\n'
