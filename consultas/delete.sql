/* consultas de borrado (delete)
   cada una corre en su propia transaccion: control previo, sentencia, control posterior
   y rollback, asi se pueden correr todas sin cambiar la base.
   uso: psql -U bodega_owner -d bodegas -f consultas/delete.sql
   los valores concretos salen de la carga con semilla 2026 y se cambian en los \set */

\pset pager off
\set ON_ERROR_STOP off

/* d1
   enunciado: borrar los comprobantes con mas de 5 anios de antiguedad asociados a clientes
   socios del club.
   estrategia: delete ... using con cliente para filtrar por tipo. los renglones se borran
   solos por el on delete cascade de renglon_comprobante.
   triggers: por cada renglon borrado se dispara trg_renglon_actualiza, que intenta recalcular
   un comprobante que ya no existe y no hace nada. el borrado no devuelve stock */
BEGIN;
-- control previo
SELECT count(*) AS comprobantes, (SELECT count(*) FROM renglon_comprobante) AS renglones_totales
  FROM comprobante c JOIN cliente cl ON cl.id_cliente = c.id_cliente
 WHERE cl.tipo = 'socio' AND c.fecha < CURRENT_DATE - INTERVAL '5 years';
DELETE FROM comprobante c
 USING cliente cl
 WHERE cl.id_cliente = c.id_cliente
   AND cl.tipo = 'socio'
   AND c.fecha < CURRENT_DATE - INTERVAL '5 years';
-- control posterior: no quedan y los renglones bajaron
SELECT count(*) AS comprobantes, (SELECT count(*) FROM renglon_comprobante) AS renglones_totales
  FROM comprobante c JOIN cliente cl ON cl.id_cliente = c.id_cliente
 WHERE cl.tipo = 'socio' AND c.fecha < CURRENT_DATE - INTERVAL '5 years';
ROLLBACK;

/* d2
   enunciado: eliminar las cepas que no componen ningun vino ni estan plantadas en ninguna parcela.
   estrategia: dos not exists, uno contra composicion y otro contra parcela. si se intentara
   borrar una cepa en uso, el on delete restrict de esas fk lo impediria */
BEGIN;
-- control previo
SELECT c.id_cepa, c.nombre FROM cepa c
 WHERE NOT EXISTS (SELECT 1 FROM composicion co WHERE co.id_cepa = c.id_cepa)
   AND NOT EXISTS (SELECT 1 FROM parcela p WHERE p.id_cepa = c.id_cepa)
 ORDER BY c.id_cepa;
DELETE FROM cepa c
 WHERE NOT EXISTS (SELECT 1 FROM composicion co WHERE co.id_cepa = c.id_cepa)
   AND NOT EXISTS (SELECT 1 FROM parcela p WHERE p.id_cepa = c.id_cepa);
-- control posterior
SELECT count(*) AS cepas FROM cepa;
ROLLBACK;

/* d3
   enunciado: la sala de una localidad determinada fue dada de baja: eliminar los empleados
   de esa sala que trabajaron menos de dos anios.
   estrategia: delete ... using con sala_venta y localidad para encontrar la sala por el nombre
   de la localidad, y fn_antiguedad_anios para la antiguedad. tupungato tiene una sola sala */
\set localidad_d3 'Tupungato'
BEGIN;
-- control previo
SELECT e.cuit, e.nombre, e.fecha_ingreso, fn_antiguedad_anios(e.fecha_ingreso) AS anios
  FROM empleado e
  JOIN sala_venta s ON s.id_sala = e.id_sala
  JOIN localidad l ON l.id_localidad = s.id_localidad
 WHERE l.nombre = :'localidad_d3'
 ORDER BY e.fecha_ingreso;
DELETE FROM empleado e
 USING sala_venta s, localidad l
 WHERE s.id_sala = e.id_sala
   AND l.id_localidad = s.id_localidad
   AND l.nombre = :'localidad_d3'
   AND fn_antiguedad_anios(e.fecha_ingreso) < 2;
-- control posterior
SELECT e.cuit, e.nombre, e.fecha_ingreso, fn_antiguedad_anios(e.fecha_ingreso) AS anios
  FROM empleado e
  JOIN sala_venta s ON s.id_sala = e.id_sala
  JOIN localidad l ON l.id_localidad = s.id_localidad
 WHERE l.nombre = :'localidad_d3'
 ORDER BY e.fecha_ingreso;
ROLLBACK;

/* d4
   enunciado: borrar los clientes socios que nunca compraron y se dieron de alta hace mas de 5 anios.
   estrategia: not exists contra comprobante (anti join). la fila de socio se borra sola por
   el on delete cascade del subtipo. si el cliente tuviera compras, el restrict de comprobante
   lo frenaria, pero el not exists ya los deja afuera */
BEGIN;
-- control previo
SELECT count(*) AS clientes, (SELECT count(*) FROM socio) AS socios_totales
  FROM cliente c
 WHERE c.tipo = 'socio'
   AND c.fecha_alta < CURRENT_DATE - INTERVAL '5 years'
   AND NOT EXISTS (SELECT 1 FROM comprobante co WHERE co.id_cliente = c.id_cliente);
DELETE FROM cliente c
 WHERE c.tipo = 'socio'
   AND c.fecha_alta < CURRENT_DATE - INTERVAL '5 years'
   AND NOT EXISTS (SELECT 1 FROM comprobante co WHERE co.id_cliente = c.id_cliente);
-- control posterior
SELECT count(*) AS clientes, (SELECT count(*) FROM socio) AS socios_totales
  FROM cliente c
 WHERE c.tipo = 'socio'
   AND c.fecha_alta < CURRENT_DATE - INTERVAL '5 years'
   AND NOT EXISTS (SELECT 1 FROM comprobante co WHERE co.id_cliente = c.id_cliente);
ROLLBACK;

/* d5
   enunciado: eliminar los ingresos en estado procesado de hace mas de 365 dias.
   estrategia: delete simple por estado y fecha. los renglones se borran por cascade.
   triggers: trg_renglon_ingreso_bloqueo no deja tocar renglones de un ingreso procesado,
   pero en el borrado en cascada la cabecera ya no existe y el trigger lo deja pasar.
   el stock del deposito no cambia: el ingreso ya se habia sumado cuando se proceso */
BEGIN;
-- control previo
SELECT count(*) AS ingresos, (SELECT count(*) FROM renglon_ingreso) AS renglones_totales,
       (SELECT SUM(cantidad) FROM stock_deposito) AS stock_deposito
  FROM ingreso WHERE estado = 'procesado' AND fecha < CURRENT_DATE - 365;
DELETE FROM ingreso
 WHERE estado = 'procesado'
   AND fecha < CURRENT_DATE - 365;
-- control posterior
SELECT count(*) AS ingresos, (SELECT count(*) FROM renglon_ingreso) AS renglones_totales,
       (SELECT SUM(cantidad) FROM stock_deposito) AS stock_deposito
  FROM ingreso WHERE estado = 'procesado' AND fecha < CURRENT_DATE - 365;
ROLLBACK;

/* d6
   enunciado: borrar los clientes socios sin compras que viven en una localidad especifica.
   estrategia: igual que d4 pero filtrando por la localidad, que se busca por nombre */
\set localidad_d6 'San Rafael'
BEGIN;
-- control previo
SELECT count(*) AS clientes
  FROM cliente c
 WHERE c.tipo = 'socio'
   AND c.id_localidad = (SELECT id_localidad FROM localidad WHERE nombre = :'localidad_d6')
   AND NOT EXISTS (SELECT 1 FROM comprobante co WHERE co.id_cliente = c.id_cliente);
DELETE FROM cliente c
 WHERE c.tipo = 'socio'
   AND c.id_localidad = (SELECT id_localidad FROM localidad WHERE nombre = :'localidad_d6')
   AND NOT EXISTS (SELECT 1 FROM comprobante co WHERE co.id_cliente = c.id_cliente);
-- control posterior
SELECT count(*) AS clientes
  FROM cliente c
 WHERE c.tipo = 'socio'
   AND c.id_localidad = (SELECT id_localidad FROM localidad WHERE nombre = :'localidad_d6')
   AND NOT EXISTS (SELECT 1 FROM comprobante co WHERE co.id_cliente = c.id_cliente);
ROLLBACK;
