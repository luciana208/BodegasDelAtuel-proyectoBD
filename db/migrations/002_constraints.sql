-- restricciones que completan el esquema de 001

-- unicidad
ALTER TABLE departamento ADD CONSTRAINT uq_departamento_nombre UNIQUE (nombre, provincia);
ALTER TABLE localidad ADD CONSTRAINT uq_localidad_nombre UNIQUE (nombre, id_departamento);
ALTER TABLE cepa ADD CONSTRAINT uq_cepa_nombre UNIQUE (nombre);
ALTER TABLE maridaje ADD CONSTRAINT uq_maridaje_nombre UNIQUE (nombre);
ALTER TABLE bodega ADD CONSTRAINT uq_bodega_razon_social UNIQUE (razon_social);
ALTER TABLE vino ADD CONSTRAINT uq_vino_nombre_anada_volumen UNIQUE (nombre, anada, volumen_ml);
-- rn-04 una parcela se cosecha a lo sumo una vez por campania
ALTER TABLE lote_uva ADD CONSTRAINT uq_lote_parcela_campania UNIQUE (id_finca, nro_parcela, campania);
ALTER TABLE cliente ADD CONSTRAINT uq_cliente_documento UNIQUE (tipo_documento, nro_documento);
ALTER TABLE socio ADD CONSTRAINT uq_socio_carnet UNIQUE (nro_carnet);
ALTER TABLE distribuidor ADD CONSTRAINT uq_distribuidor_habilitacion UNIQUE (nro_habilitacion);
ALTER TABLE transportista ADD CONSTRAINT uq_transportista_cuit UNIQUE (cuit);

-- valores validos de una fila
ALTER TABLE sala_venta ADD CONSTRAINT chk_sala_numero CHECK (numero > 0);
ALTER TABLE empleado ADD CONSTRAINT chk_empleado_salario CHECK (salario > 0);

-- rn-15 superficies, kilos y medidas positivas
ALTER TABLE finca ADD CONSTRAINT chk_finca_superficie CHECK (superficie_ha > 0);
ALTER TABLE parcela ADD CONSTRAINT chk_parcela_superficie CHECK (superficie_ha > 0);
ALTER TABLE parcela ADD CONSTRAINT chk_parcela_anio CHECK (anio_plantacion BETWEEN 1900 AND 2100);
ALTER TABLE lote_uva ADD CONSTRAINT chk_lote_kilos CHECK (kilos > 0);
ALTER TABLE lote_uva ADD CONSTRAINT chk_lote_campania CHECK (campania BETWEEN 1990 AND 2100);
-- la fecha de cosecha tiene que caer en el anio de la campania
ALTER TABLE lote_uva ADD CONSTRAINT chk_lote_fecha_campania CHECK (EXTRACT(YEAR FROM fecha_cosecha) = campania);
ALTER TABLE analisis_calidad ADD CONSTRAINT chk_analisis_brix CHECK (brix BETWEEN 0 AND 40);
ALTER TABLE analisis_calidad ADD CONSTRAINT chk_analisis_ph CHECK (ph BETWEEN 2 AND 5);
ALTER TABLE analisis_calidad ADD CONSTRAINT chk_analisis_acidez CHECK (acidez_total > 0);

-- rn-01 precio positivo y rn-15 graduacion entre 5 y 20
ALTER TABLE vino ADD CONSTRAINT chk_vino_precio CHECK (precio > 0);
ALTER TABLE vino ADD CONSTRAINT chk_vino_graduacion CHECK (graduacion BETWEEN 5 AND 20);
ALTER TABLE vino ADD CONSTRAINT chk_vino_anada CHECK (anada BETWEEN 1990 AND 2100);
ALTER TABLE vino ADD CONSTRAINT chk_vino_volumen CHECK (volumen_ml IN (187, 375, 750, 1500, 3000));
ALTER TABLE composicion ADD CONSTRAINT chk_composicion_porcentaje CHECK (porcentaje > 0 AND porcentaje <= 100);
ALTER TABLE maridaje ADD CONSTRAINT chk_maridaje_temperatura CHECK (temperatura_servicio BETWEEN 0 AND 25);

-- rn-06 rango del descuento de clientes
ALTER TABLE cliente ADD CONSTRAINT chk_cliente_tipo_documento CHECK (tipo_documento IN ('DNI', 'CUIT', 'PAS'));
ALTER TABLE cliente ADD CONSTRAINT chk_cliente_descuento CHECK (descuento BETWEEN 0 AND 50);

-- rn-07 el vencimiento es posterior a la emision
ALTER TABLE permiso_exportacion ADD CONSTRAINT chk_permiso_fechas CHECK (fecha_vencimiento > fecha_emision);

-- importes del comprobante
ALTER TABLE comprobante ADD CONSTRAINT chk_comprobante_importes
  CHECK (subtotal >= 0 AND descuento >= 0 AND total >= 0);
ALTER TABLE comprobante ADD CONSTRAINT chk_comprobante_total CHECK (total = subtotal - descuento);

-- rn-15 cantidades y precios positivos en los renglones
ALTER TABLE renglon_comprobante ADD CONSTRAINT chk_renglon_comprobante_cantidad CHECK (cantidad > 0);
ALTER TABLE renglon_comprobante ADD CONSTRAINT chk_renglon_comprobante_precio CHECK (precio_unitario > 0);
ALTER TABLE renglon_comprobante ADD CONSTRAINT chk_renglon_comprobante_descuento CHECK (porc_descuento BETWEEN 0 AND 50);
ALTER TABLE renglon_comprobante ADD CONSTRAINT chk_renglon_comprobante_subtotal CHECK (subtotal >= 0);
ALTER TABLE renglon_ingreso ADD CONSTRAINT chk_renglon_ingreso_cantidad CHECK (cantidad > 0);
ALTER TABLE renglon_transferencia ADD CONSTRAINT chk_renglon_transferencia_cantidad CHECK (cantidad > 0);

-- rn-09 el stock nunca es negativo
ALTER TABLE stock_sala ADD CONSTRAINT chk_stock_sala_cantidad CHECK (cantidad >= 0);
ALTER TABLE stock_deposito ADD CONSTRAINT chk_stock_deposito_cantidad CHECK (cantidad >= 0);

ALTER TABLE transportista ADD CONSTRAINT chk_transportista_email CHECK (email LIKE '_%@_%._%');
ALTER TABLE auditoria_precio ADD CONSTRAINT chk_auditoria_precios
  CHECK (precio_anterior > 0 AND precio_nuevo > 0 AND precio_anterior <> precio_nuevo);

-- valores por defecto
ALTER TABLE cliente ALTER COLUMN fecha_alta SET DEFAULT CURRENT_DATE;
ALTER TABLE comprobante ALTER COLUMN fecha SET DEFAULT CURRENT_DATE;
ALTER TABLE comprobante ALTER COLUMN subtotal SET DEFAULT 0;
ALTER TABLE comprobante ALTER COLUMN descuento SET DEFAULT 0;
ALTER TABLE comprobante ALTER COLUMN total SET DEFAULT 0;
ALTER TABLE stock_sala ALTER COLUMN cantidad SET DEFAULT 0;
ALTER TABLE stock_deposito ALTER COLUMN cantidad SET DEFAULT 0;
ALTER TABLE ingreso ALTER COLUMN fecha SET DEFAULT CURRENT_DATE;
ALTER TABLE ingreso ALTER COLUMN estado SET DEFAULT 'en_confeccion';
ALTER TABLE transferencia ALTER COLUMN fecha_confeccion SET DEFAULT CURRENT_DATE;
ALTER TABLE transferencia ALTER COLUMN estado SET DEFAULT 'en_confeccion';
ALTER TABLE auditoria_precio ALTER COLUMN fecha_hora SET DEFAULT LOCALTIMESTAMP;
ALTER TABLE auditoria_precio ALTER COLUMN usuario SET DEFAULT CURRENT_USER;
