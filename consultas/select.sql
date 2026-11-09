/* consultas (select)
   uso: psql -U bodega_owner -d bodegas -f consultas/select.sql
   los periodos se calculan desde CURRENT_DATE. los valores concretos salen de la carga
   con semilla 2026 y se cambian en los \set */

\pset pager off

\set sala 1
\set vino 224
\set bodega 'Bodega Boutique Cordoba'

/* s1
   enunciado: ranking de los 10 vinos con mayor cantidad de botellas vendidas en toda la red de salas.
   estrategia: join de renglones con vino, suma de cantidades por vino, orden descendente y limit */
SELECT v.cod_vino, v.nombre, v.anada, v.volumen_ml, SUM(r.cantidad) AS botellas
  FROM renglon_comprobante r
  JOIN vino v ON v.cod_vino = r.cod_vino
 GROUP BY v.cod_vino, v.nombre, v.anada, v.volumen_ml
 ORDER BY botellas DESC
 LIMIT 10;

/* s2
   enunciado: listar codigos y nombres de los vinos que se vendieron en todas las salas
   (division relacional).
   estrategia: doble not exists: un vino entra si no existe ninguna sala en la que no se haya
   vendido. los pares sala-vino vendidos se calculan una sola vez en una cte, si no la
   subconsulta de adentro recorre los renglones por cada vino y cada sala */
WITH vendidos AS (
  SELECT DISTINCT c.id_sala, r.cod_vino
    FROM comprobante c
    JOIN renglon_comprobante r ON r.nro_comprobante = c.nro_comprobante)
SELECT v.cod_vino, v.nombre
  FROM vino v
 WHERE NOT EXISTS (
       SELECT 1 FROM sala_venta s
        WHERE NOT EXISTS (
              SELECT 1 FROM vendidos x
               WHERE x.id_sala = s.id_sala AND x.cod_vino = v.cod_vino))
 ORDER BY v.cod_vino;

/* s3
   enunciado: cantidad de clientes de cada tipo que compraron en una sala determinada en la
   ultima semana.
   estrategia: join comprobante con cliente, filtro por sala y fecha, y count distinct para
   no contar dos veces a un cliente que compro mas de una vez. usa idx_comprobante_sala_fecha */
SELECT cl.tipo, count(DISTINCT cl.id_cliente) AS clientes
  FROM comprobante c
  JOIN cliente cl ON cl.id_cliente = c.id_cliente
 WHERE c.id_sala = :sala
   AND c.fecha > CURRENT_DATE - 7
 GROUP BY cl.tipo
 ORDER BY cl.tipo;

/* s4
   enunciado: top 5 de las salas que solicitaron mayor cantidad de un vino determinado
   mediante transferencias en los ultimos 15 dias.
   estrategia: join transferencia con sus renglones, filtro por vino y fecha, suma por sala.
   cuenta las transferencias en cualquier estado porque son solicitudes. usa
   idx_renglon_transferencia_vino */
SELECT t.id_sala, l.nombre AS localidad, SUM(r.cantidad) AS botellas_pedidas
  FROM transferencia t
  JOIN renglon_transferencia r ON r.nro_transferencia = t.nro_transferencia
  JOIN sala_venta s ON s.id_sala = t.id_sala
  JOIN localidad l ON l.id_localidad = s.id_localidad
 WHERE r.cod_vino = :vino
   AND t.fecha_confeccion >= CURRENT_DATE - 15
 GROUP BY t.id_sala, l.nombre
 ORDER BY botellas_pedidas DESC, t.id_sala
 LIMIT 5;

/* s5
   enunciado: listado de las salas con menor cantidad de transferencias pendientes (no procesadas).
   estrategia: cte con todas las salas y la cantidad de pendientes (el left join cuenta 0
   cuando no tiene). despues se muestran las salas cuyo conteo es igual al minimo, que puede
   ser mas de una */
WITH pendientes AS (
  SELECT s.id_sala, l.nombre AS localidad, count(t.nro_transferencia) AS pendientes
    FROM sala_venta s
    JOIN localidad l ON l.id_localidad = s.id_localidad
    LEFT JOIN transferencia t ON t.id_sala = s.id_sala AND t.estado <> 'procesado'
   GROUP BY s.id_sala, l.nombre)
SELECT id_sala, localidad, pendientes
  FROM pendientes
 WHERE pendientes = (SELECT min(pendientes) FROM pendientes)
 ORDER BY id_sala;

/* s6
   enunciado: para una sala determinada, los vinos sin stock en la sala pero con stock en el
   deposito central.
   estrategia: vinos con stock positivo en el deposito y not exists de una fila con stock
   positivo en la sala. asi entran los que tienen fila en 0 y los que no tienen fila */
SELECT v.cod_vino, v.nombre, v.anada, v.volumen_ml, d.cantidad AS stock_deposito
  FROM vino v
  JOIN stock_deposito d ON d.cod_vino = v.cod_vino
 WHERE d.cantidad > 0
   AND NOT EXISTS (SELECT 1 FROM stock_sala s
                    WHERE s.id_sala = :sala AND s.cod_vino = v.cod_vino AND s.cantidad > 0)
 ORDER BY v.cod_vino;

/* s7
   enunciado: cual es la empresa de transporte con mayor actividad en el ultimo mes.
   estrategia: la actividad se mide en ingresos trasladados en el ultimo mes (tambien se muestran
   las botellas). cte con el conteo por transportista y se devuelven los que tienen el maximo,
   asi un empate no deja a nadie afuera */
WITH actividad AS (
  SELECT t.cod_transporte, t.razon_social, count(DISTINCT i.cod_ingreso) AS ingresos,
         COALESCE(SUM(r.cantidad), 0) AS botellas
    FROM transportista t
    JOIN ingreso i ON i.cod_transporte = t.cod_transporte
    LEFT JOIN renglon_ingreso r ON r.cod_ingreso = i.cod_ingreso
   WHERE i.fecha >= CURRENT_DATE - INTERVAL '1 month'
   GROUP BY t.cod_transporte, t.razon_social)
SELECT *
  FROM actividad
 WHERE ingresos = (SELECT max(ingresos) FROM actividad)
 ORDER BY botellas DESC;

/* s8
   enunciado: monto total de ventas por sala en el ultimo trimestre, en orden descendente.
   estrategia: suma de totales por sala filtrando por fecha. usa idx_comprobante_fecha_brin */
SELECT c.id_sala, l.nombre AS localidad, count(*) AS comprobantes, SUM(c.total) AS monto
  FROM comprobante c
  JOIN sala_venta s ON s.id_sala = c.id_sala
  JOIN localidad l ON l.id_localidad = s.id_localidad
 WHERE c.fecha >= CURRENT_DATE - INTERVAL '3 months'
 GROUP BY c.id_sala, l.nombre
 ORDER BY monto DESC;

/* s9
   enunciado: ficha de un vino: cepas con sus porcentajes, bodega elaboradora, maridajes y stock
   total (deposito mas salas).
   estrategia: la vista v_ficha_vino junta todo en una fila con string_agg en subconsultas,
   para que el join con cepas y maridajes no multiplique filas. el detalle del stock sale de
   la vista v_stock_total_vino y las cepas una por fila de un join con composicion */
SELECT * FROM v_ficha_vino WHERE cod_vino = :vino;

SELECT stock_deposito, stock_salas, stock_total FROM v_stock_total_vino WHERE cod_vino = :vino;

SELECT ce.nombre AS cepa, ce.tipo, co.porcentaje
  FROM composicion co
  JOIN cepa ce ON ce.id_cepa = co.id_cepa
 WHERE co.cod_vino = :vino
 ORDER BY co.porcentaje DESC;

/* s10
   enunciado: rendimiento en kg por hectarea de cada parcela y campania, e identificar las
   parcelas que rinden menos que el promedio de su finca.
   estrategia: una cte calcula el rendimiento de cada lote (kilos sobre superficie de la parcela).
   la primera consulta lo lista. la segunda compara cada parcela con una subconsulta correlacionada
   que calcula el promedio de su finca en la misma campania */
WITH rendimiento AS (
  SELECT l.id_finca, l.nro_parcela, l.campania, l.kilos, p.superficie_ha,
         ROUND(l.kilos / p.superficie_ha, 2) AS kg_por_ha
    FROM lote_uva l
    JOIN parcela p ON p.id_finca = l.id_finca AND p.nro_parcela = l.nro_parcela)
SELECT r.id_finca, f.nombre AS finca, r.nro_parcela, r.campania, r.kilos, r.superficie_ha, r.kg_por_ha
  FROM rendimiento r
  JOIN finca f ON f.id_finca = r.id_finca
 ORDER BY r.id_finca, r.nro_parcela, r.campania;

WITH rendimiento AS (
  SELECT l.id_finca, l.nro_parcela, l.campania,
         ROUND(l.kilos / p.superficie_ha, 2) AS kg_por_ha
    FROM lote_uva l
    JOIN parcela p ON p.id_finca = l.id_finca AND p.nro_parcela = l.nro_parcela)
SELECT r.id_finca, f.nombre AS finca, r.nro_parcela, r.campania, r.kg_por_ha,
       (SELECT ROUND(AVG(r2.kg_por_ha), 2)
          FROM rendimiento r2
         WHERE r2.id_finca = r.id_finca AND r2.campania = r.campania) AS promedio_finca
  FROM rendimiento r
  JOIN finca f ON f.id_finca = r.id_finca
 WHERE r.kg_por_ha < (SELECT AVG(r2.kg_por_ha)
                        FROM rendimiento r2
                       WHERE r2.id_finca = r.id_finca AND r2.campania = r.campania)
 ORDER BY r.id_finca, r.campania, r.nro_parcela;

/* s11
   enunciado: ranking de vinos dentro de cada sala por botellas vendidas y ventas acumuladas
   mensuales por sala.
   estrategia: para el ranking, rank() over (partition by sala order by botellas desc) sobre
   las ventas agrupadas por sala y vino; se muestran los 5 primeros de cada sala. para el
   acumulado, sum() over (partition by sala y anio order by mes) sobre la vista de ventas
   mensuales, que va sumando mes a mes y vuelve a empezar cada anio; se muestra el anio actual */
WITH ventas AS (
  SELECT c.id_sala, r.cod_vino, SUM(r.cantidad) AS botellas
    FROM comprobante c
    JOIN renglon_comprobante r ON r.nro_comprobante = c.nro_comprobante
   GROUP BY c.id_sala, r.cod_vino),
ranking AS (
  SELECT id_sala, cod_vino, botellas,
         RANK() OVER (PARTITION BY id_sala ORDER BY botellas DESC) AS puesto
    FROM ventas)
SELECT k.id_sala, k.puesto, k.cod_vino, v.nombre, k.botellas
  FROM ranking k
  JOIN vino v ON v.cod_vino = k.cod_vino
 WHERE k.puesto <= 5
 ORDER BY k.id_sala, k.puesto, k.cod_vino;

SELECT *
  FROM (SELECT id_sala, mes, total_vendido,
               SUM(total_vendido) OVER (PARTITION BY id_sala, EXTRACT(YEAR FROM mes) ORDER BY mes) AS acumulado_anio
          FROM v_ventas_mensuales_sala) m
 WHERE EXTRACT(YEAR FROM mes) = EXTRACT(YEAR FROM CURRENT_DATE)
 ORDER BY id_sala, mes;

/* s12
   enunciado: clientes que compraron todos los vinos de una bodega determinada, y clientes que
   nunca compraron ningun vino tinto.
   estrategia: la primera es una division con doble not exists: un cliente entra si no hay
   ningun vino de la bodega que no haya comprado. usa idx_comprobante_cliente. la segunda es
   un anti join con not exists: clientes para los que no existe ningun renglon de un vino tinto.
   tambien entran los clientes que nunca compraron nada */
SELECT cl.id_cliente, cl.nombre, cl.tipo
  FROM cliente cl
 WHERE NOT EXISTS (
       SELECT 1
         FROM vino v
         JOIN bodega b ON b.cuit = v.cuit_bodega
        WHERE b.razon_social = :'bodega'
          AND NOT EXISTS (
              SELECT 1
                FROM comprobante c
                JOIN renglon_comprobante r ON r.nro_comprobante = c.nro_comprobante
               WHERE c.id_cliente = cl.id_cliente
                 AND r.cod_vino = v.cod_vino))
 ORDER BY cl.id_cliente;

SELECT cl.id_cliente, cl.nombre, cl.tipo
  FROM cliente cl
 WHERE NOT EXISTS (
       SELECT 1
         FROM comprobante c
         JOIN renglon_comprobante r ON r.nro_comprobante = c.nro_comprobante
         JOIN vino v ON v.cod_vino = r.cod_vino
        WHERE c.id_cliente = cl.id_cliente
          AND v.tipo = 'tinto')
 ORDER BY cl.id_cliente;

/* planes de ejecucion de las consultas usadas en la etapa 4 (s1, s3, s4 y s8) y de las
   avanzadas (s9 a s12) */
EXPLAIN (ANALYZE)
SELECT v.cod_vino, v.nombre, v.anada, v.volumen_ml, SUM(r.cantidad) AS botellas
  FROM renglon_comprobante r
  JOIN vino v ON v.cod_vino = r.cod_vino
 GROUP BY v.cod_vino, v.nombre, v.anada, v.volumen_ml
 ORDER BY botellas DESC
 LIMIT 10;

EXPLAIN (ANALYZE)
SELECT cl.tipo, count(DISTINCT cl.id_cliente) AS clientes
  FROM comprobante c
  JOIN cliente cl ON cl.id_cliente = c.id_cliente
 WHERE c.id_sala = :sala
   AND c.fecha > CURRENT_DATE - 7
 GROUP BY cl.tipo;

EXPLAIN (ANALYZE)
SELECT t.id_sala, SUM(r.cantidad) AS botellas_pedidas
  FROM transferencia t
  JOIN renglon_transferencia r ON r.nro_transferencia = t.nro_transferencia
 WHERE r.cod_vino = :vino
   AND t.fecha_confeccion >= CURRENT_DATE - 15
 GROUP BY t.id_sala
 ORDER BY botellas_pedidas DESC
 LIMIT 5;

EXPLAIN (ANALYZE)
SELECT c.id_sala, SUM(c.total) AS monto
  FROM comprobante c
 WHERE c.fecha >= CURRENT_DATE - INTERVAL '3 months'
 GROUP BY c.id_sala
 ORDER BY monto DESC;

EXPLAIN (ANALYZE)
SELECT * FROM v_ficha_vino WHERE cod_vino = :vino;

EXPLAIN (ANALYZE)
WITH rendimiento AS (
  SELECT l.id_finca, l.nro_parcela, l.campania,
         ROUND(l.kilos / p.superficie_ha, 2) AS kg_por_ha
    FROM lote_uva l
    JOIN parcela p ON p.id_finca = l.id_finca AND p.nro_parcela = l.nro_parcela)
SELECT r.id_finca, r.nro_parcela, r.campania, r.kg_por_ha
  FROM rendimiento r
 WHERE r.kg_por_ha < (SELECT AVG(r2.kg_por_ha)
                        FROM rendimiento r2
                       WHERE r2.id_finca = r.id_finca AND r2.campania = r.campania);

EXPLAIN (ANALYZE)
WITH ventas AS (
  SELECT c.id_sala, r.cod_vino, SUM(r.cantidad) AS botellas
    FROM comprobante c
    JOIN renglon_comprobante r ON r.nro_comprobante = c.nro_comprobante
   GROUP BY c.id_sala, r.cod_vino)
SELECT id_sala, cod_vino, botellas,
       RANK() OVER (PARTITION BY id_sala ORDER BY botellas DESC) AS puesto
  FROM ventas;

EXPLAIN (ANALYZE)
SELECT id_sala, mes, total_vendido,
       SUM(total_vendido) OVER (PARTITION BY id_sala, EXTRACT(YEAR FROM mes) ORDER BY mes) AS acumulado_anio
  FROM v_ventas_mensuales_sala;

EXPLAIN (ANALYZE)
SELECT cl.id_cliente
  FROM cliente cl
 WHERE NOT EXISTS (
       SELECT 1
         FROM vino v
         JOIN bodega b ON b.cuit = v.cuit_bodega
        WHERE b.razon_social = :'bodega'
          AND NOT EXISTS (
              SELECT 1
                FROM comprobante c
                JOIN renglon_comprobante r ON r.nro_comprobante = c.nro_comprobante
               WHERE c.id_cliente = cl.id_cliente
                 AND r.cod_vino = v.cod_vino));

EXPLAIN (ANALYZE)
SELECT cl.id_cliente
  FROM cliente cl
 WHERE NOT EXISTS (
       SELECT 1
         FROM comprobante c
         JOIN renglon_comprobante r ON r.nro_comprobante = c.nro_comprobante
         JOIN vino v ON v.cod_vino = r.cod_vino
        WHERE c.id_cliente = cl.id_cliente
          AND v.tipo = 'tinto');
