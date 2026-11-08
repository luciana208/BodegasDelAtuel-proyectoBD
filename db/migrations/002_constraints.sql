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
