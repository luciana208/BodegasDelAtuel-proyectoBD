/* sesion a de la demostracion de la ultima botella. se corre al mismo tiempo que
   sesion_b.sql, en otra terminal. los pg_sleep ordenan los pasos entre las dos sesiones.
   nivel de aislamiento: read committed, el que usa postgresql por defecto */

\pset pager off
\set ON_ERROR_STOP off

SELECT s.id_sala AS sala, v.cod_vino AS vino, c.id_cliente AS cliente
  FROM sala_venta s, vino v, cliente c
 WHERE s.calle = 'Calle Concurrencia' AND v.nombre = 'Vino Concurrencia' AND c.nro_documento = '99999985' \gset

SHOW transaction_isolation;

\echo
\echo parte 1: con SELECT ... FOR UPDATE

UPDATE stock_sala SET cantidad = 1 WHERE id_sala = :sala AND cod_vino = :vino;

-- paso 1
BEGIN;
-- paso 2: bloquea la fila y lee 1
SELECT clock_timestamp()::TIME(0) AS hora, cantidad
  FROM stock_sala WHERE id_sala = :sala AND cod_vino = :vino FOR UPDATE;
SELECT pg_sleep(4);
-- paso 4: vende la botella y confirma
UPDATE stock_sala SET cantidad = cantidad - 1 WHERE id_sala = :sala AND cod_vino = :vino;
SELECT clock_timestamp()::TIME(0) AS hora_commit;
COMMIT;

\echo
\echo parte 2: sin FOR UPDATE

SELECT pg_sleep(2);
UPDATE stock_sala SET cantidad = 1 WHERE id_sala = :sala AND cod_vino = :vino;

BEGIN;
-- lee 1 sin bloquear la fila
SELECT clock_timestamp()::TIME(0) AS hora, cantidad
  FROM stock_sala WHERE id_sala = :sala AND cod_vino = :vino;
SELECT pg_sleep(3);
-- la aplicacion calcula el stock nuevo con lo que leyo: 1 - 1 = 0
UPDATE stock_sala SET cantidad = 0 WHERE id_sala = :sala AND cod_vino = :vino;
SELECT clock_timestamp()::TIME(0) AS hora_commit;
COMMIT;
\echo a vendio la botella

\echo
\echo parte 3: venta real con el trigger de la base

SELECT pg_sleep(3);
UPDATE stock_sala SET cantidad = 1 WHERE id_sala = :sala AND cod_vino = :vino;

BEGIN;
INSERT INTO comprobante (id_cliente, id_sala) VALUES (:cliente, :sala) RETURNING nro_comprobante AS comp \gset
-- el trigger trg_renglon_valida_stock bloquea la fila de stock con FOR UPDATE
INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad) VALUES (:comp, :vino, 1);
SELECT clock_timestamp()::TIME(0) AS hora, fn_stock_sala(:sala, :vino) AS stock_despues_de_vender;
SELECT pg_sleep(3);
COMMIT;
\echo a vendio la ultima botella

SELECT clock_timestamp()::TIME(0) AS hora, fn_stock_sala(:sala, :vino) AS stock_final;
