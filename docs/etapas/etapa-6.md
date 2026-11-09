# Etapa 6: API REST

## Qué hicimos

La API está en `api/` y está hecha en Python con FastAPI y psycopg 3. No usamos ningún ORM ni armador de consultas: todo el SQL está escrito a mano en `api/app/datos.py`.

```
api/
  Dockerfile
  requirements.txt
  demo_inyeccion.sh
  app/
    config.py    lectura de variables de entorno
    db.py        pool de conexiones (psycopg_pool)
    datos.py     capa de acceso a datos, una funcion por consulta
    modelos.py   cuerpos de los pedidos
    errores.py   traduccion de sqlstate a http
    main.py      rutas
  tests/
    conftest.py, test_api.py, test_inyeccion.py
```

Se levanta junto con la base:

```
docker compose up -d
```

y queda en `http://localhost:8000`. La documentación OpenAPI que genera FastAPI está en `http://localhost:8000/docs` (y el JSON en `/openapi.json`, guardado también en `docs/resultados/api/openapi.json`).

### Conexión y rol

La API se conecta con `bodega_app`, el rol de lectura y escritura de la etapa 2, que no es dueño de nada ni superusuario. Los datos de conexión salen de variables de entorno: `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD` y `DB_SSLMODE`, o directamente `DATABASE_URL` (lo vamos a usar en la nube). En el `docker-compose.yml` la clave se toma de `APP_DB_PASSWORD` del `.env`, que no se sube al repositorio. El endpoint `/salud` devuelve el usuario con el que está conectada, y una de las pruebas verifica que sea `bodega_app`.

El pool (`psycopg_pool.ConnectionPool`) abre las conexiones al arrancar y las presta en cada pedido. Las conexiones trabajan en autocommit, así cada sentencia suelta es atómica. Cuando una operación tiene varias sentencias, `datos.py` abre una transacción explícita con `with conn.transaction():`, que hace `BEGIN` al entrar y `COMMIT` al salir, o `ROLLBACK` si hubo un error. Eso pasa en:

- `crear_vino` y `actualizar_vino`: el vino, su composición y sus maridajes. La suma de los cortes la revisa el constraint trigger diferido al hacer `COMMIT`, y si no da 100 se deshace todo.
- `crear_cliente` y `actualizar_cliente`: el cliente y su subtipo (y los permisos si es exportador).
- `crear_comprobante`: la cabecera y todos los renglones. Si un renglón no tiene stock, el trigger lo rechaza y no queda ni la cabecera ni los renglones anteriores.

### Lo que no hace la API

La API no calcula totales, descuentos ni stock. Para vender inserta la cabecera y los renglones con solo el vino y la cantidad; el precio, el descuento, los subtotales, el total y el descuento del stock los hacen los triggers. Para procesar transferencias e ingresos llama a `sp_procesar_transferencia` y `sp_procesar_ingreso`, y para terminarlos hace un UPDATE del estado que valida `trg_control_estado`. Los modelos de `modelos.py` solo controlan el formato (que un número sea número, que estén los campos obligatorios); por ejemplo el precio negativo no lo rechaza la API sino el CHECK de la base.

### Parámetros

Todas las consultas usan parámetros de psycopg (`%s` o `%(nombre)s`). Los filtros opcionales del catálogo no se arman concatenando: la consulta es siempre la misma y cada filtro tiene la forma `(%(tipo)s::tipo_vino IS NULL OR v.tipo = %(tipo)s::tipo_vino)`, así un filtro vacío no filtra.

## Endpoints

| Recurso | Rutas |
|---|---|
| Salud | `GET /salud` |
| Vinos | `GET /vinos` (filtros `tipo`, `cepa`, `bodega`, `anada`, `nombre`, paginación `pagina` y `tamanio`), `GET /vinos/{cod}`, `POST /vinos`, `PUT /vinos/{cod}`, `DELETE /vinos/{cod}` |
| Clientes | `GET /clientes` (filtros `tipo`, `nombre`, paginación), `GET /clientes/{id}`, `POST /clientes`, `PUT /clientes/{id}`, `DELETE /clientes/{id}` |
| Ventas | `POST /comprobantes`, `GET /comprobantes/{nro}` |
| Transferencias | `GET /transferencias`, `POST /transferencias`, `GET /transferencias/{nro}`, `POST /transferencias/{nro}/renglones`, `POST /transferencias/{nro}/terminar`, `POST /transferencias/{nro}/procesar` |
| Ingresos | `POST /ingresos`, `GET /ingresos/{cod}`, `POST /ingresos/{cod}/renglones`, `POST /ingresos/{cod}/terminar`, `POST /ingresos/{cod}/procesar` |
| Reportes | `GET /reportes/top-vinos` (S1), `/reportes/ventas-por-sala` (S8), `/reportes/vinos-sin-stock?sala=` (S6), `/reportes/transportista-activo` (S7), `/reportes/trazabilidad/{cod}` |
| Catálogos | `GET /cepas`, `/bodegas`, `/maridajes`, `/salas`, `/localidades`, `/transportistas` (para los formularios del front) |

La trazabilidad de un vino muestra sus datos y su composición, los ingresos por los que entró al depósito, las transferencias a las salas y las ventas y el stock actual de cada sala.

Los listados devuelven `{"pagina", "tamanio", "total", "datos"}`. El total sale de `count(*) OVER ()` en la misma consulta.

## Errores

`errores.py` tiene un manejador central para cualquier error de psycopg. Mira el SQLSTATE y elige el código HTTP:

| SQLSTATE | Situación | HTTP |
|---|---|---|
| 23505 | UNIQUE violado | 409 |
| 23503 | FK violada | 409 |
| 23514 | CHECK violado | 422 |
| 23502 | NOT NULL violado | 422 |
| P0001 | RAISE EXCEPTION de un trigger o procedimiento | 409 |
| 22P02 | Texto con formato inválido para el tipo | 400 |
| 22003, 22007, 22008 | Número fuera de rango o fecha inválida | 422 o 400 |
| 40001, 40P01 | Serialización o deadlock | 503 con `Retry-After` |
| otro | | 500 |

La respuesta tiene siempre la forma `{"error": "...", "sqlstate": "..."}`, con `detalle` y `restriccion` cuando la base los informa. En `error` va el mensaje de la base tal cual, por ejemplo `Stock insuficiente del vino 242 en la sala 1: hay 24 y se piden 999 (RN-09)`. Los errores de formato que detecta FastAPI y los 404 usan el mismo formato.

## Pruebas

Son 19 pruebas con pytest que usan el cliente de prueba de FastAPI contra la base real. Corren en un servicio aparte del compose:

```
docker compose run --rm api-pruebas
```

Las pruebas usan sus propios datos: `conftest.py` crea con el rol propietario una sala, una bodega, un vino con stock, un socio y un transportista, y al terminar los borra junto con todo lo que hayan generado las pruebas (ventas, transferencias, ingresos, auditoría). Así la base queda igual que antes. Las credenciales del propietario solo las recibe el servicio `api-pruebas`, el de la API no las tiene.

Las que provocan violaciones de reglas de la base:

| Prueba | Regla | Respuesta esperada |
|---|---|---|
| `test_composicion_que_no_suma_100` | RN-05 | 409 con el mensaje del constraint trigger |
| `test_precio_negativo` | RN-01 | 422 con `chk_vino_precio` |
| `test_venta_sin_stock_no_deja_datos` | RN-09 | 409 y verifica que no quedó comprobante ni cambió el stock |
| `test_cambio_de_estado_invalido` | RN-11 | 409 al procesar una transferencia en confección o terminarla vacía |
| `test_circuito_de_transferencia` | RN-12 | 409 al agregar un renglón a una transferencia terminada |
| `test_transferencia_sin_stock_en_deposito` | RN-11 | 409 y la transferencia sigue terminada |
| `test_circuito_de_ingreso` | RN-10 | 409 al procesar un ingreso en confección |
| `test_borrar_vino_con_movimientos` | RN-14 | 409 por la FK |
| `test_clientes_de_los_tres_tipos` | RN-07 y UNIQUE | 422 con `chk_permiso_fechas` y 409 con un documento repetido |

Las demás prueban la salud con el rol de la API, la paginación, los filtros, el detalle, el alta, modificación (con la auditoría del precio) y baja de un vino, una venta con los importes calculados por la base, los reportes y los errores de formato. La salida está en `docs/resultados/api/pytest.txt`: 19 pasan.

## Inyección SQL

`api/demo_inyeccion.sh` manda textos maliciosos en los filtros del catálogo:

- `nombre=' OR '1'='1` y `nombre='; DROP TABLE vino; --` devuelven 200 con 0 vinos: el texto se buscó como parte del nombre de un vino, porque viaja como parámetro y nunca se mezcla con el SQL. Antes y después el catálogo tiene 409 vinos.
- `tipo=tinto' OR '1'='1` devuelve 400: la base intenta convertir el texto al ENUM `tipo_vino` y lo rechaza (22P02).

La salida está en `docs/resultados/api/inyeccion_sql.txt` y lo mismo se verifica en `api/tests/test_inyeccion.py`.

## CORS

Los orígenes permitidos se leen de `CORS_ORIGINS` (separados por comas). Por defecto es `http://localhost:8080`, donde va a estar el front.

## Criterios de aceptación

- [x] Un solo comando (`docker compose up`) levanta base y API. Servicios `db` y `api` del `docker-compose.yml`; la API espera a que la base esté sana.
- [x] Toda consulta está parametrizada y la API usa el rol sin privilegios de propietario. `api/app/datos.py` no arma SQL con texto (no hay f-strings ni `format` en ese archivo), las pruebas de inyección pasan y `/salud` devuelve `bodega_app`.
- [x] Un intento de vender sin stock devuelve un error claro (409) y no deja datos a medias. `test_venta_sin_stock_no_deja_datos`.
- [x] Las pruebas automáticas pasan y cubren errores de reglas de la base. 19 pruebas, 9 de ellas con reglas de la base (`docs/resultados/api/pytest.txt`).
- [x] La documentación de la API está disponible y es coherente con las rutas reales. FastAPI la genera desde las mismas rutas en `/docs`; cada ruta tiene un resumen corto y está agrupada por recurso.
