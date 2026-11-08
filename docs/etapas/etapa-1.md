# Etapa 1: modelado

## Qué hicimos

Arrancamos leyendo el escenario y anotando las entidades, los atributos y las reglas que iban a necesitar algo más que una columna. Esta vez lo hicimos al revés de lo habitual: primero escribimos el esquema en SQL y después, con el esquema ya probado, armamos el DER a partir de él.

El esquema quedó en `db/migrations/001_esquema.sql`, agrupado por tema: localidades, salas y empleados; producción de uva; vinos; clientes; ventas y stock; logística y auditoría. Son 30 tablas, 5 tipos ENUM y 2 dominios. En este archivo solo van las tablas, las claves primarias, las foráneas con sus acciones y los NOT NULL. Los UNIQUE, CHECK y DEFAULT que faltan se agregan en la etapa 2.

Algunas cosas que nos costaron más:

- La jerarquía de clientes. Probamos las tres opciones y nos quedamos con supertipo más subtipos. Para que un cliente no quede en dos subtipos usamos una FK compuesta `(id_cliente, tipo)` con el tipo fijo en cada subtabla.
- La provincia. Al principio estaba en localidad y en finca, pero depende del departamento, así que sacamos una tabla `departamento` para no tener una dependencia transitiva.
- El encargado regional. Va en localidad y no en sala, porque es uno solo por localidad aunque haya varias salas.
- El código postal no es clave porque en Mendoza hay localidades que lo comparten.
- Parcela es la entidad débil: su clave es `(id_finca, nro_parcela)`.

Para probar que el esquema se crea desde cero usamos el contenedor de PostgreSQL 16 del `docker-compose.yml`, que monta `db/migrations` en `/docker-entrypoint-initdb.d`. Con el volumen vacío corre los archivos en orden.

```
cp .env.example .env
docker compose down -v
docker compose up -d db
docker compose exec db psql -U bodega_owner -d bodegas -c '\dt'
```

## Documentos

- Esquema relacional y cardinalidades: `docs/modelo/esquema_relacional.md`.
- Diccionario de datos: `docs/modelo/diccionario_datos.md`.
- Dependencias funcionales y 3FN: `docs/modelo/normalizacion.md`.
- Decisiones de diseño (jerarquía, claves, tipos, derivados, acciones referenciales) y guía para el DER: `docs/modelo/decisiones_diseno.md`.

El DER lo dibujamos aparte a partir del esquema.

## Criterios de aceptación

- [x] Todas las entidades de la sección 5 están representadas y sus cardinalidades son coherentes con el escenario. Están en `db/migrations/001_esquema.sql` y la tabla de cardinalidades al final de `docs/modelo/esquema_relacional.md`.
- [x] El esquema relacional está en 3FN y hay justificación escrita. En `docs/modelo/normalizacion.md`.
- [x] Ningún importe usa FLOAT y los estados no son texto libre. Todos los importes son NUMERIC y el estado usa el ENUM `estado_documento`. Se ve con `grep -niE 'float|real|double' db/migrations/001_esquema.sql`, que no devuelve nada.
- [x] `001_esquema.sql` corre de punta a punta sobre una base vacía. Se ve con `docker compose down -v && docker compose up -d db` y `docker compose logs db`, que termina en `PostgreSQL init process complete` sin errores.
- [x] El diccionario de datos coincide con el esquema físico. Comparamos columna por columna el tipo, los nulos y las acciones de las FK de `docs/modelo/diccionario_datos.md` contra el catálogo de la base, y dio 132 columnas sin diferencias. La lista de columnas de la base sale con:

```sql
SELECT c.relname, a.attname, format_type(a.atttypid, a.atttypmod), a.attnotnull
  FROM pg_attribute a
  JOIN pg_class c ON c.oid = a.attrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind = 'r' AND a.attnum > 0 AND NOT a.attisdropped
 ORDER BY 1, a.attnum;
```
