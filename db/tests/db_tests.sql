/* pruebas de las reglas de negocio rn-01 a rn-15 y de los roles.
   todo corre dentro de una transaccion que termina en rollback, asi que no deja datos.
   cada caso se ejecuta en su propio bloque con manejo de excepciones y el resultado
   queda en la tabla temporal resultado_prueba, que se muestra al final.
   uso: psql -U bodega_owner -d bodegas -f db/tests/db_tests.sql */

\set ON_ERROR_STOP on
\pset pager off
SET client_min_messages = warning;

BEGIN;

CREATE TEMP TABLE resultado_prueba (
   nro      SERIAL PRIMARY KEY,
   regla    TEXT,
   caso     TEXT,
   esperado TEXT,
   obtenido TEXT,
   ok       BOOLEAN
);

-- ejecuta una sentencia que tiene que fallar con el sqlstate indicado y deshace lo que haya hecho
CREATE PROCEDURE pg_temp.debe_fallar(p_regla TEXT, p_caso TEXT, p_sql TEXT, p_sqlstate TEXT)
LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
    RAISE EXCEPTION 'la sentencia no fallo' USING ERRCODE = 'P0099';
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = 'P0099' THEN
      INSERT INTO resultado_prueba (regla, caso, esperado, obtenido, ok)
      VALUES (p_regla, p_caso, 'error ' || p_sqlstate, 'sin error', false);
    ELSE
      INSERT INTO resultado_prueba (regla, caso, esperado, obtenido, ok)
      VALUES (p_regla, p_caso, 'error ' || p_sqlstate, SQLSTATE || ' ' || SQLERRM, SQLSTATE = p_sqlstate);
    END IF;
  END;
END;
$$;

-- ejecuta una sentencia que tiene que funcionar y deja sus cambios
CREATE PROCEDURE pg_temp.debe_andar(p_regla TEXT, p_caso TEXT, p_sql TEXT)
LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
    INSERT INTO resultado_prueba (regla, caso, esperado, obtenido, ok)
    VALUES (p_regla, p_caso, 'sin error', 'sin error', true);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO resultado_prueba (regla, caso, esperado, obtenido, ok)
    VALUES (p_regla, p_caso, 'sin error', SQLSTATE || ' ' || SQLERRM, false);
  END;
END;
$$;

-- evalua una condicion que tiene que dar verdadera
CREATE PROCEDURE pg_temp.verificar(p_regla TEXT, p_caso TEXT, p_condicion TEXT)
LANGUAGE plpgsql AS $$
DECLARE
  v_ok BOOLEAN;
BEGIN
  BEGIN
    EXECUTE 'SELECT (' || p_condicion || ')' INTO v_ok;
    INSERT INTO resultado_prueba (regla, caso, esperado, obtenido, ok)
    VALUES (p_regla, p_caso, 'verdadero', COALESCE(v_ok::TEXT, 'nulo'), COALESCE(v_ok, false));
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO resultado_prueba (regla, caso, esperado, obtenido, ok)
    VALUES (p_regla, p_caso, 'verdadero', SQLSTATE || ' ' || SQLERRM, false);
  END;
END;
$$;

-- datos de prueba
INSERT INTO departamento (nombre, provincia) VALUES ('Departamento Prueba', 'Mendoza')
RETURNING id_departamento AS depto \gset
INSERT INTO localidad (nombre, cod_postal, id_departamento, encargado_regional)
VALUES ('Localidad Prueba', '5600', :depto, 'Encargado Prueba')
RETURNING id_localidad AS loc \gset
INSERT INTO sala_venta (calle, numero, dia_cierre, id_localidad) VALUES ('Calle Prueba', 1, 'lunes', :loc)
RETURNING id_sala AS sala_a \gset
INSERT INTO sala_venta (calle, numero, dia_cierre, id_localidad) VALUES ('Calle Prueba', 2, 'martes', :loc)
RETURNING id_sala AS sala_b \gset

INSERT INTO cepa (nombre, tipo) VALUES ('Cepa Prueba Tinta', 'tinta') RETURNING id_cepa AS cepa_t \gset
INSERT INTO cepa (nombre, tipo) VALUES ('Cepa Prueba Tinta Dos', 'tinta') RETURNING id_cepa AS cepa_t2 \gset
INSERT INTO cepa (nombre, tipo) VALUES ('Cepa Prueba Blanca', 'blanca') RETURNING id_cepa AS cepa_b \gset

INSERT INTO bodega (cuit, razon_social, domicilio) VALUES ('30999999991', 'Bodega Prueba', 'Calle Prueba 10');

INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
VALUES ('Vino Prueba Tinto', 'tinto', 2022, 750, 14, 10000, '30999999991')
RETURNING cod_vino AS vino_a \gset
INSERT INTO composicion (cod_vino, id_cepa, porcentaje) VALUES (:vino_a, :cepa_t, 100);
INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
VALUES ('Vino Prueba Blanco', 'blanco', 2023, 750, 12.5, 8000, '30999999991')
RETURNING cod_vino AS vino_b \gset
INSERT INTO composicion (cod_vino, id_cepa, porcentaje) VALUES (:vino_b, :cepa_b, 100);
INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
VALUES ('Vino Prueba Rosado', 'rosado', 2024, 750, 12, 7000, '30999999991')
RETURNING cod_vino AS vino_c \gset
INSERT INTO composicion (cod_vino, id_cepa, porcentaje) VALUES (:vino_c, :cepa_t, 100);

INSERT INTO transportista (razon_social, cuit, email, telefono, domicilio)
VALUES ('Transporte Prueba', '20999999992', 'prueba@transporte.com', '2604000000', 'Ruta 143 km 1')
RETURNING cod_transporte AS transp \gset

-- el socio se carga con un descuento cualquiera para ver que el trigger lo corrige
INSERT INTO cliente (nombre, tipo_documento, nro_documento, direccion, id_localidad, tipo, descuento)
VALUES ('Socio Prueba', 'DNI', '99000001', 'Calle 1', :loc, 'socio', 45)
RETURNING id_cliente AS cli_socio \gset
INSERT INTO socio (id_cliente, nro_carnet) VALUES (:cli_socio, 990001);
INSERT INTO cliente (nombre, tipo_documento, nro_documento, direccion, id_localidad, tipo)
VALUES ('Distribuidor Prueba', 'CUIT', '30999999993', 'Calle 2', :loc, 'distribuidor')
RETURNING id_cliente AS cli_dist \gset
INSERT INTO distribuidor (id_cliente, zona_cobertura, nro_habilitacion) VALUES (:cli_dist, 'Zona Prueba', 'HAB-PRUEBA-1');
INSERT INTO cliente (nombre, tipo_documento, nro_documento, direccion, id_localidad, tipo)
VALUES ('Exportador Prueba', 'CUIT', '30999999994', 'Calle 3', :loc, 'exportador')
RETURNING id_cliente AS cli_exp \gset
INSERT INTO exportador (id_cliente, pais_destino) VALUES (:cli_exp, 'Chile');

INSERT INTO finca (nombre, superficie_ha, id_departamento) VALUES ('Finca Prueba', 50, :depto)
RETURNING id_finca AS finca \gset
INSERT INTO parcela (id_finca, nro_parcela, superficie_ha, anio_plantacion, id_cepa)
VALUES (:finca, 1, 10, 2010, :cepa_t);

INSERT INTO stock_deposito (cod_vino, cantidad) VALUES (:vino_a, 100);
INSERT INTO stock_sala (id_sala, cod_vino, cantidad) VALUES (:sala_a, :vino_a, 10);

-- el comprobante se crea con importes cargados a mano para ver que el trigger los ignora
INSERT INTO comprobante (id_cliente, id_sala, subtotal, descuento, total) VALUES (:cli_dist, :sala_a, 999, 0, 999)
RETURNING nro_comprobante AS comp1 \gset
INSERT INTO comprobante (id_cliente, id_sala) VALUES (:cli_socio, :sala_a)
RETURNING nro_comprobante AS comp2 \gset

INSERT INTO ingreso (cod_transporte, cuit_bodega) VALUES (:transp, '30999999991') RETURNING cod_ingreso AS ing1 \gset
INSERT INTO ingreso (cod_transporte, cuit_bodega) VALUES (:transp, '30999999991') RETURNING cod_ingreso AS ing2 \gset

-- la fecha que se pasa tiene que ser reemplazada por la actual
INSERT INTO transferencia (id_sala, fecha_confeccion) VALUES (:sala_b, '2020-01-01') RETURNING nro_transferencia AS tr1 \gset
INSERT INTO transferencia (id_sala) VALUES (:sala_b) RETURNING nro_transferencia AS tr2 \gset
INSERT INTO transferencia (id_sala) VALUES (:sala_b) RETURNING nro_transferencia AS tr3 \gset
INSERT INTO transferencia (id_sala) VALUES (:sala_b) RETURNING nro_transferencia AS tr4 \gset

\set ON_ERROR_STOP off

-- rn-01 precio unico y mayor que cero
-- se espera 23514 por chk_vino_precio
CALL pg_temp.debe_fallar('RN-01', 'precio negativo', format('UPDATE vino SET precio = -100 WHERE cod_vino = %s', :vino_a), '23514');
-- se espera 23514 por chk_vino_precio
CALL pg_temp.debe_fallar('RN-01', 'precio cero', format('UPDATE vino SET precio = 0 WHERE cod_vino = %s', :vino_a), '23514');
CALL pg_temp.verificar('RN-01', 'el precio es una sola columna del vino, igual para todas las salas',
  $q$(SELECT array_agg(c.table_name::TEXT) = ARRAY['vino']
        FROM information_schema.columns c
        JOIN information_schema.tables t ON t.table_schema = c.table_schema AND t.table_name = c.table_name
       WHERE c.column_name = 'precio' AND c.table_schema = 'public' AND t.table_type = 'BASE TABLE')$q$);

-- rn-02 sala en una sola localidad y un encargado por localidad
-- se espera 23503 porque la localidad no existe
CALL pg_temp.debe_fallar('RN-02', 'sala con localidad inexistente', $q$INSERT INTO sala_venta (calle, numero, dia_cierre, id_localidad) VALUES ('X', 1, 'lunes', -1)$q$, '23503');
-- se espera 23502 porque el encargado es obligatorio
CALL pg_temp.debe_fallar('RN-02', 'localidad sin encargado', format($q$INSERT INTO localidad (nombre, cod_postal, id_departamento, encargado_regional) VALUES ('Otra Prueba', '5601', %s, NULL)$q$, :depto), '23502');
CALL pg_temp.verificar('RN-02', 'las dos salas de la localidad tienen el mismo encargado',
  format('(SELECT count(DISTINCT l.encargado_regional) FROM sala_venta s JOIN localidad l ON l.id_localidad = s.id_localidad WHERE s.id_sala IN (%s, %s)) = 1', :sala_a, :sala_b));

-- rn-03 cada empleado en una sola sala
CALL pg_temp.debe_andar('RN-03', 'empleado con sala', format($q$INSERT INTO empleado VALUES ('20999999990', 'Empleado Prueba', '2020-01-01', 900000, %s)$q$, :sala_a));
-- se espera 23502 porque la sala es obligatoria
CALL pg_temp.debe_fallar('RN-03', 'empleado sin sala', $q$INSERT INTO empleado VALUES ('20999999981', 'Sin Sala', '2020-01-01', 900000, NULL)$q$, '23502');
-- se espera 23503 porque la sala no existe
CALL pg_temp.debe_fallar('RN-03', 'empleado con sala inexistente', $q$INSERT INTO empleado VALUES ('20999999982', 'Sala Mala', '2020-01-01', 900000, -1)$q$, '23503');

-- rn-04 una cepa por parcela y una cosecha por parcela y campania
CALL pg_temp.debe_andar('RN-04', 'primera cosecha de la campania', format($q$INSERT INTO lote_uva (id_finca, nro_parcela, campania, fecha_cosecha, kilos, cuit_bodega) VALUES (%s, 1, 2024, '2024-03-10', 95000, '30999999991')$q$, :finca));
-- se espera 23505 por uq_lote_parcela_campania
CALL pg_temp.debe_fallar('RN-04', 'segunda cosecha en la misma campania', format($q$INSERT INTO lote_uva (id_finca, nro_parcela, campania, fecha_cosecha, kilos, cuit_bodega) VALUES (%s, 1, 2024, '2024-04-02', 1000, '30999999991')$q$, :finca), '23505');
-- se espera 23514 por chk_lote_fecha_campania
CALL pg_temp.debe_fallar('RN-04', 'fecha de cosecha fuera de la campania', format($q$INSERT INTO lote_uva (id_finca, nro_parcela, campania, fecha_cosecha, kilos, cuit_bodega) VALUES (%s, 1, 2023, '2024-03-01', 1000, '30999999991')$q$, :finca), '23514');
-- se espera 23503 porque la cepa no existe
CALL pg_temp.debe_fallar('RN-04', 'parcela con cepa inexistente', format('INSERT INTO parcela VALUES (%s, 2, 5, 2015, -1)', :finca), '23503');

-- rn-05 los porcentajes de corte suman 100 (constraint trigger diferido)
-- se espera P0001 al forzar el chequeo diferido
CALL pg_temp.debe_fallar('RN-05', 'corte que suma 90',
  format($q$INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega) VALUES ('Corte Prueba Malo', 'tinto', 2022, 750, 14, 9000, '30999999991');
            INSERT INTO composicion SELECT cod_vino, %s, 60 FROM vino WHERE nombre = 'Corte Prueba Malo';
            INSERT INTO composicion SELECT cod_vino, %s, 30 FROM vino WHERE nombre = 'Corte Prueba Malo';
            SET CONSTRAINTS trg_composicion_suma, trg_vino_composicion IMMEDIATE$q$, :cepa_t, :cepa_t2), 'P0001');
-- se espera P0001 porque el vino no tiene cepas
CALL pg_temp.debe_fallar('RN-05', 'vino sin composicion',
  $q$INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega) VALUES ('Sin Corte Prueba', 'tinto', 2022, 750, 14, 9000, '30999999991');
     SET CONSTRAINTS trg_composicion_suma, trg_vino_composicion IMMEDIATE$q$, 'P0001');
CALL pg_temp.debe_andar('RN-05', 'corte 60 y 40 cargado en dos pasos',
  format($q$INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega) VALUES ('Corte Prueba Bueno', 'tinto', 2022, 750, 14, 9000, '30999999991');
            INSERT INTO composicion SELECT cod_vino, %s, 60 FROM vino WHERE nombre = 'Corte Prueba Bueno';
            INSERT INTO composicion SELECT cod_vino, %s, 40 FROM vino WHERE nombre = 'Corte Prueba Bueno';
            SET CONSTRAINTS trg_composicion_suma, trg_vino_composicion IMMEDIATE;
            SET CONSTRAINTS ALL DEFERRED$q$, :cepa_t, :cepa_t2));
-- se espera P0001 porque el corte queda en 80
CALL pg_temp.debe_fallar('RN-05', 'modificar un porcentaje y romper la suma',
  format('UPDATE composicion SET porcentaje = 80 WHERE cod_vino = %s; SET CONSTRAINTS trg_composicion_suma IMMEDIATE', :vino_a), 'P0001');

-- rn-06 descuento segun el tipo de cliente
CALL pg_temp.verificar('RN-06', 'socio recibe 10 aunque se cargo 45', format('fn_descuento_cliente(%s) = 10', :cli_socio));
CALL pg_temp.verificar('RN-06', 'distribuidor recibe 20', format('fn_descuento_cliente(%s) = 20', :cli_dist));
CALL pg_temp.verificar('RN-06', 'exportador recibe 30', format('fn_descuento_cliente(%s) = 30', :cli_exp));
-- se espera 23514 por chk_cliente_descuento
CALL pg_temp.debe_fallar('RN-06', 'descuento fuera de rango', format('UPDATE cliente SET descuento = 60 WHERE id_cliente = %s', :cli_exp), '23514');
-- se espera 23503 porque el cliente es socio y no puede estar en distribuidor
CALL pg_temp.debe_fallar('RN-06', 'socio cargado como distribuidor', format($q$INSERT INTO distribuidor (id_cliente, zona_cobertura, nro_habilitacion) VALUES (%s, 'Z', 'HAB-X')$q$, :cli_socio), '23503');

-- rn-07 permisos de exportacion
CALL pg_temp.debe_andar('RN-07', 'primer permiso', format($q$INSERT INTO permiso_exportacion VALUES ('PERM-PRUEBA-1', %s, '2025-01-01', '2027-01-01')$q$, :cli_exp));
CALL pg_temp.debe_andar('RN-07', 'segundo permiso del mismo exportador', format($q$INSERT INTO permiso_exportacion VALUES ('PERM-PRUEBA-2', %s, '2025-06-01', '2026-06-01')$q$, :cli_exp));
-- se espera 23514 por chk_permiso_fechas
CALL pg_temp.debe_fallar('RN-07', 'vencimiento anterior a la emision', format($q$INSERT INTO permiso_exportacion VALUES ('PERM-PRUEBA-3', %s, '2025-01-01', '2024-01-01')$q$, :cli_exp), '23514');
-- se espera 23503 porque un socio no es exportador
CALL pg_temp.debe_fallar('RN-07', 'permiso para un cliente que no es exportador', format($q$INSERT INTO permiso_exportacion VALUES ('PERM-PRUEBA-4', %s, '2025-01-01', '2026-01-01')$q$, :cli_socio), '23503');

-- rn-08 el total es la suma de los renglones con descuento y no se carga a mano
CALL pg_temp.verificar('RN-08', 'el comprobante nuevo arranca en cero aunque se cargue un total', format('(SELECT total = 0 AND subtotal = 0 FROM comprobante WHERE nro_comprobante = %s)', :comp1));
CALL pg_temp.debe_andar('RN-08', 'venta de 2 botellas a un distribuidor', format('INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad, precio_unitario, subtotal) VALUES (%s, %s, 2, 1, 1)', :comp1, :vino_a));
CALL pg_temp.verificar('RN-08', 'el renglon toma el precio del vino, el 20 por ciento y calcula el subtotal',
  format('(SELECT precio_unitario = 10000 AND porc_descuento = 20 AND subtotal = 16000 FROM renglon_comprobante WHERE nro_comprobante = %s)', :comp1));
CALL pg_temp.verificar('RN-08', 'el comprobante queda con subtotal 20000, descuento 4000 y total 16000',
  format('(SELECT subtotal = 20000 AND descuento = 4000 AND total = 16000 FROM comprobante WHERE nro_comprobante = %s)', :comp1));
CALL pg_temp.debe_andar('RN-08', 'intento de cargar el total a mano', format('UPDATE comprobante SET total = 1, descuento = 0, subtotal = 1 WHERE nro_comprobante = %s', :comp1));
CALL pg_temp.verificar('RN-08', 'el total se recalcula desde los renglones', format('(SELECT total = 16000 FROM comprobante WHERE nro_comprobante = %s) AND fn_total_comprobante(%s) = 16000', :comp1, :comp1));

-- rn-09 no se vende mas de lo que hay y el stock nunca es negativo
CALL pg_temp.verificar('RN-09', 'la venta desconto 2 botellas del stock de la sala', format('fn_stock_sala(%s, %s) = 8', :sala_a, :vino_a));
-- se espera P0001 por stock insuficiente
CALL pg_temp.debe_fallar('RN-09', 'venta de 50 botellas con stock 8', format('INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad) VALUES (%s, %s, 50)', :comp2, :vino_a), 'P0001');
CALL pg_temp.verificar('RN-09', 'la venta rechazada no cambio el stock ni el comprobante',
  format('fn_stock_sala(%s, %s) = 8 AND (SELECT total = 0 FROM comprobante WHERE nro_comprobante = %s) AND NOT EXISTS (SELECT 1 FROM renglon_comprobante WHERE nro_comprobante = %s)', :sala_a, :vino_a, :comp2, :comp2));
-- se espera P0001 porque la sala no tiene ese vino
CALL pg_temp.debe_fallar('RN-09', 'venta de un vino sin stock en la sala', format('INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad) VALUES (%s, %s, 1)', :comp2, :vino_b), 'P0001');
-- se espera 23514 por chk_stock_sala_cantidad
CALL pg_temp.debe_fallar('RN-09', 'stock negativo cargado a mano', format('UPDATE stock_sala SET cantidad = -1 WHERE id_sala = %s AND cod_vino = %s', :sala_a, :vino_a), '23514');
-- se espera P0001 porque el renglon ya vendido no cambia la cantidad
CALL pg_temp.debe_fallar('RN-09', 'cambiar la cantidad de un renglon vendido', format('UPDATE renglon_comprobante SET cantidad = 1 WHERE nro_comprobante = %s', :comp1), 'P0001');
CALL pg_temp.debe_andar('RN-09', 'venta de la ultima botella', format('UPDATE stock_sala SET cantidad = 1 WHERE id_sala = %s AND cod_vino = %s; INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad) VALUES (%s, %s, 1)', :sala_a, :vino_a, :comp2, :vino_a));
CALL pg_temp.verificar('RN-09', 'el stock queda en cero', format('fn_stock_sala(%s, %s) = 0', :sala_a, :vino_a));

-- rn-10 estados de ingreso y procesamiento
-- se espera P0001 porque un ingreso nuevo arranca en confeccion
CALL pg_temp.debe_fallar('RN-10', 'crear un ingreso ya procesado', format($q$INSERT INTO ingreso (cod_transporte, cuit_bodega, estado) VALUES (%s, '30999999991', 'procesado')$q$, :transp), 'P0001');
-- se espera P0001 porque no tiene renglones
CALL pg_temp.debe_fallar('RN-10', 'terminar un ingreso vacio', format($q$UPDATE ingreso SET estado = 'terminado' WHERE cod_ingreso = %s$q$, :ing1), 'P0001');
CALL pg_temp.debe_andar('RN-10', 'cargar renglon en confeccion', format('INSERT INTO renglon_ingreso VALUES (%s, %s, 50)', :ing1, :vino_a));
-- se espera P0001 porque no puede saltar de en_confeccion a procesado
CALL pg_temp.debe_fallar('RN-10', 'saltar de en_confeccion a procesado', format($q$UPDATE ingreso SET estado = 'procesado' WHERE cod_ingreso = %s$q$, :ing1), 'P0001');
-- se espera P0001 porque solo se procesa un ingreso terminado
CALL pg_temp.debe_fallar('RN-10', 'procesar un ingreso en confeccion', format('CALL sp_procesar_ingreso(%s)', :ing1), 'P0001');
CALL pg_temp.debe_andar('RN-10', 'terminar el ingreso', format($q$UPDATE ingreso SET estado = 'terminado' WHERE cod_ingreso = %s$q$, :ing1));
CALL pg_temp.debe_andar('RN-10', 'procesar el ingreso terminado', format('CALL sp_procesar_ingreso(%s)', :ing1));
CALL pg_temp.verificar('RN-10', 'el deposito sumo 50 botellas y el ingreso quedo procesado',
  format($q$(SELECT cantidad = 150 FROM stock_deposito WHERE cod_vino = %s) AND (SELECT estado = 'procesado' FROM ingreso WHERE cod_ingreso = %s)$q$, :vino_a, :ing1));
-- se espera P0001 porque los estados no retroceden
CALL pg_temp.debe_fallar('RN-10', 'volver de procesado a en_confeccion', format($q$UPDATE ingreso SET estado = 'en_confeccion' WHERE cod_ingreso = %s$q$, :ing1), 'P0001');
-- se espera P0001 porque ya esta procesado
CALL pg_temp.debe_fallar('RN-10', 'procesar dos veces el mismo ingreso', format('CALL sp_procesar_ingreso(%s)', :ing1), 'P0001');
CALL pg_temp.debe_andar('RN-10', 'ingreso de un vino que no tenia fila en el deposito',
  format($q$INSERT INTO renglon_ingreso VALUES (%s, %s, 30); UPDATE ingreso SET estado = 'terminado' WHERE cod_ingreso = %s; CALL sp_procesar_ingreso(%s)$q$, :ing2, :vino_b, :ing2, :ing2));
CALL pg_temp.verificar('RN-10', 'se creo la fila del deposito con 30 botellas', format('(SELECT cantidad = 30 FROM stock_deposito WHERE cod_vino = %s)', :vino_b));

-- rn-11 transferencias: fecha actual, estados y procesamiento sin cambios a medias
CALL pg_temp.verificar('RN-11', 'la fecha de confeccion es la actual aunque se pase otra', format('(SELECT fecha_confeccion = CURRENT_DATE FROM transferencia WHERE nro_transferencia = %s)', :tr1));
-- se espera P0001 porque la fecha de confeccion no se modifica
CALL pg_temp.debe_fallar('RN-11', 'modificar la fecha de confeccion', format($q$UPDATE transferencia SET fecha_confeccion = '2020-01-01' WHERE nro_transferencia = %s$q$, :tr1), 'P0001');
CALL pg_temp.debe_andar('RN-11', 'transferencia de 500 botellas terminada', format($q$INSERT INTO renglon_transferencia VALUES (%s, %s, 500); UPDATE transferencia SET estado = 'terminado' WHERE nro_transferencia = %s$q$, :tr1, :vino_a, :tr1));
-- se espera P0001 porque el deposito tiene 150
CALL pg_temp.debe_fallar('RN-11', 'procesar sin stock suficiente en el deposito', format('CALL sp_procesar_transferencia(%s)', :tr1), 'P0001');
CALL pg_temp.verificar('RN-11', 'la transferencia rechazada no dejo cambios a medias',
  format($q$(SELECT cantidad = 150 FROM stock_deposito WHERE cod_vino = %s) AND fn_stock_sala(%s, %s) = 0 AND (SELECT estado = 'terminado' FROM transferencia WHERE nro_transferencia = %s)$q$, :vino_a, :sala_b, :vino_a, :tr1));
CALL pg_temp.debe_andar('RN-11', 'transferencia con un vino que no tiene fila en el deposito', format($q$INSERT INTO renglon_transferencia VALUES (%s, %s, 30), (%s, %s, 5); UPDATE transferencia SET estado = 'terminado' WHERE nro_transferencia = %s$q$, :tr2, :vino_a, :tr2, :vino_c, :tr2));
-- se espera P0001 porque el vino no esta en el deposito
CALL pg_temp.debe_fallar('RN-11', 'procesar con un vino sin fila en el deposito', format('CALL sp_procesar_transferencia(%s)', :tr2), 'P0001');
CALL pg_temp.verificar('RN-11', 'no se desconto el otro renglon de la misma transferencia', format('(SELECT cantidad = 150 FROM stock_deposito WHERE cod_vino = %s)', :vino_a));
CALL pg_temp.debe_andar('RN-11', 'procesar una transferencia de 40 botellas', format($q$INSERT INTO renglon_transferencia VALUES (%s, %s, 40); UPDATE transferencia SET estado = 'terminado' WHERE nro_transferencia = %s; CALL sp_procesar_transferencia(%s)$q$, :tr3, :vino_a, :tr3, :tr3));
CALL pg_temp.verificar('RN-11', 'el deposito bajo a 110, la sala tiene 40 y la transferencia quedo procesada',
  format($q$(SELECT cantidad = 110 FROM stock_deposito WHERE cod_vino = %s) AND fn_stock_sala(%s, %s) = 40 AND (SELECT estado = 'procesado' FROM transferencia WHERE nro_transferencia = %s)$q$, :vino_a, :sala_b, :vino_a, :tr3));
-- se espera P0001 porque los estados no retroceden
CALL pg_temp.debe_fallar('RN-11', 'volver de procesado a terminado', format($q$UPDATE transferencia SET estado = 'terminado' WHERE nro_transferencia = %s$q$, :tr3), 'P0001');
-- se espera P0001 porque esta en confeccion
CALL pg_temp.debe_fallar('RN-11', 'procesar una transferencia en confeccion', format('CALL sp_procesar_transferencia(%s)', :tr4), 'P0001');

-- rn-12 renglones bloqueados fuera de confeccion
-- se espera P0001 porque el ingreso esta procesado
CALL pg_temp.debe_fallar('RN-12', 'agregar renglon a un ingreso procesado', format('INSERT INTO renglon_ingreso VALUES (%s, %s, 10)', :ing1, :vino_c), 'P0001');
-- se espera P0001 porque la transferencia esta procesada
CALL pg_temp.debe_fallar('RN-12', 'modificar renglon de una transferencia procesada', format('UPDATE renglon_transferencia SET cantidad = 1 WHERE nro_transferencia = %s', :tr3), 'P0001');
-- se espera P0001 porque la transferencia esta terminada
CALL pg_temp.debe_fallar('RN-12', 'quitar renglon de una transferencia terminada', format('DELETE FROM renglon_transferencia WHERE nro_transferencia = %s', :tr1), 'P0001');
CALL pg_temp.debe_andar('RN-12', 'agregar, modificar y quitar renglones en confeccion',
  format('INSERT INTO renglon_transferencia VALUES (%s, %s, 5); UPDATE renglon_transferencia SET cantidad = 6 WHERE nro_transferencia = %s; DELETE FROM renglon_transferencia WHERE nro_transferencia = %s', :tr4, :vino_a, :tr4, :tr4));

-- rn-13 auditoria de precio
CALL pg_temp.debe_andar('RN-13', 'cambio de precio', format('UPDATE vino SET precio = 11000 WHERE cod_vino = %s', :vino_a));
CALL pg_temp.verificar('RN-13', 'quedo registrado el precio anterior, el nuevo, la fecha y el usuario',
  format('(SELECT count(*) = 1 AND bool_and(precio_anterior = 10000 AND precio_nuevo = 11000 AND usuario = CURRENT_USER AND fecha_hora IS NOT NULL) FROM auditoria_precio WHERE cod_vino = %s)', :vino_a));
CALL pg_temp.debe_andar('RN-13', 'cambio de otro dato del vino', format($q$UPDATE vino SET graduacion = 14.5 WHERE cod_vino = %s$q$, :vino_a));
CALL pg_temp.verificar('RN-13', 'si no cambia el precio no se audita', format('(SELECT count(*) = 1 FROM auditoria_precio WHERE cod_vino = %s)', :vino_a));
-- se espera 42501 porque la api no puede borrar la auditoria
CALL pg_temp.debe_fallar('RN-13', 'la api intenta borrar la auditoria', 'SET LOCAL ROLE bodega_app; DELETE FROM auditoria_precio', '42501');

-- rn-14 no se borran vinos, bodegas ni transportistas con movimientos
-- se espera 23503 por las fk con restrict
CALL pg_temp.debe_fallar('RN-14', 'borrar un vino con ventas', format('DELETE FROM vino WHERE cod_vino = %s', :vino_a), '23503');
-- se espera 23503 por las fk con restrict
CALL pg_temp.debe_fallar('RN-14', 'borrar una bodega con vinos e ingresos', $q$DELETE FROM bodega WHERE cuit = '30999999991'$q$, '23503');
-- se espera 23503 por las fk con restrict
CALL pg_temp.debe_fallar('RN-14', 'borrar un transportista con ingresos', format('DELETE FROM transportista WHERE cod_transporte = %s', :transp), '23503');
CALL pg_temp.debe_andar('RN-14', 'borrar un vino sin movimientos',
  format($q$INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega) VALUES ('Vino Prueba Borrable', 'tinto', 2022, 750, 14, 5000, '30999999991');
            INSERT INTO composicion SELECT cod_vino, %s, 100 FROM vino WHERE nombre = 'Vino Prueba Borrable';
            DELETE FROM vino WHERE nombre = 'Vino Prueba Borrable'$q$, :cepa_t));

-- rn-15 cantidades, superficies, kilos y precios positivos, graduacion entre 5 y 20
-- se espera 23514 en todos los casos
CALL pg_temp.debe_fallar('RN-15', 'renglon de transferencia con cantidad cero', format('INSERT INTO renglon_transferencia VALUES (%s, %s, 0)', :tr4, :vino_b), '23514');
CALL pg_temp.debe_fallar('RN-15', 'parcela con superficie negativa', format('INSERT INTO parcela VALUES (%s, 3, -2, 2015, %s)', :finca, :cepa_t), '23514');
CALL pg_temp.debe_fallar('RN-15', 'finca con superficie cero', format($q$INSERT INTO finca (nombre, superficie_ha, id_departamento) VALUES ('Finca Cero', 0, %s)$q$, :depto), '23514');
CALL pg_temp.debe_fallar('RN-15', 'lote con kilos negativos', format($q$INSERT INTO lote_uva (id_finca, nro_parcela, campania, fecha_cosecha, kilos, cuit_bodega) VALUES (%s, 1, 2025, '2025-03-01', -5, '30999999991')$q$, :finca), '23514');
CALL pg_temp.debe_fallar('RN-15', 'graduacion de 25', format('UPDATE vino SET graduacion = 25 WHERE cod_vino = %s', :vino_a), '23514');
CALL pg_temp.debe_fallar('RN-15', 'graduacion de 4', format('UPDATE vino SET graduacion = 4 WHERE cod_vino = %s', :vino_a), '23514');
CALL pg_temp.debe_fallar('RN-15', 'renglon de ingreso con cantidad negativa', format($q$INSERT INTO ingreso (cod_transporte, cuit_bodega) VALUES (%s, '30999999991'); INSERT INTO renglon_ingreso SELECT max(cod_ingreso), %s, -3 FROM ingreso$q$, :transp, :vino_a), '23514');

-- roles y privilegios
CALL pg_temp.debe_andar('ROLES', 'la api lee datos y usa funciones con su rol', format('SET LOCAL ROLE bodega_app; SELECT count(*) FROM vino; SELECT fn_total_comprobante(%s); RESET ROLE', :comp1));
-- se espera 42501 en todos los casos
CALL pg_temp.debe_fallar('ROLES', 'la api no puede vaciar tablas', 'SET LOCAL ROLE bodega_app; TRUNCATE vino CASCADE', '42501');
CALL pg_temp.debe_fallar('ROLES', 'la api no puede crear tablas', 'SET LOCAL ROLE bodega_app; CREATE TABLE prueba_api (a INTEGER)', '42501');
CALL pg_temp.debe_fallar('ROLES', 'la api no puede modificar la auditoria', 'SET LOCAL ROLE bodega_app; UPDATE auditoria_precio SET usuario = current_user', '42501');
CALL pg_temp.debe_fallar('ROLES', 'el rol de lectura no puede insertar', $q$SET LOCAL ROLE bodega_lectura; INSERT INTO cepa (nombre, tipo) VALUES ('X', 'tinta')$q$, '42501');
CALL pg_temp.debe_fallar('ROLES', 'el rol de lectura no puede procesar transferencias', format('SET LOCAL ROLE bodega_lectura; CALL sp_procesar_transferencia(%s)', :tr1), '42501');

-- resultados
\pset format aligned
SELECT nro, regla, caso, esperado, obtenido, CASE WHEN ok THEN 'ok' ELSE 'FALLA' END AS resultado
  FROM resultado_prueba
 ORDER BY nro;

SELECT count(*) AS casos,
       count(*) FILTER (WHERE ok) AS ok,
       count(*) FILTER (WHERE NOT ok) AS fallas,
       count(DISTINCT regla) FILTER (WHERE regla LIKE 'RN-%') AS reglas_cubiertas
  FROM resultado_prueba;

ROLLBACK;
