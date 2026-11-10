# Bodegas del Atuel

Sistema de gestión de una empresa vitivinícola: producción de uva, vinos, clientes, ventas en salas, ingresos al depósito central y transferencias a las salas. Las reglas de negocio viven en la base de datos PostgreSQL (constraints, funciones, procedimientos y triggers); encima hay una API REST en FastAPI y un front en HTML, CSS y JavaScript.

Trabajo práctico integrador de Bases de Datos, UTN Facultad Regional San Rafael, 2026.

## Versión en la nube

- Front: https://bodegas-front.onrender.com

- API: https://bodegas-api-wton.onrender.com , documentación en `/docs`

## Requisitos

- Docker y Docker Compose.
- Puertos libres en la máquina: 5432 (base), 8000 (API) y 8080 (front). Se pueden cambiar en el `.env`.

## Levantar todo en local

```
cp .env.example .env        # y cambiar las claves
docker compose up -d --build
```

Esto levanta tres contenedores:

| Servicio | Qué es | Dirección |
|---|---|---|
| `db` | PostgreSQL 16 | `localhost:5432` |
| `api` | API REST | `http://localhost:8000` (documentación en `http://localhost:8000/docs`) |
| `front` | Front servido con nginx | `http://localhost:8080` |

## Migraciones

Están en `db/migrations/` y se aplican solas, en orden, la primera vez que arranca el contenedor de la base con el volumen vacío:

| Archivo | Contenido |
|---|---|
| `001_esquema.sql` | Tipos, dominios, tablas, claves primarias y foráneas |
| `002_constraints.sql` | UNIQUE, CHECK y DEFAULT |
| `003_funciones.sql` | Funciones de descuento, totales, stock y antigüedad |
| `004_procedimientos.sql` | Procesar ingresos y transferencias |
| `005_triggers.sql` | Triggers de las reglas de negocio |
| `006_vistas.sql` | Vistas |
| `007_roles.sql` | Roles `bodega_app` (API) y `bodega_lectura` (reportes) |
| `008_indices.sql` | Índices |
| `009_claves_roles.sh` | Claves de los roles, tomadas del `.env` |

Para crear la base de nuevo desde cero:

```
docker compose down -v
docker compose up -d
```

Para aplicarlas sobre una base remota vacía, ver la etapa 8 más abajo.

## Carga de datos

```
docker compose run --rm seed
```

Genera con una semilla fija unos 20.000 clientes, 150.000 comprobantes y 500.000 renglones, con fechas relativas al día en que se corre, los carga y corre las consultas de control. Tarda alrededor de medio minuto. Los detalles están en `db/seed/README.md`. También hay un volcado de la base cargada en `db/seed/dump_completo.sql.gz`.

## Pruebas

Pruebas de las reglas de la base (RN-01 a RN-15 y roles), que terminan en ROLLBACK y no cambian los datos:

```
docker compose exec -T db psql -U bodega_owner -d bodegas -f - < db/tests/db_tests.sql
```

Pruebas de la API contra la base real, con la base cargada:

```
docker compose run --rm api-pruebas
```

Demostración de concurrencia (dos sesiones vendiendo la última botella):

```
bash db/tests/concurrencia/demo.sh
```

Medición de índices antes y después de `008_indices.sql`:

```
docker compose run --rm indices
```

## Consultas

Las consultas de la sección 8 de la consigna están en `consultas/` (`update.sql`, `insert.sql`, `delete.sql` y `select.sql`). Las que modifican datos terminan en ROLLBACK:

```
docker compose exec -T db psql -U bodega_owner -d bodegas -f - < consultas/select.sql
```

## Despliegue en la nube

Los scripts están en `db/nube/` y la configuración de Render en `render.yaml`. Se copia `.env.nube.example` a `.env.nube` con los datos de la base en la nube y se corren con el servicio `nube`:

```
docker compose run --rm nube bash db/nube/aplicar_migraciones.sh
docker compose run --rm nube bash db/nube/carga_reducida.sh
docker compose run --rm nube bash db/nube/backup.sh
docker compose run --rm nube bash db/nube/restaurar.sh backups/<archivo>.dump
bash db/nube/probar_regla.sh https://<url-de-la-api>
```

Los pasos completos están en `docs/etapas/etapa-8.md`.

## Estructura

```
db/migrations/   esquema, constraints, funciones, procedimientos, triggers, vistas, roles e indices
db/seed/         catalogos en csv, script de carga, controles y volcado
db/tests/        pruebas de la base y demostracion de concurrencia
db/indices/      medicion de indices
db/nube/         scripts para la base en la nube
consultas/       consultas de la seccion 8
api/             api rest (fastapi y psycopg)
front/           front (html, css y javascript)
docs/modelo/     esquema relacional, diccionario de datos, normalizacion y decisiones de diseno
docs/etapas/     desarrollo de cada etapa
docs/resultados/ salidas de las pruebas, mediciones y controles
```

## Documentación

- Modelo de datos: `docs/modelo/`.
- Desarrollo y criterios de aceptación de cada etapa: `docs/etapas/etapa-1.md` a `etapa-8.md`.
- Resultados (planes de ejecución, tiempos, controles, pruebas): `docs/resultados/`.
