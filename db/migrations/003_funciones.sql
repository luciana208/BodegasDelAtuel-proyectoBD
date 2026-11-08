-- funciones de calculo

/* fn_descuento_tipo: porcentaje de descuento que corresponde a cada tipo de cliente (rn-06)
   parametros: p_tipo, tipo de cliente
   immutable: para el mismo tipo siempre devuelve lo mismo */
CREATE OR REPLACE FUNCTION fn_descuento_tipo(p_tipo tipo_cliente)
RETURNS NUMERIC(5,2)
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_tipo
           WHEN 'socio' THEN 10.00
           WHEN 'distribuidor' THEN 20.00
           WHEN 'exportador' THEN 30.00
         END::NUMERIC(5,2);
$$;

/* fn_descuento_cliente: porcentaje de descuento guardado para un cliente (rn-06)
   parametros: p_id_cliente, id del cliente
   stable: lee la tabla cliente */
CREATE OR REPLACE FUNCTION fn_descuento_cliente(p_id_cliente INTEGER)
RETURNS NUMERIC(5,2)
LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_descuento NUMERIC(5,2);
BEGIN
  SELECT descuento INTO v_descuento FROM cliente WHERE id_cliente = p_id_cliente;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El cliente % no existe', p_id_cliente;
  END IF;
  RETURN v_descuento;
END;
$$;

/* fn_subtotal_renglon: importe de un renglon con el descuento aplicado (rn-08)
   parametros: p_cantidad botellas, p_precio precio unitario, p_porc_descuento porcentaje
   immutable: depende solo de sus parametros */
CREATE OR REPLACE FUNCTION fn_subtotal_renglon(p_cantidad INTEGER, p_precio NUMERIC, p_porc_descuento NUMERIC)
RETURNS NUMERIC(12,2)
LANGUAGE sql IMMUTABLE AS $$
  SELECT ROUND(p_cantidad * p_precio * (100 - p_porc_descuento) / 100, 2);
$$;

/* fn_subtotal_comprobante: suma de cantidad por precio de los renglones, sin descuento (rn-08)
   parametros: p_nro, numero de comprobante
   stable: lee renglon_comprobante */
CREATE OR REPLACE FUNCTION fn_subtotal_comprobante(p_nro INTEGER)
RETURNS NUMERIC(12,2)
LANGUAGE sql STABLE AS $$
  SELECT COALESCE(SUM(cantidad * precio_unitario), 0)::NUMERIC(12,2)
    FROM renglon_comprobante
   WHERE nro_comprobante = p_nro;
$$;

/* fn_total_comprobante: suma de los subtotales de los renglones con su descuento (rn-08)
   parametros: p_nro, numero de comprobante
   stable: lee renglon_comprobante */
CREATE OR REPLACE FUNCTION fn_total_comprobante(p_nro INTEGER)
RETURNS NUMERIC(12,2)
LANGUAGE sql STABLE AS $$
  SELECT COALESCE(SUM(subtotal), 0)::NUMERIC(12,2)
    FROM renglon_comprobante
   WHERE nro_comprobante = p_nro;
$$;

/* fn_stock_sala: botellas de un vino en una sala, 0 si no hay fila (rn-09)
   parametros: p_sala id de la sala, p_vino codigo del vino
   stable: lee stock_sala */
CREATE OR REPLACE FUNCTION fn_stock_sala(p_sala INTEGER, p_vino INTEGER)
RETURNS INTEGER
LANGUAGE sql STABLE AS $$
  SELECT COALESCE(
    (SELECT cantidad FROM stock_sala
      WHERE id_sala = p_sala AND cod_vino = p_vino), 0);
$$;

/* fn_stock_total: botellas de un vino en el deposito mas todas las salas
   parametros: p_vino, codigo del vino
   stable: lee stock_deposito y stock_sala */
CREATE OR REPLACE FUNCTION fn_stock_total(p_vino INTEGER)
RETURNS INTEGER
LANGUAGE sql STABLE AS $$
  SELECT (COALESCE((SELECT cantidad FROM stock_deposito WHERE cod_vino = p_vino), 0)
        + COALESCE((SELECT SUM(cantidad) FROM stock_sala WHERE cod_vino = p_vino), 0))::INTEGER;
$$;

/* fn_antiguedad_anios: anios completos entre una fecha y hoy
   parametros: p_fecha, fecha de inicio (ingreso de un empleado, alta de un cliente)
   stable y no immutable: usa CURRENT_DATE, que cambia de un dia a otro */
CREATE OR REPLACE FUNCTION fn_antiguedad_anios(p_fecha DATE)
RETURNS INTEGER
LANGUAGE sql STABLE AS $$
  SELECT EXTRACT(YEAR FROM age(CURRENT_DATE, p_fecha))::INTEGER;
$$;
