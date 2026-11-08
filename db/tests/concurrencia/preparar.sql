-- crea los datos de la demostracion de la ultima botella si no existen y deja el stock en 1

BEGIN;

INSERT INTO departamento (nombre, provincia)
SELECT 'Departamento Concurrencia', 'Mendoza'
 WHERE NOT EXISTS (SELECT 1 FROM departamento WHERE nombre = 'Departamento Concurrencia');

INSERT INTO localidad (nombre, cod_postal, id_departamento, encargado_regional)
SELECT 'Localidad Concurrencia', '5600', id_departamento, 'Encargado Concurrencia'
  FROM departamento
 WHERE nombre = 'Departamento Concurrencia'
   AND NOT EXISTS (SELECT 1 FROM localidad WHERE nombre = 'Localidad Concurrencia');

INSERT INTO sala_venta (calle, numero, dia_cierre, id_localidad)
SELECT 'Calle Concurrencia', 1, 'lunes', id_localidad
  FROM localidad
 WHERE nombre = 'Localidad Concurrencia'
   AND NOT EXISTS (SELECT 1 FROM sala_venta WHERE calle = 'Calle Concurrencia');

INSERT INTO cepa (nombre, tipo)
SELECT 'Cepa Concurrencia', 'tinta'
 WHERE NOT EXISTS (SELECT 1 FROM cepa WHERE nombre = 'Cepa Concurrencia');

INSERT INTO bodega (cuit, razon_social, domicilio)
SELECT '30999999985', 'Bodega Concurrencia', 'Calle Concurrencia 2'
 WHERE NOT EXISTS (SELECT 1 FROM bodega WHERE cuit = '30999999985');

INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
SELECT 'Vino Concurrencia', 'tinto', 2022, 750, 14, 10000, '30999999985'
 WHERE NOT EXISTS (SELECT 1 FROM vino WHERE nombre = 'Vino Concurrencia');

INSERT INTO composicion (cod_vino, id_cepa, porcentaje)
SELECT v.cod_vino, c.id_cepa, 100
  FROM vino v, cepa c
 WHERE v.nombre = 'Vino Concurrencia' AND c.nombre = 'Cepa Concurrencia'
ON CONFLICT DO NOTHING;

INSERT INTO cliente (nombre, tipo_documento, nro_documento, direccion, id_localidad, tipo)
SELECT 'Cliente Concurrencia', 'DNI', '99999985', 'Calle Concurrencia 3', id_localidad, 'socio'
  FROM localidad
 WHERE nombre = 'Localidad Concurrencia'
   AND NOT EXISTS (SELECT 1 FROM cliente WHERE nro_documento = '99999985');

INSERT INTO stock_sala (id_sala, cod_vino, cantidad)
SELECT s.id_sala, v.cod_vino, 1
  FROM sala_venta s, vino v
 WHERE s.calle = 'Calle Concurrencia' AND v.nombre = 'Vino Concurrencia'
ON CONFLICT (id_sala, cod_vino) DO UPDATE SET cantidad = 1;

COMMIT;

SELECT s.id_sala, v.cod_vino, ss.cantidad AS stock
  FROM stock_sala ss
  JOIN sala_venta s ON s.id_sala = ss.id_sala
  JOIN vino v ON v.cod_vino = ss.cod_vino
 WHERE s.calle = 'Calle Concurrencia' AND v.nombre = 'Vino Concurrencia';
