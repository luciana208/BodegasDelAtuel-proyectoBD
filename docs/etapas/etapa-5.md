# Etapa 5: consultas SQL

## Qué hicimos

Resolvimos las 24 consignas de la sección 8 en los cuatro archivos de `consultas/`. Cada una tiene un comentario con el código, el enunciado y la estrategia. Los valores concretos están en variables de psql (`\set`) y los elegimos entre datos de la carga que no cambian si se vuelve a cargar otro día; la lista está en `consultas/README.md`. Los períodos ("última semana", "último trimestre", "más de 5 años") se calculan siempre desde `CURRENT_DATE`.

Las sentencias que modifican datos corren cada una en su transacción: `BEGIN`, una consulta de control, la sentencia, la misma consulta de control y `ROLLBACK`. Así se ve el antes y el después y la base no cambia; después de correr los cuatro archivos la base sigue con los mismos 506.878 renglones de comprobante. Las salidas de la última corrida están en `docs/resultados/consultas/`.

## Filas afectadas y lo que observamos

| Código | Filas | Qué pasó |
|---|---|---|
| U1 | 90 renglones (más 1 cliente) | Para que el recálculo se note, en la misma transacción primero le subimos el descuento al exportador 50. El UPDATE sobre los renglones dispara `trg_renglon_importes`, que recalcula el subtotal, y `trg_renglon_actualiza`, que recalcula el comprobante. El total de ese cliente pasó de 52.824.800 a 49.051.600 y sigue siendo igual a `fn_total_comprobante`. |
| U2 | 110 | La masa salarial de esos empleados pasó de 139.988.500 a 167.986.200. |
| U3 | 35 | `trg_vino_auditoria_precio` agregó 35 filas a `auditoria_precio` (de 80 a 115). |
| U4 | 19 | 9 salas con cierre lunes y 10 con miércoles quedaron al revés en un solo UPDATE con CASE. |
| U5 | 10 | Los 10 menos vendidos tienen 0 botellas vendidas; ante el empate se ordena por código para que siempre sean los mismos. También audita los 10 cambios. |
| U6 | 398 | El 35 % entra en el CHECK `chk_cliente_descuento`. Las ventas ya hechas mantienen el descuento con el que se hicieron. |
| I1 | 1 | El transportista con menos ingresos en el trimestre fue Transportes Garcia (1 ingreso). El LEFT JOIN con la fecha en el ON hace que uno sin envíos cuente 0. |
| I2 | 1 maridaje y 161 asociaciones | Hay 161 tintos de 14° o más. |
| I3 | 1 comprobante y 3 renglones | Solo se cargan vino y cantidad. Los triggers completaron precio, descuento del distribuidor (20 %) y subtotales, descontaron el stock de la sala 1 y dejaron el comprobante con subtotal 126.700, descuento 25.340 y total 101.360, igual a lo que devuelven `fn_subtotal_comprobante` y `fn_total_comprobante`. |
| I4 | 1 | |
| I5 | 1 | El id lo genera la identity. |
| I6 | 1 ingreso y 1 renglón | El estado y la fecha salen de los DEFAULT. `trg_ingreso_estado` controla que nazca en confección y por eso `trg_renglon_ingreso_bloqueo` deja cargar el renglón. |
| D1 | 18.855 comprobantes | Los renglones se borraron por ON DELETE CASCADE (de 506.878 a 443.463). Por cada renglón se dispara `trg_renglon_actualiza`, que no hace nada porque el comprobante ya no existe. El borrado no devuelve stock. |
| D2 | 4 | Tannat, Ancellotta, Pedro Giménez y Moscatel de Alejandría. Una cepa en uso no se podría borrar por el RESTRICT. |
| D3 | 2 | En la sala de Tupungato había 6 empleados y se borraron los 2 con menos de dos años. |
| D4 | 151 | La fila de `socio` se borra por cascade. |
| D5 | 1.352 ingresos | Sus renglones se borran por cascade. Acá chocamos con `trg_renglon_ingreso_bloqueo` (RN-12), que no deja tocar renglones de un ingreso procesado: lo resolvimos en la etapa 2 haciendo que deje pasar el borrado cuando la cabecera ya no existe. El stock del depósito no cambia. |
| D6 | 115 | Socios sin compras de San Rafael. |

## Herramientas que usan las consultas avanzadas

| Código | Herramienta |
|---|---|
| S2 | División relacional con doble NOT EXISTS sobre una CTE con los pares sala-vino vendidos |
| S5, S7 | CTE y comparación con el mínimo o el máximo, para no perder empates |
| S9 | Vistas `v_ficha_vino` y `v_stock_total_vino`, joins y `string_agg` |
| S10 | CTE con el rendimiento y subconsulta correlacionada con el promedio de la finca en la campaña |
| S11 | `RANK() OVER (PARTITION BY id_sala ORDER BY botellas DESC)` y `SUM() OVER (PARTITION BY id_sala, año ORDER BY mes)` |
| S12 | Doble NOT EXISTS (división) y anti join con NOT EXISTS |

## Planes de ejecución

Al final de `consultas/select.sql` están los `EXPLAIN (ANALYZE)` de S1, S3, S4 y S8 (las de la etapa 4) y de S9 a S12. En la corrida guardada en `docs/resultados/consultas/select.txt` dieron:

| Consulta | Tiempo |
|---|---|
| S1 | 79 ms |
| S3 | 0,2 ms |
| S4 | 0,4 ms |
| S8 | 2,9 ms |
| S9 (ficha) | 0,4 ms |
| S10 | 475 ms |
| S11 ranking | 109 ms |
| S11 acumulado | 150 ms |
| S12 todos los vinos de una bodega | 554 ms |
| S12 nunca compraron tintos | 245 ms |

S2 la escribimos primero con el doble NOT EXISTS directo sobre los renglones y tardaba unos 8 segundos, porque la subconsulta de adentro se resolvía de nuevo para cada vino y cada sala. Calculando antes los pares sala-vino en una CTE baja a unos 0,4 segundos y sigue siendo una división con NOT EXISTS.

## Criterios de aceptación

- [x] Están resueltas todas las consignas de la sección 8, cada una con su explicación. U1 a U6, I1 a I6, D1 a D6 y S1 a S12 en `consultas/`, cada una con su comentario de estrategia.
- [x] Las sentencias de modificación muestran estado antes y después y se probaron en transacción. Cada una tiene su control previo y posterior entre `BEGIN` y `ROLLBACK`; la salida está en `docs/resultados/consultas/update.txt`, `insert.txt` y `delete.txt`.
- [x] Las consultas avanzadas usan efectivamente CTE, funciones de ventana, subconsultas correlacionadas o NOT EXISTS según corresponda. Tabla de herramientas de arriba y `consultas/select.sql`.
