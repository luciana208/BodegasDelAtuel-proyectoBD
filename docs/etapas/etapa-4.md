# Etapa 4: índices y rendimiento

## Qué hicimos

Elegimos cinco consultas de la sección 8 que trabajan sobre las tablas grandes: S1, S3, S4, S8 y S12. Primero las medimos solo con los índices de las claves primarias y de los UNIQUE, miramos los planes, y a partir de eso escribimos `db/migrations/008_indices.sql`.

Para no medir a mano hicimos `db/indices/medir.py`, que corre en el mismo contenedor que la carga:

```
docker compose run --rm indices
```

El script borra los índices de 008, hace ANALYZE, corre cada consulta cinco veces con `EXPLAIN (ANALYZE, BUFFERS)` y se queda con la mediana (con la caché ya caliente). Después crea los índices midiendo cuánto tarda cada uno, vuelve a hacer ANALYZE y repite las mediciones. También mide el costo de escritura, prueba los índices que descartamos y arma el caso en que el planificador no usa un índice. Al terminar la base queda con los índices de 008, igual que si se hubiera creado desde cero. Todo queda en `docs/resultados/indices/`:

- `comparacion.md`: las tablas de resultados.
- `planes_antes.txt` y `planes_despues.txt`: los planes completos de cada consulta (anexo).
- `planes_descartados.txt` y `planes_no_usa_indice.txt`: los planes de las pruebas extra.

## Índices creados

| Índice | Tipo | Para qué | Justificación |
|---|---|---|---|
| `idx_comprobante_sala_fecha` | B-tree compuesto `(id_sala, fecha)` | S3, S11, ventas por sala en el tablero | Antes S3 hacía Seq Scan de los 150.000 comprobantes para quedarse con 45. |
| `idx_comprobante_fecha_brin` | BRIN sobre `fecha` | S8, D1 y cualquier filtro por período | Los comprobantes se cargan en orden de fecha, así que cada bloque de páginas cubre pocos días y el BRIN descarta casi toda la tabla. Ocupa 24 kB. |
| `idx_comprobante_cliente` | B-tree sobre la FK `id_cliente` | S12, D4, D6 | PostgreSQL no indexa las FK. Sin este índice S12 recorre toda la tabla de comprobantes por cada cliente. Además lo usa el RESTRICT al borrar un cliente. |
| `idx_renglon_comprobante_vino` | B-tree sobre la FK `cod_vino` con `INCLUDE (cantidad)` | S2, U5, búsquedas por vino y el RESTRICT de RN-14 | La PK de renglón empieza por el comprobante, así que no sirve para buscar por vino. Con la cantidad incluida, sumar las botellas de un vino se resuelve leyendo solo el índice. |
| `idx_renglon_transferencia_vino` | B-tree sobre la FK `cod_vino` | S4 | Mismo problema que el anterior en los renglones de transferencia. |
| `idx_transferencia_pendientes` | B-tree parcial `(id_sala, fecha_confeccion) WHERE estado <> 'procesado'` | S5, `v_documentos_pendientes`, pantalla de transferencias | Las pendientes son 26 de 3.028. El índice guarda solo esas y ocupa 16 kB. |

### Orden de las columnas del compuesto

En `idx_comprobante_sala_fecha` va primero `id_sala` porque en las consultas se compara por igualdad (una sala), y después `fecha` porque se filtra por rango. Con ese orden todas las entradas de una sala quedan juntas y ordenadas por fecha, y el índice lee solo el tramo que corresponde. Con el orden al revés `(fecha, id_sala)` el índice tiene que recorrer las entradas de todas las salas dentro del rango de fechas y descartar las que no son de la sala. Lo probamos con las ventas de la sala 1 del último año: con `(id_sala, fecha)` tardó 0,51 ms y leyó 215 buffers, con `(fecha, id_sala)` 0,73 ms y 262 buffers. Con S3 (una semana) casi no hay diferencia porque el rango es muy chico, pero cuanto más largo es el período más pesa.

## Comparación antes y después

Mediana de cinco ejecuciones. S12 sin índices tardó más de dos minutos y se midió una sola vez.

| Consulta | Antes | Después | Mejora | Recorrido antes | Recorrido después | Filas leídas antes | Filas leídas después |
|---|---|---|---|---|---|---|---|
| S1 top 10 vinos | 70,99 ms | 82,60 ms | no mejora | Seq Scan renglon_comprobante | Seq Scan renglon_comprobante | 508.104 | 508.104 |
| S3 clientes por tipo en la sala 1, última semana | 9,39 ms | 0,12 ms | 77 veces | Seq Scan comprobante | Bitmap Index Scan idx_comprobante_sala_fecha | 150.045 | 135 |
| S4 top 5 salas que pidieron el vino 224 | 0,81 ms | 0,37 ms | 2,2 veces | Seq Scan renglon_transferencia | Bitmap Index Scan idx_renglon_transferencia_vino | 13.451 | 3.798 |
| S8 ventas por sala, último trimestre | 13,41 ms | 2,97 ms | 4,5 veces | Seq Scan comprobante | Bitmap Index Scan idx_comprobante_fecha_brin | 150.000 | 13.036 |
| S12 clientes que compraron todos los vinos de una bodega | 135.802 ms | 596 ms | 228 veces | Seq Scan comprobante en cada vuelta | Bitmap Index Scan idx_comprobante_cliente | 3.568.282.272 | 547.563 |

La tabla completa, con los buffers, está en `docs/resultados/indices/comparacion.md`.

S1 no mejora y lo dejamos en la tabla a propósito: tiene que sumar las cantidades de los 506.878 renglones, así que cualquier camino lee todo. El planificador prefiere el Seq Scan con HashAggregate antes que recorrer el índice entero; las diferencias de tiempo entre las dos mediciones son ruido. Un índice sirve cuando la consulta se queda con una parte chica de la tabla.

En S12 se ve lo más importante: es una doble negación con subconsultas correlacionadas, y la de adentro filtra comprobantes por cliente. Sin el índice sobre la FK se hacía un Seq Scan de comprobante por cada cliente y cada vino de la bodega, más de 3.500 millones de filas leídas en total.

## Índices descartados

| Índice | Por qué lo descartamos |
|---|---|
| B-tree sobre `comprobante (fecha)` | Para S8 fue un poco más rápido que el BRIN (1,98 ms contra 2,97 ms) pero ocupa 1.040 kB contra 24 kB, y como todo B-tree hay que actualizarlo en cada venta. Como la tabla está ordenada por fecha el BRIN alcanza. |
| B-tree compuesto `comprobante (fecha, id_sala)` | Es el mismo índice con las columnas al revés. Lee más páginas que `(id_sala, fecha)` cuando el período es largo (ver arriba). |
| B-tree sobre `cliente (tipo)` | El 75 % de los clientes son socios. Para traer los socios el planificador sigue usando Seq Scan aunque el índice exista, así que solo ocuparía lugar y haría más lentas las altas. |

## Costo de escritura

Medimos cuánto tarda copiar las dos tablas grandes (`INSERT ... SELECT` en una tabla nueva creada con `LIKE ... INCLUDING ALL`, que copia también los índices) sin los índices de 008 y con ellos:

| Tabla | Filas | Sin índices de 008 | Con índices de 008 | Diferencia |
|---|---|---|---|---|
| comprobante | 150.000 | 0,39 s | 0,85 s | +117 % |
| renglon_comprobante | 506.878 | 1,07 s | 1,79 s | +67 % |

comprobante tiene tres índices nuevos y por eso duplica el tiempo. Crear los seis índices sobre la base ya cargada tardó menos de medio segundo en total, así que con volúmenes más grandes convendría borrarlos antes de una carga masiva y crearlos de nuevo al final. Con nuestro volumen la diferencia es de pocos segundos y la carga de la etapa 3 se hace con los índices puestos. En el uso normal cada venta inserta pocas filas y el costo extra por fila es chico comparado con lo que se gana en las consultas.

## Caso en que el planificador no usa un índice

```sql
SELECT id_sala, count(*), SUM(total)
  FROM comprobante
 WHERE id_sala BETWEEN 2 AND 30
 GROUP BY id_sala;
```

Existe `idx_comprobante_sala_fecha`, que empieza por `id_sala`, pero la condición deja pasar el 93,5 % de los comprobantes. El planificador estima que leer casi todas las filas desde el índice sale más caro que recorrer la tabla en orden y elige Seq Scan (35,86 ms). Forzando el índice con `SET enable_seqscan = off` usa un Bitmap Heap Scan y tarda más (37,40 ms). La causa es la baja selectividad. Los dos planes están en `docs/resultados/indices/planes_no_usa_indice.txt`.

Lo mismo pasa con el índice sobre `cliente (tipo)` que descartamos.

## Criterios de aceptación

- [x] Hay al menos 5 índices, incluyendo los tipos pedidos, y todos tienen justificación. Son 6 en `db/migrations/008_indices.sql`: compuesto (`idx_comprobante_sala_fecha`), parcial (`idx_transferencia_pendientes`), sobre claves foráneas (`idx_comprobante_cliente`, `idx_renglon_comprobante_vino`, `idx_renglon_transferencia_vino`), BRIN (`idx_comprobante_fecha_brin`) y con INCLUDE (`idx_renglon_comprobante_vino`). La justificación está en la tabla de arriba y en los comentarios del archivo.
- [x] La tabla comparativa muestra una mejora medida en al menos 3 consultas. Mejoran S3, S4, S8 y S12 (`docs/resultados/indices/comparacion.md`, planes en `planes_antes.txt` y `planes_despues.txt`).
- [x] Se explica por qué algún índice se descartó y cuál es el costo de escritura de los índices creados. Secciones "Índices descartados" y "Costo de escritura".
