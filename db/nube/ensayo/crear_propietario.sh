#!/bin/bash
# crea el rol propietario sin superusuario y la base vacia, como las que da un proveedor
set -e
psql -v ON_ERROR_STOP=1 --username postgres -v clave="$CLAVE_OWNER" <<'FIN'
CREATE ROLE bodega_owner LOGIN CREATEROLE CREATEDB PASSWORD :'clave';
CREATE DATABASE bodegas OWNER bodega_owner;
FIN
