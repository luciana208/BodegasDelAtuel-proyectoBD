# Diccionario de datos

Para cada tabla se indica el tipo de cada columna, si admite nulos, las restricciones y una descripción. Los tipos y las claves salen de `db/migrations/001_esquema.sql`; los UNIQUE, CHECK y DEFAULT de `db/migrations/002_constraints.sql`. Cuando un valor lo completa un trigger se indica cuál (`db/migrations/005_triggers.sql`).

## departamento

Departamentos de cada provincia. Se usa para ubicar localidades y fincas.

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| id_departamento | SMALLINT | No | PK, identity | Identificador del departamento |
| nombre | VARCHAR(40) | No | UNIQUE uq_departamento_nombre (nombre, provincia) | Nombre del departamento |
| provincia | VARCHAR(40) | No | UNIQUE uq_departamento_nombre (nombre, provincia) | Provincia a la que pertenece |

## localidad

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| id_localidad | INTEGER | No | PK, identity | Identificador de la localidad |
| nombre | VARCHAR(60) | No | UNIQUE uq_localidad_nombre (nombre, id_departamento) | Nombre de la localidad |
| cod_postal | cod_postal_dom | No | 4 dígitos (dominio) | Código postal |
| id_departamento | SMALLINT | No | FK departamento, ON DELETE RESTRICT, ON UPDATE RESTRICT | Departamento donde está la localidad |
| encargado_regional | VARCHAR(80) | No | | Responsable comercial de la localidad, el mismo para todas sus salas |

## sala_venta

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| id_sala | INTEGER | No | PK, identity | Identificador de la sala |
| calle | VARCHAR(80) | No | | Calle de la dirección |
| numero | INTEGER | No | CHECK chk_sala_numero (> 0) | Número de la dirección |
| dia_cierre | dia_semana | No | ENUM | Día de cierre semanal |
| id_localidad | INTEGER | No | FK localidad, ON DELETE RESTRICT, ON UPDATE RESTRICT | Localidad donde está la sala |

## empleado

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| cuit | cuit_dom | No | PK, 11 dígitos (dominio) | CUIT del empleado |
| nombre | VARCHAR(80) | No | | Apellido y nombre |
| fecha_ingreso | DATE | No | | Fecha de ingreso laboral |
| salario | NUMERIC(12,2) | No | CHECK chk_empleado_salario (> 0) | Salario mensual |
| id_sala | INTEGER | No | FK sala_venta, ON DELETE RESTRICT, ON UPDATE RESTRICT | Sala donde trabaja |

## cepa

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| id_cepa | SMALLINT | No | PK, identity | Identificador de la cepa |
| nombre | VARCHAR(40) | No | UNIQUE uq_cepa_nombre | Nombre de la cepa |
| tipo | tipo_cepa | No | ENUM | Tinta o blanca |

## finca

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| id_finca | INTEGER | No | PK, identity | Identificador de la finca |
| nombre | VARCHAR(80) | No | | Nombre de la finca |
| superficie_ha | NUMERIC(8,2) | No | CHECK chk_finca_superficie (> 0) | Superficie total en hectáreas |
| id_departamento | SMALLINT | No | FK departamento, ON DELETE RESTRICT, ON UPDATE RESTRICT | Departamento donde está la finca |

## parcela

Entidad débil: no existe sin su finca.

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| id_finca | INTEGER | No | PK (1), FK finca, ON DELETE CASCADE, ON UPDATE RESTRICT | Finca a la que pertenece |
| nro_parcela | SMALLINT | No | PK (2) | Número de parcela dentro de la finca |
| superficie_ha | NUMERIC(7,2) | No | CHECK chk_parcela_superficie (> 0) | Superficie en hectáreas |
| anio_plantacion | SMALLINT | No | CHECK chk_parcela_anio (entre 1900 y 2100) | Año en que se plantó |
| id_cepa | SMALLINT | No | FK cepa, ON DELETE RESTRICT, ON UPDATE RESTRICT | Cepa plantada (una sola) |

## bodega

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| cuit | cuit_dom | No | PK, 11 dígitos (dominio) | CUIT de la bodega |
| razon_social | VARCHAR(100) | No | UNIQUE uq_bodega_razon_social | Razón social |
| domicilio | VARCHAR(120) | No | | Domicilio |

## lote_uva

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| nro_lote | INTEGER | No | PK, identity | Número de lote |
| id_finca | INTEGER | No | FK (1) parcela, ON DELETE RESTRICT, ON UPDATE CASCADE, UNIQUE uq_lote_parcela_campania (id_finca, nro_parcela, campania) | Finca de la parcela cosechada |
| nro_parcela | SMALLINT | No | FK (2) parcela | Parcela cosechada |
| campania | SMALLINT | No | CHECK chk_lote_campania (entre 1990 y 2100), UNIQUE uq_lote_parcela_campania | Año de cosecha |
| fecha_cosecha | DATE | No | CHECK chk_lote_fecha_campania (el año de la fecha es la campaña) | Fecha de la cosecha |
| kilos | NUMERIC(10,2) | No | CHECK chk_lote_kilos (> 0) | Kilos cosechados |
| cuit_bodega | cuit_dom | No | FK bodega, ON DELETE RESTRICT, ON UPDATE CASCADE | Bodega a la que se entregó |

## analisis_calidad

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| id_analisis | INTEGER | No | PK, identity | Identificador del análisis |
| nro_lote | INTEGER | No | FK lote_uva, ON DELETE CASCADE, ON UPDATE RESTRICT | Lote analizado |
| fecha | DATE | No | | Fecha del análisis |
| brix | NUMERIC(4,1) | No | CHECK chk_analisis_brix (entre 0 y 40) | Grado Brix |
| ph | NUMERIC(3,2) | No | CHECK chk_analisis_ph (entre 2 y 5) | pH |
| acidez_total | NUMERIC(4,2) | No | CHECK chk_analisis_acidez (> 0) | Acidez total en g/L |

## vino

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| cod_vino | INTEGER | No | PK, identity | Código del vino |
| nombre | VARCHAR(80) | No | UNIQUE uq_vino_nombre_anada_volumen (nombre, anada, volumen_ml) | Nombre comercial |
| tipo | tipo_vino | No | ENUM | Tinto, blanco, rosado o espumante |
| anada | SMALLINT | No | CHECK chk_vino_anada (entre 1990 y 2100) | Año de la cosecha de la uva |
| volumen_ml | INTEGER | No | CHECK chk_vino_volumen (187, 375, 750, 1500 o 3000) | Presentación en ml |
| graduacion | NUMERIC(4,2) | No | CHECK chk_vino_graduacion (entre 5 y 20) | Graduación alcohólica |
| precio | NUMERIC(10,2) | No | CHECK chk_vino_precio (> 0) | Precio de venta, igual en todas las salas |
| cuit_bodega | cuit_dom | No | FK bodega, ON DELETE RESTRICT, ON UPDATE CASCADE | Bodega que lo elabora |

## composicion

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| cod_vino | INTEGER | No | PK (1), FK vino, ON DELETE CASCADE, ON UPDATE RESTRICT | Vino |
| id_cepa | SMALLINT | No | PK (2), FK cepa, ON DELETE RESTRICT, ON UPDATE RESTRICT | Cepa que forma parte del corte |
| porcentaje | NUMERIC(5,2) | No | CHECK chk_composicion_porcentaje (> 0 y <= 100) | Porcentaje de la cepa en el corte |

## maridaje

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| id_maridaje | SMALLINT | No | PK, identity | Identificador del maridaje |
| nombre | VARCHAR(60) | No | UNIQUE uq_maridaje_nombre | Nombre (por ejemplo carnes rojas) |
| temperatura_servicio | NUMERIC(4,1) | No | CHECK chk_maridaje_temperatura (entre 0 y 25) | Temperatura de servicio sugerida en °C |

## vino_maridaje

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| cod_vino | INTEGER | No | PK (1), FK vino, ON DELETE CASCADE, ON UPDATE RESTRICT | Vino |
| id_maridaje | SMALLINT | No | PK (2), FK maridaje, ON DELETE CASCADE, ON UPDATE RESTRICT | Maridaje recomendado |

## cliente

Supertipo de la jerarquía de clientes.

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| id_cliente | INTEGER | No | PK, identity, UNIQUE (id_cliente, tipo) | Identificador del cliente |
| nombre | VARCHAR(120) | No | | Apellido y nombre o razón social |
| tipo_documento | VARCHAR(4) | No | CHECK chk_cliente_tipo_documento ('DNI', 'CUIT' o 'PAS'), UNIQUE uq_cliente_documento (tipo_documento, nro_documento) | Tipo de documento |
| nro_documento | VARCHAR(13) | No | UNIQUE uq_cliente_documento | Número de documento |
| direccion | VARCHAR(120) | No | | Dirección |
| id_localidad | INTEGER | No | FK localidad, ON DELETE RESTRICT, ON UPDATE RESTRICT | Localidad del cliente |
| fecha_alta | DATE | No | DEFAULT CURRENT_DATE | Fecha de alta |
| tipo | tipo_cliente | No | ENUM, UNIQUE (id_cliente, tipo) | Subtipo del cliente |
| descuento | NUMERIC(5,2) | No | CHECK chk_cliente_descuento (entre 0 y 50), lo completa trg_cliente_descuento | Porcentaje de descuento que se le aplica |

## socio

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| id_cliente | INTEGER | No | PK, FK (1) cliente, ON DELETE CASCADE, ON UPDATE RESTRICT | Cliente |
| tipo | tipo_cliente | No | FK (2) cliente, DEFAULT 'socio', CHECK tipo = 'socio' | Tipo fijo del subtipo |
| nro_carnet | INTEGER | No | UNIQUE uq_socio_carnet | Número de carnet del club |

## distribuidor

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| id_cliente | INTEGER | No | PK, FK (1) cliente, ON DELETE CASCADE, ON UPDATE RESTRICT | Cliente |
| tipo | tipo_cliente | No | FK (2) cliente, DEFAULT 'distribuidor', CHECK tipo = 'distribuidor' | Tipo fijo del subtipo |
| zona_cobertura | VARCHAR(80) | No | | Zona que cubre |
| nro_habilitacion | VARCHAR(20) | No | UNIQUE uq_distribuidor_habilitacion | Número de habilitación |

## exportador

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| id_cliente | INTEGER | No | PK, FK (1) cliente, ON DELETE CASCADE, ON UPDATE RESTRICT | Cliente |
| tipo | tipo_cliente | No | FK (2) cliente, DEFAULT 'exportador', CHECK tipo = 'exportador' | Tipo fijo del subtipo |
| pais_destino | VARCHAR(60) | No | | País de destino principal |

## permiso_exportacion

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| cod_permiso | VARCHAR(20) | No | PK | Código del permiso |
| id_cliente | INTEGER | No | FK exportador, ON DELETE CASCADE, ON UPDATE RESTRICT | Exportador titular |
| fecha_emision | DATE | No | | Fecha de emisión |
| fecha_vencimiento | DATE | No | CHECK chk_permiso_fechas (> fecha_emision) | Fecha de vencimiento |

## comprobante

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| nro_comprobante | INTEGER | No | PK, identity | Número de comprobante |
| fecha | DATE | No | DEFAULT CURRENT_DATE | Fecha de la venta |
| id_cliente | INTEGER | No | FK cliente, ON DELETE RESTRICT, ON UPDATE RESTRICT | Cliente que compra |
| id_sala | INTEGER | No | FK sala_venta, ON DELETE RESTRICT, ON UPDATE RESTRICT | Sala donde se vendió |
| subtotal | NUMERIC(12,2) | No | DEFAULT 0, CHECK chk_comprobante_importes (>= 0), lo calcula trg_comprobante_importes | Suma de cantidad por precio de los renglones, sin descuento |
| descuento | NUMERIC(12,2) | No | DEFAULT 0, CHECK chk_comprobante_importes (>= 0), lo calcula trg_comprobante_importes | Importe descontado |
| total | NUMERIC(12,2) | No | DEFAULT 0, CHECK chk_comprobante_importes (>= 0), CHECK chk_comprobante_total (= subtotal - descuento), lo calcula trg_comprobante_importes | Suma de los subtotales de los renglones |

## renglon_comprobante

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| nro_comprobante | INTEGER | No | PK (1), FK comprobante, ON DELETE CASCADE, ON UPDATE RESTRICT | Comprobante |
| cod_vino | INTEGER | No | PK (2), FK vino, ON DELETE RESTRICT, ON UPDATE RESTRICT | Vino vendido |
| cantidad | INTEGER | No | CHECK chk_renglon_comprobante_cantidad (> 0) | Botellas vendidas |
| precio_unitario | NUMERIC(10,2) | No | CHECK chk_renglon_comprobante_precio (> 0), lo completa trg_renglon_importes | Precio del vino al momento de la venta |
| porc_descuento | NUMERIC(5,2) | No | CHECK chk_renglon_comprobante_descuento (entre 0 y 50), lo completa trg_renglon_importes | Porcentaje de descuento aplicado según el tipo de cliente |
| subtotal | NUMERIC(12,2) | No | CHECK chk_renglon_comprobante_subtotal (>= 0), lo calcula trg_renglon_importes | Cantidad por precio con el descuento aplicado |

## stock_sala

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| id_sala | INTEGER | No | PK (1), FK sala_venta, ON DELETE RESTRICT, ON UPDATE RESTRICT | Sala |
| cod_vino | INTEGER | No | PK (2), FK vino, ON DELETE RESTRICT, ON UPDATE RESTRICT | Vino |
| cantidad | INTEGER | No | DEFAULT 0, CHECK chk_stock_sala_cantidad (>= 0) | Botellas disponibles en la sala |

## stock_deposito

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| cod_vino | INTEGER | No | PK, FK vino, ON DELETE RESTRICT, ON UPDATE RESTRICT | Vino |
| cantidad | INTEGER | No | DEFAULT 0, CHECK chk_stock_deposito_cantidad (>= 0) | Botellas disponibles en el depósito central |

## transportista

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| cod_transporte | INTEGER | No | PK, identity | Código del transportista |
| razon_social | VARCHAR(100) | No | | Razón social |
| cuit | cuit_dom | No | 11 dígitos (dominio), UNIQUE uq_transportista_cuit | CUIT |
| email | VARCHAR(100) | No | CHECK chk_transportista_email (forma 'algo@algo.algo') | Correo electrónico |
| telefono | VARCHAR(20) | No | | Teléfono |
| domicilio | VARCHAR(120) | No | | Domicilio |

## transportista_localidad

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| cod_transporte | INTEGER | No | PK (1), FK transportista, ON DELETE CASCADE, ON UPDATE RESTRICT | Transportista |
| id_localidad | INTEGER | No | PK (2), FK localidad, ON DELETE RESTRICT, ON UPDATE RESTRICT | Localidad a la que llega el servicio |

## ingreso

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| cod_ingreso | INTEGER | No | PK, identity | Código del ingreso |
| fecha | DATE | No | DEFAULT CURRENT_DATE | Fecha del ingreso |
| estado | estado_documento | No | ENUM, DEFAULT 'en_confeccion' | Estado del documento |
| cod_transporte | INTEGER | No | FK transportista, ON DELETE RESTRICT, ON UPDATE RESTRICT | Transportista que hizo el traslado |
| cuit_bodega | cuit_dom | No | FK bodega, ON DELETE RESTRICT, ON UPDATE CASCADE | Bodega de origen |

## renglon_ingreso

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| cod_ingreso | INTEGER | No | PK (1), FK ingreso, ON DELETE CASCADE, ON UPDATE RESTRICT | Ingreso |
| cod_vino | INTEGER | No | PK (2), FK vino, ON DELETE RESTRICT, ON UPDATE RESTRICT | Vino ingresado |
| cantidad | INTEGER | No | CHECK chk_renglon_ingreso_cantidad (> 0) | Botellas ingresadas |

## transferencia

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| nro_transferencia | INTEGER | No | PK, identity | Número de solicitud |
| id_sala | INTEGER | No | FK sala_venta, ON DELETE RESTRICT, ON UPDATE RESTRICT | Sala que solicita |
| fecha_confeccion | DATE | No | DEFAULT CURRENT_DATE, la fuerza trg_transferencia_fecha | Fecha de confección |
| estado | estado_documento | No | ENUM, DEFAULT 'en_confeccion' | Estado del documento |

## renglon_transferencia

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| nro_transferencia | INTEGER | No | PK (1), FK transferencia, ON DELETE CASCADE, ON UPDATE RESTRICT | Transferencia |
| cod_vino | INTEGER | No | PK (2), FK vino, ON DELETE RESTRICT, ON UPDATE RESTRICT | Vino solicitado |
| cantidad | INTEGER | No | CHECK chk_renglon_transferencia_cantidad (> 0) | Botellas solicitadas |

## auditoria_precio

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| id_auditoria | INTEGER | No | PK, identity | Identificador del registro |
| cod_vino | INTEGER | No | FK vino, ON DELETE RESTRICT, ON UPDATE RESTRICT | Vino al que se le cambió el precio |
| precio_anterior | NUMERIC(10,2) | No | CHECK chk_auditoria_precios (> 0 y distinto del nuevo) | Precio antes del cambio |
| precio_nuevo | NUMERIC(10,2) | No | CHECK chk_auditoria_precios (> 0) | Precio después del cambio |
| fecha_hora | TIMESTAMP | No | DEFAULT LOCALTIMESTAMP | Momento del cambio |
| usuario | VARCHAR(63) | No | DEFAULT CURRENT_USER | Usuario de la base que hizo el cambio |
