# Diccionario de datos

Para cada tabla se indica el tipo de cada columna, si admite nulos, las restricciones y una descripción. Los tipos son los mismos que en `db/migrations/001_esquema.sql`.

## departamento

Departamentos de cada provincia. Se usa para ubicar localidades y fincas.

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| id_departamento | SMALLINT | No | PK, identity | Identificador del departamento |
| nombre | VARCHAR(40) | No | | Nombre del departamento |
| provincia | VARCHAR(40) | No | | Provincia a la que pertenece |

## localidad

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| id_localidad | INTEGER | No | PK, identity | Identificador de la localidad |
| nombre | VARCHAR(60) | No | | Nombre de la localidad |
| cod_postal | cod_postal_dom | No | 4 dígitos (dominio) | Código postal |
| id_departamento | SMALLINT | No | FK departamento, ON DELETE RESTRICT, ON UPDATE RESTRICT | Departamento donde está la localidad |
| encargado_regional | VARCHAR(80) | No | | Responsable comercial de la localidad, el mismo para todas sus salas |

## sala_venta

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| id_sala | INTEGER | No | PK, identity | Identificador de la sala |
| calle | VARCHAR(80) | No | | Calle de la dirección |
| numero | INTEGER | No | | Número de la dirección |
| dia_cierre | dia_semana | No | ENUM | Día de cierre semanal |
| id_localidad | INTEGER | No | FK localidad, ON DELETE RESTRICT, ON UPDATE RESTRICT | Localidad donde está la sala |

## empleado

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| cuit | cuit_dom | No | PK, 11 dígitos (dominio) | CUIT del empleado |
| nombre | VARCHAR(80) | No | | Apellido y nombre |
| fecha_ingreso | DATE | No | | Fecha de ingreso laboral |
| salario | NUMERIC(12,2) | No | | Salario mensual |
| id_sala | INTEGER | No | FK sala_venta, ON DELETE RESTRICT, ON UPDATE RESTRICT | Sala donde trabaja |

## cepa

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| id_cepa | SMALLINT | No | PK, identity | Identificador de la cepa |
| nombre | VARCHAR(40) | No | | Nombre de la cepa |
| tipo | tipo_cepa | No | ENUM | Tinta o blanca |

## finca

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| id_finca | INTEGER | No | PK, identity | Identificador de la finca |
| nombre | VARCHAR(80) | No | | Nombre de la finca |
| superficie_ha | NUMERIC(8,2) | No | | Superficie total en hectáreas |
| id_departamento | SMALLINT | No | FK departamento, ON DELETE RESTRICT, ON UPDATE RESTRICT | Departamento donde está la finca |

## parcela

Entidad débil: no existe sin su finca.

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| id_finca | INTEGER | No | PK (1), FK finca, ON DELETE CASCADE, ON UPDATE RESTRICT | Finca a la que pertenece |
| nro_parcela | SMALLINT | No | PK (2) | Número de parcela dentro de la finca |
| superficie_ha | NUMERIC(7,2) | No | | Superficie en hectáreas |
| anio_plantacion | SMALLINT | No | | Año en que se plantó |
| id_cepa | SMALLINT | No | FK cepa, ON DELETE RESTRICT, ON UPDATE RESTRICT | Cepa plantada (una sola) |

## bodega

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| cuit | cuit_dom | No | PK, 11 dígitos (dominio) | CUIT de la bodega |
| razon_social | VARCHAR(100) | No | | Razón social |
| domicilio | VARCHAR(120) | No | | Domicilio |

## lote_uva

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| nro_lote | INTEGER | No | PK, identity | Número de lote |
| id_finca | INTEGER | No | FK (1) parcela, ON DELETE RESTRICT, ON UPDATE CASCADE | Finca de la parcela cosechada |
| nro_parcela | SMALLINT | No | FK (2) parcela | Parcela cosechada |
| campania | SMALLINT | No | | Año de cosecha |
| fecha_cosecha | DATE | No | | Fecha de la cosecha |
| kilos | NUMERIC(10,2) | No | | Kilos cosechados |
| cuit_bodega | cuit_dom | No | FK bodega, ON DELETE RESTRICT, ON UPDATE CASCADE | Bodega a la que se entregó |

## analisis_calidad

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| id_analisis | INTEGER | No | PK, identity | Identificador del análisis |
| nro_lote | INTEGER | No | FK lote_uva, ON DELETE CASCADE, ON UPDATE RESTRICT | Lote analizado |
| fecha | DATE | No | | Fecha del análisis |
| brix | NUMERIC(4,1) | No | | Grado Brix |
| ph | NUMERIC(3,2) | No | | pH |
| acidez_total | NUMERIC(4,2) | No | | Acidez total en g/L |

## vino

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| cod_vino | INTEGER | No | PK, identity | Código del vino |
| nombre | VARCHAR(80) | No | | Nombre comercial |
| tipo | tipo_vino | No | ENUM | Tinto, blanco, rosado o espumante |
| anada | SMALLINT | No | | Año de la cosecha de la uva |
| volumen_ml | INTEGER | No | | Presentación en ml |
| graduacion | NUMERIC(4,2) | No | | Graduación alcohólica |
| precio | NUMERIC(10,2) | No | | Precio de venta, igual en todas las salas |
| cuit_bodega | cuit_dom | No | FK bodega, ON DELETE RESTRICT, ON UPDATE CASCADE | Bodega que lo elabora |

## composicion

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| cod_vino | INTEGER | No | PK (1), FK vino, ON DELETE CASCADE, ON UPDATE RESTRICT | Vino |
| id_cepa | SMALLINT | No | PK (2), FK cepa, ON DELETE RESTRICT, ON UPDATE RESTRICT | Cepa que forma parte del corte |
| porcentaje | NUMERIC(5,2) | No | | Porcentaje de la cepa en el corte |

## maridaje

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| id_maridaje | SMALLINT | No | PK, identity | Identificador del maridaje |
| nombre | VARCHAR(60) | No | | Nombre (por ejemplo carnes rojas) |
| temperatura_servicio | NUMERIC(4,1) | No | | Temperatura de servicio sugerida en °C |

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
| tipo_documento | VARCHAR(4) | No | | Tipo de documento |
| nro_documento | VARCHAR(13) | No | | Número de documento |
| direccion | VARCHAR(120) | No | | Dirección |
| id_localidad | INTEGER | No | FK localidad, ON DELETE RESTRICT, ON UPDATE RESTRICT | Localidad del cliente |
| fecha_alta | DATE | No | | Fecha de alta |
| tipo | tipo_cliente | No | ENUM, UNIQUE (id_cliente, tipo) | Subtipo del cliente |
| descuento | NUMERIC(5,2) | No | | Porcentaje de descuento que se le aplica |

## socio

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| id_cliente | INTEGER | No | PK, FK (1) cliente, ON DELETE CASCADE, ON UPDATE RESTRICT | Cliente |
| tipo | tipo_cliente | No | FK (2) cliente, DEFAULT 'socio', CHECK tipo = 'socio' | Tipo fijo del subtipo |
| nro_carnet | INTEGER | No | | Número de carnet del club |

## distribuidor

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| id_cliente | INTEGER | No | PK, FK (1) cliente, ON DELETE CASCADE, ON UPDATE RESTRICT | Cliente |
| tipo | tipo_cliente | No | FK (2) cliente, DEFAULT 'distribuidor', CHECK tipo = 'distribuidor' | Tipo fijo del subtipo |
| zona_cobertura | VARCHAR(80) | No | | Zona que cubre |
| nro_habilitacion | VARCHAR(20) | No | | Número de habilitación |

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
| fecha_vencimiento | DATE | No | | Fecha de vencimiento |

## comprobante

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| nro_comprobante | INTEGER | No | PK, identity | Número de comprobante |
| fecha | DATE | No | | Fecha de la venta |
| id_cliente | INTEGER | No | FK cliente, ON DELETE RESTRICT, ON UPDATE RESTRICT | Cliente que compra |
| id_sala | INTEGER | No | FK sala_venta, ON DELETE RESTRICT, ON UPDATE RESTRICT | Sala donde se vendió |
| subtotal | NUMERIC(12,2) | No | | Suma de cantidad por precio de los renglones, sin descuento |
| descuento | NUMERIC(12,2) | No | | Importe descontado |
| total | NUMERIC(12,2) | No | | Suma de los subtotales de los renglones |

## renglon_comprobante

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| nro_comprobante | INTEGER | No | PK (1), FK comprobante, ON DELETE CASCADE, ON UPDATE RESTRICT | Comprobante |
| cod_vino | INTEGER | No | PK (2), FK vino, ON DELETE RESTRICT, ON UPDATE RESTRICT | Vino vendido |
| cantidad | INTEGER | No | | Botellas vendidas |
| precio_unitario | NUMERIC(10,2) | No | | Precio del vino al momento de la venta |
| porc_descuento | NUMERIC(5,2) | No | | Porcentaje de descuento aplicado según el tipo de cliente |
| subtotal | NUMERIC(12,2) | No | | Cantidad por precio con el descuento aplicado |

## stock_sala

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| id_sala | INTEGER | No | PK (1), FK sala_venta, ON DELETE RESTRICT, ON UPDATE RESTRICT | Sala |
| cod_vino | INTEGER | No | PK (2), FK vino, ON DELETE RESTRICT, ON UPDATE RESTRICT | Vino |
| cantidad | INTEGER | No | | Botellas disponibles en la sala |

## stock_deposito

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| cod_vino | INTEGER | No | PK, FK vino, ON DELETE RESTRICT, ON UPDATE RESTRICT | Vino |
| cantidad | INTEGER | No | | Botellas disponibles en el depósito central |

## transportista

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| cod_transporte | INTEGER | No | PK, identity | Código del transportista |
| razon_social | VARCHAR(100) | No | | Razón social |
| cuit | cuit_dom | No | 11 dígitos (dominio) | CUIT |
| email | VARCHAR(100) | No | | Correo electrónico |
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
| fecha | DATE | No | | Fecha del ingreso |
| estado | estado_documento | No | ENUM | Estado del documento |
| cod_transporte | INTEGER | No | FK transportista, ON DELETE RESTRICT, ON UPDATE RESTRICT | Transportista que hizo el traslado |
| cuit_bodega | cuit_dom | No | FK bodega, ON DELETE RESTRICT, ON UPDATE CASCADE | Bodega de origen |

## renglon_ingreso

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| cod_ingreso | INTEGER | No | PK (1), FK ingreso, ON DELETE CASCADE, ON UPDATE RESTRICT | Ingreso |
| cod_vino | INTEGER | No | PK (2), FK vino, ON DELETE RESTRICT, ON UPDATE RESTRICT | Vino ingresado |
| cantidad | INTEGER | No | | Botellas ingresadas |

## transferencia

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| nro_transferencia | INTEGER | No | PK, identity | Número de solicitud |
| id_sala | INTEGER | No | FK sala_venta, ON DELETE RESTRICT, ON UPDATE RESTRICT | Sala que solicita |
| fecha_confeccion | DATE | No | | Fecha de confección |
| estado | estado_documento | No | ENUM | Estado del documento |

## renglon_transferencia

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| nro_transferencia | INTEGER | No | PK (1), FK transferencia, ON DELETE CASCADE, ON UPDATE RESTRICT | Transferencia |
| cod_vino | INTEGER | No | PK (2), FK vino, ON DELETE RESTRICT, ON UPDATE RESTRICT | Vino solicitado |
| cantidad | INTEGER | No | | Botellas solicitadas |

## auditoria_precio

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| id_auditoria | INTEGER | No | PK, identity | Identificador del registro |
| cod_vino | INTEGER | No | FK vino, ON DELETE RESTRICT, ON UPDATE RESTRICT | Vino al que se le cambió el precio |
| precio_anterior | NUMERIC(10,2) | No | | Precio antes del cambio |
| precio_nuevo | NUMERIC(10,2) | No | | Precio después del cambio |
| fecha_hora | TIMESTAMP | No | | Momento del cambio |
| usuario | VARCHAR(63) | No | | Usuario de la base que hizo el cambio |
