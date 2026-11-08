/* sesion b de la demostracion de la ultima botella. se corre al mismo tiempo que
   sesion_a.sql, en otra terminal */

\pset pager off
\set ON_ERROR_STOP off

SELECT s.id_sala AS sala, v.cod_vino AS vino, c.id_cliente AS cliente
  FROM sala_venta s, vino v, cliente c
 WHERE s.calle = 'Calle Concurrencia' AND v.nombre = 'Vino Concurrencia' AND c.nro_documento = '99999985' \gset

SHOW transaction_isolation;

\echo
\echo parte 1: con SELECT ... FOR UPDATE

SELECT pg_sleep(1);
-- paso 1
BEGIN;
-- paso 3: la misma consulta queda esperando a que a termine
SELECT clock_timestamp()::TIME(0) AS hora_pedido;
SELECT clock_timestamp()::TIME(0) AS hora_respuesta, cantidad
  FROM stock_sala WHERE id_sala = :sala AND cod_vino = :vino FOR UPDATE;
-- paso 5: recien ahora obtiene el resultado, que ya es 0, y la venta se rechaza
ROLLBACK;
\echo b no vende porque el stock es 0

\echo
\echo parte 2: sin FOR UPDATE

SELECT pg_sleep(3);
BEGIN;
-- lee 1 porque a todavia no confirmo nada
SELECT clock_timestamp()::TIME(0) AS hora, cantidad
  FROM stock_sala WHERE id_sala = :sala AND cod_vino = :vino;
SELECT pg_sleep(3);
-- a ya confirmo su venta, pero b sigue con el 1 que leyo y tambien calcula 1 - 1 = 0
UPDATE stock_sala SET cantidad = 0 WHERE id_sala = :sala AND cod_vino = :vino;
SELECT clock_timestamp()::TIME(0) AS hora_commit;
COMMIT;
\echo b tambien vendio la botella: se vendio dos veces la misma

\echo
\echo parte 3: venta real con el trigger de la base

SELECT pg_sleep(4);
BEGIN;
INSERT INTO comprobante (id_cliente, id_sala) VALUES (:cliente, :sala) RETURNING nro_comprobante AS comp \gset
SELECT clock_timestamp()::TIME(0) AS hora_pedido;
-- espera a que a confirme y despues el trigger ve stock 0 y rechaza la venta
INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad) VALUES (:comp, :vino, 1);
SELECT clock_timestamp()::TIME(0) AS hora_respuesta;
ROLLBACK;
\echo b no pudo vender
