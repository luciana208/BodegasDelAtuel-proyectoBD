-- triggers de las reglas de negocio

-- rn-06 asigna al cliente nuevo el descuento de su tipo
CREATE OR REPLACE FUNCTION trg_cliente_descuento() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.descuento := fn_descuento_tipo(NEW.tipo);
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_cliente_descuento
BEFORE INSERT ON cliente
FOR EACH ROW EXECUTE FUNCTION trg_cliente_descuento();

/* rn-08 los importes del comprobante no se cargan a mano: al insertarlo arrancan en cero
   y en cada update se recalculan desde sus renglones */
CREATE OR REPLACE FUNCTION trg_comprobante_importes() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.subtotal := 0;
    NEW.descuento := 0;
    NEW.total := 0;
  ELSE
    IF NEW.id_sala <> OLD.id_sala OR NEW.id_cliente <> OLD.id_cliente THEN
      RAISE EXCEPTION 'No se puede cambiar la sala ni el cliente del comprobante % (RN-08)', OLD.nro_comprobante;
    END IF;
    NEW.subtotal := fn_subtotal_comprobante(NEW.nro_comprobante);
    NEW.total := fn_total_comprobante(NEW.nro_comprobante);
    NEW.descuento := NEW.subtotal - NEW.total;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_comprobante_importes
BEFORE INSERT OR UPDATE ON comprobante
FOR EACH ROW EXECUTE FUNCTION trg_comprobante_importes();

/* rn-09 valida stock antes de vender. bloquea la fila de stock de la sala para que
   dos ventas simultaneas no vean el mismo stock */
CREATE OR REPLACE FUNCTION trg_validar_stock_venta() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_sala  INTEGER;
  v_stock INTEGER;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.cantidad <> OLD.cantidad OR NEW.cod_vino <> OLD.cod_vino
       OR NEW.nro_comprobante <> OLD.nro_comprobante THEN
      RAISE EXCEPTION 'No se puede cambiar el vino ni la cantidad de un renglon ya vendido (RN-09)';
    END IF;
    RETURN NEW;
  END IF;

  SELECT id_sala INTO v_sala FROM comprobante WHERE nro_comprobante = NEW.nro_comprobante;

  PERFORM 1 FROM stock_sala
   WHERE id_sala = v_sala AND cod_vino = NEW.cod_vino
     FOR UPDATE;

  v_stock := fn_stock_sala(v_sala, NEW.cod_vino);
  IF v_stock < NEW.cantidad THEN
    RAISE EXCEPTION 'Stock insuficiente del vino % en la sala %: hay % y se piden % (RN-09)',
                    NEW.cod_vino, v_sala, v_stock, NEW.cantidad;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_renglon_valida_stock
BEFORE INSERT OR UPDATE ON renglon_comprobante
FOR EACH ROW EXECUTE FUNCTION trg_validar_stock_venta();

/* rn-08 y rn-06 completa el precio del momento, el descuento del cliente y el subtotal
   del renglon. en un update se mantiene el precio original de la venta */
CREATE OR REPLACE FUNCTION trg_renglon_importes() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_cliente INTEGER;
BEGIN
  SELECT id_cliente INTO v_cliente FROM comprobante WHERE nro_comprobante = NEW.nro_comprobante;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El comprobante % no existe', NEW.nro_comprobante
          USING ERRCODE = 'foreign_key_violation';
  END IF;

  IF TG_OP = 'INSERT' THEN
    SELECT precio INTO NEW.precio_unitario FROM vino WHERE cod_vino = NEW.cod_vino;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'El vino % no existe', NEW.cod_vino
            USING ERRCODE = 'foreign_key_violation';
    END IF;
  ELSE
    NEW.precio_unitario := OLD.precio_unitario;
  END IF;

  NEW.porc_descuento := fn_descuento_cliente(v_cliente);
  NEW.subtotal := fn_subtotal_renglon(NEW.cantidad, NEW.precio_unitario, NEW.porc_descuento);
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_renglon_importes
BEFORE INSERT OR UPDATE ON renglon_comprobante
FOR EACH ROW EXECUTE FUNCTION trg_renglon_importes();

/* rn-09 y rn-08 despues de vender descuenta el stock de la sala y recalcula el comprobante.
   el borrado no devuelve stock porque solo se usa para depurar comprobantes viejos */
CREATE OR REPLACE FUNCTION trg_renglon_actualiza() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_nro INTEGER;
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE stock_sala s
       SET cantidad = s.cantidad - NEW.cantidad
      FROM comprobante c
     WHERE c.nro_comprobante = NEW.nro_comprobante
       AND s.id_sala = c.id_sala
       AND s.cod_vino = NEW.cod_vino;
  END IF;

  IF TG_OP = 'DELETE' THEN
    v_nro := OLD.nro_comprobante;
  ELSE
    v_nro := NEW.nro_comprobante;
  END IF;

  -- el trigger del comprobante recalcula subtotal, descuento y total
  UPDATE comprobante SET total = fn_total_comprobante(v_nro) WHERE nro_comprobante = v_nro;
  RETURN NULL;
END;
$$;

CREATE TRIGGER trg_renglon_actualiza
AFTER INSERT OR UPDATE OR DELETE ON renglon_comprobante
FOR EACH ROW EXECUTE FUNCTION trg_renglon_actualiza();

/* rn-10 y rn-11 controla los estados de ingresos y transferencias: un documento nuevo
   arranca en confeccion y solo se avanza en_confeccion -> terminado -> procesado */
CREATE OR REPLACE FUNCTION trg_control_estado() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_regla      TEXT;
  v_documento  TEXT;
  v_renglones  INTEGER;
BEGIN
  IF TG_TABLE_NAME = 'ingreso' THEN
    v_regla := 'RN-10';
    v_documento := 'El ingreso ' || NEW.cod_ingreso;
  ELSE
    v_regla := 'RN-11';
    v_documento := 'La transferencia ' || NEW.nro_transferencia;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.estado <> 'en_confeccion' THEN
      RAISE EXCEPTION '% tiene que crearse en confeccion (%)', v_documento, v_regla;
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.estado = OLD.estado THEN
    RETURN NEW;
  END IF;

  IF NOT ((OLD.estado = 'en_confeccion' AND NEW.estado = 'terminado')
       OR (OLD.estado = 'terminado' AND NEW.estado = 'procesado')) THEN
    RAISE EXCEPTION '% no puede pasar de % a % (%)', v_documento, OLD.estado, NEW.estado, v_regla;
  END IF;

  -- no se termina un documento vacio
  IF NEW.estado = 'terminado' THEN
    IF TG_TABLE_NAME = 'ingreso' THEN
      SELECT count(*) INTO v_renglones FROM renglon_ingreso WHERE cod_ingreso = NEW.cod_ingreso;
    ELSE
      SELECT count(*) INTO v_renglones FROM renglon_transferencia WHERE nro_transferencia = NEW.nro_transferencia;
    END IF;
    IF v_renglones = 0 THEN
      RAISE EXCEPTION '% no tiene renglones y no se puede terminar (%)', v_documento, v_regla;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_ingreso_estado
BEFORE INSERT OR UPDATE OF estado ON ingreso
FOR EACH ROW EXECUTE FUNCTION trg_control_estado();

CREATE TRIGGER trg_transferencia_estado
BEFORE INSERT OR UPDATE OF estado ON transferencia
FOR EACH ROW EXECUTE FUNCTION trg_control_estado();

-- rn-11 la fecha de confeccion de una transferencia es la actual y no se modifica
CREATE OR REPLACE FUNCTION trg_transferencia_fecha() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.fecha_confeccion := CURRENT_DATE;
  ELSIF NEW.fecha_confeccion <> OLD.fecha_confeccion THEN
    RAISE EXCEPTION 'La fecha de confeccion de la transferencia % no se puede modificar (RN-11)', OLD.nro_transferencia;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_transferencia_fecha
BEFORE INSERT OR UPDATE ON transferencia
FOR EACH ROW EXECUTE FUNCTION trg_transferencia_fecha();

/* rn-12 un ingreso que no esta en confeccion no admite agregar, modificar ni quitar renglones.
   si el ingreso ya no existe es porque se esta borrando en cascada y se deja pasar */
CREATE OR REPLACE FUNCTION trg_bloqueo_renglon_ingreso() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_estado estado_documento;
BEGIN
  IF TG_OP IN ('UPDATE', 'DELETE') THEN
    SELECT estado INTO v_estado FROM ingreso WHERE cod_ingreso = OLD.cod_ingreso;
    IF v_estado <> 'en_confeccion' THEN
      RAISE EXCEPTION 'El ingreso % esta en estado % y no admite cambios en sus renglones (RN-12)', OLD.cod_ingreso, v_estado;
    END IF;
  END IF;

  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    SELECT estado INTO v_estado FROM ingreso WHERE cod_ingreso = NEW.cod_ingreso;
    IF v_estado <> 'en_confeccion' THEN
      RAISE EXCEPTION 'El ingreso % esta en estado % y no admite cambios en sus renglones (RN-12)', NEW.cod_ingreso, v_estado;
    END IF;
    RETURN NEW;
  END IF;
  RETURN OLD;
END;
$$;

CREATE TRIGGER trg_renglon_ingreso_bloqueo
BEFORE INSERT OR UPDATE OR DELETE ON renglon_ingreso
FOR EACH ROW EXECUTE FUNCTION trg_bloqueo_renglon_ingreso();

-- rn-12 lo mismo para los renglones de transferencia
CREATE OR REPLACE FUNCTION trg_bloqueo_renglon_transferencia() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_estado estado_documento;
BEGIN
  IF TG_OP IN ('UPDATE', 'DELETE') THEN
    SELECT estado INTO v_estado FROM transferencia WHERE nro_transferencia = OLD.nro_transferencia;
    IF v_estado <> 'en_confeccion' THEN
      RAISE EXCEPTION 'La transferencia % esta en estado % y no admite cambios en sus renglones (RN-12)', OLD.nro_transferencia, v_estado;
    END IF;
  END IF;

  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    SELECT estado INTO v_estado FROM transferencia WHERE nro_transferencia = NEW.nro_transferencia;
    IF v_estado <> 'en_confeccion' THEN
      RAISE EXCEPTION 'La transferencia % esta en estado % y no admite cambios en sus renglones (RN-12)', NEW.nro_transferencia, v_estado;
    END IF;
    RETURN NEW;
  END IF;
  RETURN OLD;
END;
$$;

CREATE TRIGGER trg_renglon_transferencia_bloqueo
BEFORE INSERT OR UPDATE OR DELETE ON renglon_transferencia
FOR EACH ROW EXECUTE FUNCTION trg_bloqueo_renglon_transferencia();
