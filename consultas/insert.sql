/* consultas de insercion (insert)
   cada una corre en su propia transaccion: control previo, sentencia, control posterior
   y rollback, asi se pueden correr todas sin cambiar la base.
   uso: psql -U bodega_owner -d bodegas -f consultas/insert.sql
   los valores concretos salen de la carga con semilla 2026 y se cambian en los \set */

\pset pager off
\set ON_ERROR_STOP off

/* i1
   enunciado: insertar en la relacion transportista-localidad una nueva cobertura que vincule
   la localidad de general alvear con el transportista que menos envios (ingresos trasladados)
   haya realizado en el ultimo trimestre.
   estrategia: cte que cuenta los ingresos del ultimo trimestre por transportista. el left join
   con la condicion de fecha en el on hace que un transportista sin envios cuente 0. ante empate
   se toma el de menor codigo. el not exists evita repetir una cobertura que ya existe */
\set localidad_i1 'General Alvear'
BEGIN;
-- control previo
WITH envios AS (
  SELECT t.cod_transporte, t.razon_social, count(i.cod_ingreso) AS envios
    FROM transportista t
    LEFT JOIN ingreso i ON i.cod_transporte = t.cod_transporte
                       AND i.fecha >= CURRENT_DATE - INTERVAL '3 months'
   GROUP BY t.cod_transporte, t.razon_social)
SELECT * FROM envios ORDER BY envios, cod_transporte LIMIT 3;
SELECT tl.cod_transporte FROM transportista_localidad tl
  JOIN localidad l ON l.id_localidad = tl.id_localidad
 WHERE l.nombre = :'localidad_i1' ORDER BY 1;
INSERT INTO transportista_localidad (cod_transporte, id_localidad)
WITH envios AS (
  SELECT t.cod_transporte, count(i.cod_ingreso) AS envios
    FROM transportista t
    LEFT JOIN ingreso i ON i.cod_transporte = t.cod_transporte
                       AND i.fecha >= CURRENT_DATE - INTERVAL '3 months'
   GROUP BY t.cod_transporte
   ORDER BY envios, t.cod_transporte
   LIMIT 1)
SELECT e.cod_transporte, l.id_localidad
  FROM envios e
 CROSS JOIN localidad l
 WHERE l.nombre = :'localidad_i1'
   AND NOT EXISTS (SELECT 1 FROM transportista_localidad x
                    WHERE x.cod_transporte = e.cod_transporte AND x.id_localidad = l.id_localidad);
-- control posterior
SELECT tl.cod_transporte FROM transportista_localidad tl
  JOIN localidad l ON l.id_localidad = tl.id_localidad
 WHERE l.nombre = :'localidad_i1' ORDER BY 1;
ROLLBACK;

/* i2
   enunciado: si existe algun vino tinto con graduacion de 14 o mas, crear el maridaje
   cordero al disco y asociarlo a todos los vinos que cumplan esa condicion.
   estrategia: insert ... select con where exists, asi el maridaje se crea solo si hay vinos.
   despues un insert ... select con todos los tintos de 14 o mas */
BEGIN;
-- control previo
SELECT count(*) AS tintos_14_o_mas FROM vino WHERE tipo = 'tinto' AND graduacion >= 14;
SELECT count(*) AS maridajes FROM maridaje;
INSERT INTO maridaje (nombre, temperatura_servicio)
SELECT 'Cordero al disco', 17
 WHERE EXISTS (SELECT 1 FROM vino WHERE tipo = 'tinto' AND graduacion >= 14);
INSERT INTO vino_maridaje (cod_vino, id_maridaje)
SELECT v.cod_vino, m.id_maridaje
  FROM vino v
 CROSS JOIN maridaje m
 WHERE v.tipo = 'tinto'
   AND v.graduacion >= 14
   AND m.nombre = 'Cordero al disco';
-- control posterior
SELECT m.id_maridaje, m.nombre, m.temperatura_servicio, count(vm.cod_vino) AS vinos
  FROM maridaje m
  LEFT JOIN vino_maridaje vm ON vm.id_maridaje = m.id_maridaje
 WHERE m.nombre = 'Cordero al disco'
 GROUP BY m.id_maridaje, m.nombre, m.temperatura_servicio;
ROLLBACK;

/* i3
   enunciado: crear un nuevo comprobante con tres renglones para un cliente dado, en la sala
   con id 1, dentro de una transaccion y usando las funciones de calculo.
   estrategia: se inserta la cabecera sin importes y despues los tres renglones solo con vino
   y cantidad. los triggers completan precio, descuento (fn_descuento_cliente) y subtotal
   (fn_subtotal_renglon), descuentan el stock y recalculan el comprobante. al final se
   comparan los importes guardados con fn_subtotal_comprobante y fn_total_comprobante.
   los tres vinos son los de mas stock en la sala 1, para que la venta no falle por stock.
   triggers: trg_comprobante_importes, trg_renglon_importes, trg_renglon_valida_stock y
   trg_renglon_actualiza */
\set cliente_i3 1
\set sala_i3 1
SELECT cod_vino AS vino_1 FROM stock_sala WHERE id_sala = :sala_i3 ORDER BY cantidad DESC, cod_vino LIMIT 1 OFFSET 0 \gset
SELECT cod_vino AS vino_2 FROM stock_sala WHERE id_sala = :sala_i3 ORDER BY cantidad DESC, cod_vino LIMIT 1 OFFSET 1 \gset
SELECT cod_vino AS vino_3 FROM stock_sala WHERE id_sala = :sala_i3 ORDER BY cantidad DESC, cod_vino LIMIT 1 OFFSET 2 \gset
BEGIN;
-- control previo
SELECT cod_vino, cantidad AS stock FROM stock_sala
 WHERE id_sala = :sala_i3 AND cod_vino IN (:vino_1, :vino_2, :vino_3) ORDER BY cod_vino;
INSERT INTO comprobante (id_cliente, id_sala) VALUES (:cliente_i3, :sala_i3)
RETURNING nro_comprobante \gset
INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad) VALUES (:nro_comprobante, :vino_1, 2);
INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad) VALUES (:nro_comprobante, :vino_2, 1);
INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad) VALUES (:nro_comprobante, :vino_3, 3);
-- control posterior
SELECT * FROM renglon_comprobante WHERE nro_comprobante = :nro_comprobante ORDER BY cod_vino;
SELECT c.*, fn_subtotal_comprobante(c.nro_comprobante) AS fn_subtotal,
       fn_total_comprobante(c.nro_comprobante) AS fn_total
  FROM comprobante c WHERE c.nro_comprobante = :nro_comprobante;
SELECT cod_vino, cantidad AS stock FROM stock_sala
 WHERE id_sala = :sala_i3 AND cod_vino IN (:vino_1, :vino_2, :vino_3) ORDER BY cod_vino;
ROLLBACK;

/* i4
   enunciado: insertar una nueva bodega.
   estrategia: insert simple. el cuit tiene 11 digitos como pide el dominio cuit_dom */
BEGIN;
-- control previo
SELECT count(*) AS bodegas FROM bodega;
INSERT INTO bodega (cuit, razon_social, domicilio)
VALUES ('30712345671', 'Bodega Valle del Atuel', 'Ruta Nacional 143 km 785, San Rafael');
-- control posterior
SELECT count(*) AS bodegas FROM bodega;
SELECT * FROM bodega WHERE cuit = '30712345671';
ROLLBACK;

/* i5
   enunciado: insertar una nueva sala de venta.
   estrategia: insert ... select para buscar el id de la localidad por su nombre. el id de la
   sala lo genera la columna identity y se devuelve con returning */
\set localidad_i5 'Malargüe'
BEGIN;
-- control previo
SELECT count(*) AS salas FROM sala_venta;
INSERT INTO sala_venta (calle, numero, dia_cierre, id_localidad)
SELECT 'Avenida San Martín', 1450, 'lunes', id_localidad
  FROM localidad
 WHERE nombre = :'localidad_i5'
RETURNING *;
-- control posterior
SELECT count(*) AS salas FROM sala_venta;
ROLLBACK;

/* i6
   enunciado: crear un ingreso en confeccion de 120 botellas de un vino determinado (por
   ejemplo malbec reserva de 750 ml), elaborado por una bodega dada y trasladado por un
   transportista dado.
   estrategia: la cabecera se inserta sin estado ni fecha, que toman sus valores por defecto
   (en_confeccion y la fecha de hoy). el renglon se inserta con un select que busca el vino
   por nombre, volumen y bodega. el vino 1 es el malbec reserva de 750 ml de la bodega gonzalez.
   triggers: trg_ingreso_estado controla que nazca en confeccion y trg_renglon_ingreso_bloqueo
   deja cargar el renglon porque esta en confeccion */
\set vino_i6 'Malbec Reserva'
\set volumen_i6 750
\set bodega_i6 'Bodega Gonzalez'
\set transportista_i6 'Expreso Rios'
BEGIN;
-- control previo
SELECT count(*) AS ingresos_en_confeccion FROM ingreso WHERE estado = 'en_confeccion';
INSERT INTO ingreso (cod_transporte, cuit_bodega)
SELECT t.cod_transporte, b.cuit
  FROM transportista t, bodega b
 WHERE t.razon_social = :'transportista_i6' AND b.razon_social = :'bodega_i6'
RETURNING cod_ingreso \gset
INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
SELECT :cod_ingreso, v.cod_vino, 120
  FROM vino v
  JOIN bodega b ON b.cuit = v.cuit_bodega
 WHERE v.nombre = :'vino_i6' AND v.volumen_ml = :volumen_i6 AND b.razon_social = :'bodega_i6'
 ORDER BY v.anada
 LIMIT 1;
-- control posterior
SELECT i.*, r.cod_vino, v.nombre, v.anada, v.volumen_ml, r.cantidad
  FROM ingreso i
  JOIN renglon_ingreso r ON r.cod_ingreso = i.cod_ingreso
  JOIN vino v ON v.cod_vino = r.cod_vino
 WHERE i.cod_ingreso = :cod_ingreso;
SELECT count(*) AS ingresos_en_confeccion FROM ingreso WHERE estado = 'en_confeccion';
ROLLBACK;
