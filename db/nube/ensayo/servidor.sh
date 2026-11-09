#!/bin/bash
# servidor postgres de ensayo: certificado propio, ssl obligatorio y un propietario sin superusuario
set -e
cd /var/lib/postgresql
openssl req -new -x509 -days 2 -nodes -subj "/CN=nube-simulada" -keyout servidor.key -out servidor.crt 2>/dev/null
chown postgres servidor.key servidor.crt
chmod 600 servidor.key
cat > pg_hba.conf <<FIN
local     all all     trust
hostnossl all all all reject
hostssl   all all all scram-sha-256
FIN
cp /ensayo/crear_propietario.sh /docker-entrypoint-initdb.d/
exec docker-entrypoint.sh postgres -c ssl=on -c ssl_cert_file=/var/lib/postgresql/servidor.crt \
  -c ssl_key_file=/var/lib/postgresql/servidor.key -c hba_file=/var/lib/postgresql/pg_hba.conf
