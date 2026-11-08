-- borra todo lo que crea preparar.sql y las ventas de la demostracion

BEGIN;

DELETE FROM comprobante
 WHERE id_cliente IN (SELECT id_cliente FROM cliente WHERE nro_documento = '99999985');
DELETE FROM socio WHERE id_cliente IN (SELECT id_cliente FROM cliente WHERE nro_documento = '99999985');
DELETE FROM cliente WHERE nro_documento = '99999985';
DELETE FROM stock_sala WHERE cod_vino IN (SELECT cod_vino FROM vino WHERE nombre = 'Vino Concurrencia');
DELETE FROM vino WHERE nombre = 'Vino Concurrencia';
DELETE FROM bodega WHERE cuit = '30999999985';
DELETE FROM cepa WHERE nombre = 'Cepa Concurrencia';
DELETE FROM sala_venta WHERE calle = 'Calle Concurrencia';
DELETE FROM localidad WHERE nombre = 'Localidad Concurrencia';
DELETE FROM departamento WHERE nombre = 'Departamento Concurrencia';

COMMIT;
