-- procedimientos transaccionales

/* sp_procesar_ingreso: suma al deposito central los renglones de un ingreso terminado
   y lo pasa a procesado (rn-10). si algo falla no queda ningun cambio */
CREATE OR REPLACE PROCEDURE sp_procesar_ingreso(p_cod INTEGER)
LANGUAGE plpgsql AS $$
DECLARE
  v_estado estado_documento;
BEGIN
  -- bloquea el ingreso para que nadie lo procese al mismo tiempo
  SELECT estado INTO v_estado
    FROM ingreso WHERE cod_ingreso = p_cod FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'El ingreso % no existe', p_cod;
  END IF;

  IF v_estado <> 'terminado' THEN
    RAISE EXCEPTION 'El ingreso % esta en estado % y solo se puede procesar si esta terminado (RN-10)', p_cod, v_estado;
  END IF;

  -- bloquea las filas del deposito que se van a modificar
  PERFORM 1
     FROM stock_deposito d
    WHERE d.cod_vino IN (SELECT cod_vino FROM renglon_ingreso WHERE cod_ingreso = p_cod)
    ORDER BY d.cod_vino
      FOR UPDATE;

  -- suma al deposito y crea la fila si el vino todavia no tenia
  INSERT INTO stock_deposito (cod_vino, cantidad)
  SELECT cod_vino, cantidad
    FROM renglon_ingreso
   WHERE cod_ingreso = p_cod
  ON CONFLICT (cod_vino)
  DO UPDATE SET cantidad = stock_deposito.cantidad + EXCLUDED.cantidad;

  UPDATE ingreso SET estado = 'procesado' WHERE cod_ingreso = p_cod;
END;
$$;

/* sp_procesar_transferencia: descuenta del deposito central y suma a la sala los renglones
   de una transferencia terminada, y la pasa a procesado (rn-11). si un vino no tiene fila
   en el deposito o no alcanza el stock, falla sin dejar cambios */
CREATE OR REPLACE PROCEDURE sp_procesar_transferencia(p_nro INTEGER)
LANGUAGE plpgsql AS $$
DECLARE
  v_estado   estado_documento;
  v_sala     INTEGER;
  v_vino     INTEGER;
  v_pedido   INTEGER;
  v_hay      INTEGER;
BEGIN
  SELECT estado, id_sala INTO v_estado, v_sala
    FROM transferencia WHERE nro_transferencia = p_nro FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'La transferencia % no existe', p_nro;
  END IF;

  IF v_estado <> 'terminado' THEN
    RAISE EXCEPTION 'La transferencia % esta en estado % y solo se puede procesar si esta terminada (RN-11)', p_nro, v_estado;
  END IF;

  -- bloquea el stock del deposito de los vinos pedidos, siempre en el mismo orden
  PERFORM 1
     FROM stock_deposito d
    WHERE d.cod_vino IN (SELECT cod_vino FROM renglon_transferencia WHERE nro_transferencia = p_nro)
    ORDER BY d.cod_vino
      FOR UPDATE;

  -- vino pedido que no tiene fila en el deposito
  SELECT r.cod_vino INTO v_vino
    FROM renglon_transferencia r
   WHERE r.nro_transferencia = p_nro
     AND NOT EXISTS (SELECT 1 FROM stock_deposito d WHERE d.cod_vino = r.cod_vino)
   ORDER BY r.cod_vino
   LIMIT 1;

  IF FOUND THEN
    RAISE EXCEPTION 'El vino % de la transferencia % no tiene stock en el deposito central (RN-11)', v_vino, p_nro;
  END IF;

  -- vino pedido con stock insuficiente
  SELECT r.cod_vino, r.cantidad, d.cantidad INTO v_vino, v_pedido, v_hay
    FROM renglon_transferencia r
    JOIN stock_deposito d ON d.cod_vino = r.cod_vino
   WHERE r.nro_transferencia = p_nro
     AND d.cantidad < r.cantidad
   ORDER BY r.cod_vino
   LIMIT 1;

  IF FOUND THEN
    RAISE EXCEPTION 'Stock insuficiente en el deposito central para el vino %: hay % y se piden % (RN-11)',
                    v_vino, v_hay, v_pedido;
  END IF;

  UPDATE stock_deposito d
     SET cantidad = d.cantidad - r.cantidad
    FROM renglon_transferencia r
   WHERE r.nro_transferencia = p_nro AND d.cod_vino = r.cod_vino;

  INSERT INTO stock_sala (id_sala, cod_vino, cantidad)
  SELECT v_sala, cod_vino, cantidad
    FROM renglon_transferencia
   WHERE nro_transferencia = p_nro
  ON CONFLICT (id_sala, cod_vino)
  DO UPDATE SET cantidad = stock_sala.cantidad + EXCLUDED.cantidad;

  UPDATE transferencia SET estado = 'procesado' WHERE nro_transferencia = p_nro;
END;
$$;
