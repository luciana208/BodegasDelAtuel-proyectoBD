#!/bin/bash
# ensayo del despliegue contra un postgres local que imita la nube (ssl obligatorio y
# propietario sin superusuario). corre todos los scripts de db/nube y guarda la salida
# en docs/resultados/nube. las claves se generan al azar en cada ensayo.
# uso, desde la raiz del repo y con el compose levantado: bash db/nube/ensayo_local.sh
set -e

salida=docs/resultados/nube
mkdir -p "$salida"
clave() { head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n'; }
clave_owner=$(clave)
clave_app=$(clave)
clave_lectura=$(clave)
red=$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}' "$(docker compose ps -q db)")

docker rm -f nube-simulada api-ensayo >/dev/null 2>&1 || true
docker run -d --name nube-simulada --network "$red" -e POSTGRES_PASSWORD="$(clave)" -e CLAVE_OWNER="$clave_owner" \
  -v "$PWD/db/nube/ensayo:/ensayo:ro" postgres:17 bash /ensayo/servidor.sh >/dev/null
until docker exec nube-simulada pg_isready -U postgres -h localhost >/dev/null 2>&1 \
      && docker logs nube-simulada 2>&1 | grep -q "init process complete"; do sleep 2; done
sleep 3

nube() {
  docker compose run --rm -T -e PGHOST=nube-simulada -e PGPORT=5432 -e PGDATABASE=bodegas -e PGUSER=bodega_owner \
    -e PGPASSWORD="$clave_owner" -e PGSSLMODE=require -e APP_DB_PASSWORD="$clave_app" \
    -e LECTURA_DB_PASSWORD="$clave_lectura" -e RESULTADOS="$salida" "$@" nube bash -c "$comando"
}

echo "migraciones"
comando="bash db/nube/aplicar_migraciones.sh"; nube > "$salida/migraciones.txt" 2>&1
echo "carga reducida"
comando="bash db/nube/carga_reducida.sh"; nube > "$salida/carga_reducida.txt" 2>&1
echo "backup y restauracion"
comando="bash db/nube/backup.sh backups/ensayo.dump && bash db/nube/restaurar.sh backups/ensayo.dump bodegas_restaurada"
nube > "$salida/backup_restauracion.txt" 2>&1
echo "conexion sin ssl"
comando="psql -c 'SELECT 1'"; nube -e PGSSLMODE=disable > "$salida/conexion_sin_ssl.txt" 2>&1 || true
echo "conexion con una clave equivocada"
comando="PGPASSWORD=clave_incorrecta psql -c 'SELECT 1'"; nube > "$salida/conexion_clave_incorrecta.txt" 2>&1 || true

echo "api conectada a la base de ensayo"
docker run -d --name api-ensayo --network "$red" -p 127.0.0.1:8001:8000 \
  -e DATABASE_URL="postgresql://bodega_app:$clave_app@nube-simulada:5432/bodegas?sslmode=require" \
  "$(docker inspect -f '{{.Config.Image}}' "$(docker compose ps -q api)")" >/dev/null
until curl -s localhost:8001/salud >/dev/null; do sleep 1; done
bash db/nube/probar_regla.sh http://localhost:8001 > "$salida/regla_en_la_nube.txt" 2>&1

docker rm -f api-ensayo nube-simulada >/dev/null
# lo que escribio el contenedor queda a nombre de quien corre el ensayo
comando="rm -f backups/ensayo.dump && chown -R $(id -u):$(id -g) $salida backups"; nube >/dev/null 2>&1
echo "salida en $salida"
