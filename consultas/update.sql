/* consultas de modificacion (update)
   cada una corre en su propia transaccion: control previo, sentencia, control posterior
   y rollback, asi se pueden correr todas sin cambiar la base.
   uso: psql -U bodega_owner -d bodegas -f consultas/update.sql
   los valores concretos salen de la carga con semilla 2026 y se cambian en los \set */

\pset pager off
\set ON_ERROR_STOP off

/* u1
   enunciado: recalcular el total de todos los comprobantes aplicando el descuento que
   corresponde al tipo de cliente.
   estrategia: el total no se escribe a mano porque lo mantienen los triggers. se actualiza
   el porcentaje de descuento de los renglones con el descuento del cliente; trg_renglon_importes
   recalcula el subtotal del renglon y trg_renglon_actualiza recalcula el comprobante.
   solo se tocan los renglones cuyo descuento quedo distinto al del cliente, los demas ya
   estan bien. para que se vea el recalculo, en la misma transaccion antes se le sube el
   descuento a un exportador, como hace u6.
   triggers: trg_renglon_importes, trg_renglon_actualiza y trg_comprobante_importes */
\set cliente_u1 50
BEGIN;
UPDATE cliente SET descuento = 35 WHERE id_cliente = :cliente_u1;
-- control previo
SELECT count(*) AS comprobantes, SUM(c.subtotal) AS subtotal, SUM(c.descuento) AS descuento, SUM(c.total) AS total
  FROM comprobante c WHERE c.id_cliente = :cliente_u1;
UPDATE renglon_comprobante r
   SET porc_descuento = fn_descuento_cliente(c.id_cliente)
  FROM comprobante c
 WHERE c.nro_comprobante = r.nro_comprobante
   AND r.porc_descuento <> fn_descuento_cliente(c.id_cliente);
-- control posterior: el total baja y sigue siendo la suma de los renglones
SELECT count(*) AS comprobantes, SUM(c.subtotal) AS subtotal, SUM(c.descuento) AS descuento, SUM(c.total) AS total,
       bool_and(c.total = fn_total_comprobante(c.nro_comprobante)) AS total_igual_a_renglones
  FROM comprobante c WHERE c.id_cliente = :cliente_u1;
ROLLBACK;

/* u2
   enunciado: aumentar un 20 % el salario de los empleados con mas de 5 anios de antiguedad.
   estrategia: update con la funcion fn_antiguedad_anios, que cuenta anios completos hasta hoy */
BEGIN;
-- control previo
SELECT count(*) AS empleados, SUM(salario) AS masa_salarial
  FROM empleado WHERE fn_antiguedad_anios(fecha_ingreso) > 5;
UPDATE empleado
   SET salario = ROUND(salario * 1.20, 2)
 WHERE fn_antiguedad_anios(fecha_ingreso) > 5;
-- control posterior
SELECT count(*) AS empleados, SUM(salario) AS masa_salarial
  FROM empleado WHERE fn_antiguedad_anios(fecha_ingreso) > 5;
ROLLBACK;

/* u3
   enunciado: incrementar un 13 % el precio de los vinos elaborados por una bodega determinada.
   estrategia: update con subconsulta que busca el cuit de la bodega por su razon social.
   triggers: trg_vino_auditoria_precio deja una fila en auditoria_precio por cada vino */
\set bodega 'Bodega Gonzalez'
BEGIN;
-- control previo
SELECT count(*) AS vinos, SUM(precio) AS suma_precios,
       (SELECT count(*) FROM auditoria_precio) AS filas_auditoria
  FROM vino WHERE cuit_bodega = (SELECT cuit FROM bodega WHERE razon_social = :'bodega');
UPDATE vino
   SET precio = ROUND(precio * 1.13, 2)
 WHERE cuit_bodega = (SELECT cuit FROM bodega WHERE razon_social = :'bodega');
-- control posterior: los precios suben y la auditoria crece en la misma cantidad de vinos
SELECT count(*) AS vinos, SUM(precio) AS suma_precios,
       (SELECT count(*) FROM auditoria_precio) AS filas_auditoria
  FROM vino WHERE cuit_bodega = (SELECT cuit FROM bodega WHERE razon_social = :'bodega');
ROLLBACK;

/* u4
   enunciado: en las salas cuyo dia de cierre es lunes cambiarlo a miercoles y viceversa,
   en una sola sentencia.
   estrategia: un solo update con case, asi cada fila se evalua con su valor original y
   no se pisan los cambios entre si */
BEGIN;
-- control previo
SELECT dia_cierre, count(*) AS salas FROM sala_venta
 WHERE dia_cierre IN ('lunes', 'miercoles') GROUP BY dia_cierre ORDER BY dia_cierre;
UPDATE sala_venta
   SET dia_cierre = CASE dia_cierre
                      WHEN 'lunes' THEN 'miercoles'::dia_semana
                      WHEN 'miercoles' THEN 'lunes'::dia_semana
                    END
 WHERE dia_cierre IN ('lunes', 'miercoles');
-- control posterior: las cantidades se intercambian
SELECT dia_cierre, count(*) AS salas FROM sala_venta
 WHERE dia_cierre IN ('lunes', 'miercoles') GROUP BY dia_cierre ORDER BY dia_cierre;
ROLLBACK;

/* u5
   enunciado: aplicar un 15 % de descuento de precio a los 10 vinos menos vendidos de toda la red.
   estrategia: cte con las botellas vendidas por vino. el left join cuenta tambien los vinos
   que nunca se vendieron, con 0. ante empates se ordena por codigo para que siempre sean
   los mismos 10.
   triggers: trg_vino_auditoria_precio audita los 10 cambios */
BEGIN;
-- control previo
WITH ventas AS (
  SELECT v.cod_vino, COALESCE(SUM(r.cantidad), 0) AS botellas
    FROM vino v
    LEFT JOIN renglon_comprobante r ON r.cod_vino = v.cod_vino
   GROUP BY v.cod_vino
   ORDER BY botellas, v.cod_vino
   LIMIT 10)
SELECT v.cod_vino, v.nombre, ventas.botellas, v.precio
  FROM ventas JOIN vino v ON v.cod_vino = ventas.cod_vino
 ORDER BY ventas.botellas, v.cod_vino;
WITH ventas AS (
  SELECT v.cod_vino, COALESCE(SUM(r.cantidad), 0) AS botellas
    FROM vino v
    LEFT JOIN renglon_comprobante r ON r.cod_vino = v.cod_vino
   GROUP BY v.cod_vino
   ORDER BY botellas, v.cod_vino
   LIMIT 10)
UPDATE vino
   SET precio = ROUND(precio * 0.85, 2)
 WHERE cod_vino IN (SELECT cod_vino FROM ventas);
-- control posterior: los mismos 10 vinos con el precio nuevo
WITH ventas AS (
  SELECT v.cod_vino, COALESCE(SUM(r.cantidad), 0) AS botellas
    FROM vino v
    LEFT JOIN renglon_comprobante r ON r.cod_vino = v.cod_vino
   GROUP BY v.cod_vino
   ORDER BY botellas, v.cod_vino
   LIMIT 10)
SELECT v.cod_vino, v.nombre, ventas.botellas, v.precio
  FROM ventas JOIN vino v ON v.cod_vino = ventas.cod_vino
 ORDER BY ventas.botellas, v.cod_vino;
ROLLBACK;

/* u6
   enunciado: a los exportadores con mas de 3 permisos de exportacion, subirles el descuento al 35 %.
   estrategia: subconsulta con group by y having sobre los permisos. el 35 % entra en el
   check chk_cliente_descuento (entre 0 y 50). las ventas ya hechas no cambian, solo las nuevas */
BEGIN;
-- control previo
SELECT descuento, count(*) AS exportadores FROM cliente WHERE tipo = 'exportador' GROUP BY descuento ORDER BY descuento;
UPDATE cliente
   SET descuento = 35
 WHERE tipo = 'exportador'
   AND id_cliente IN (SELECT id_cliente
                        FROM permiso_exportacion
                       GROUP BY id_cliente
                      HAVING count(*) > 3);
-- control posterior
SELECT descuento, count(*) AS exportadores FROM cliente WHERE tipo = 'exportador' GROUP BY descuento ORDER BY descuento;
ROLLBACK;
