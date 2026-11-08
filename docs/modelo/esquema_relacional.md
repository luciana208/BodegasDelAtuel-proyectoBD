# Esquema relacional

Notación: la clave primaria va subrayada con `_guiones_`, las claves foráneas se marcan con `FK -> tabla`. Las tablas están agrupadas por tema y en el mismo orden que en `db/migrations/001_esquema.sql`.

## Tipos propios

- `estado_documento`: ENUM (`en_confeccion`, `terminado`, `procesado`).
- `tipo_cliente`: ENUM (`socio`, `distribuidor`, `exportador`).
- `tipo_cepa`: ENUM (`tinta`, `blanca`).
- `tipo_vino`: ENUM (`tinto`, `blanco`, `rosado`, `espumante`).
- `dia_semana`: ENUM (`lunes` a `domingo`).
- `cuit_dom`: DOMAIN sobre CHAR(11), solo 11 dígitos.
- `cod_postal_dom`: DOMAIN sobre VARCHAR(4), solo 4 dígitos.

## Localidades, salas y empleados

- DEPARTAMENTO (_id_departamento_, nombre, provincia)
- LOCALIDAD (_id_localidad_, nombre, cod_postal, id_departamento FK -> DEPARTAMENTO, encargado_regional)
- SALA_VENTA (_id_sala_, calle, numero, dia_cierre, id_localidad FK -> LOCALIDAD)
- EMPLEADO (_cuit_, nombre, fecha_ingreso, salario, id_sala FK -> SALA_VENTA)

## Producción de uva

- CEPA (_id_cepa_, nombre, tipo)
- FINCA (_id_finca_, nombre, superficie_ha, id_departamento FK -> DEPARTAMENTO)
- PARCELA (_id_finca, nro_parcela_, superficie_ha, anio_plantacion, id_cepa FK -> CEPA)
  - id_finca FK -> FINCA. Es la entidad débil: su clave incluye la clave de la finca.
- BODEGA (_cuit_, razon_social, domicilio)
- LOTE_UVA (_nro_lote_, id_finca, nro_parcela, campania, fecha_cosecha, kilos, cuit_bodega FK -> BODEGA)
  - (id_finca, nro_parcela) FK -> PARCELA
- ANALISIS_CALIDAD (_id_analisis_, nro_lote FK -> LOTE_UVA, fecha, brix, ph, acidez_total)

## Vinos

- VINO (_cod_vino_, nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega FK -> BODEGA)
- COMPOSICION (_cod_vino, id_cepa_, porcentaje)
  - cod_vino FK -> VINO, id_cepa FK -> CEPA. Es la N:M vino-cepa con atributo.
- MARIDAJE (_id_maridaje_, nombre, temperatura_servicio)
- VINO_MARIDAJE (_cod_vino, id_maridaje_)
  - cod_vino FK -> VINO, id_maridaje FK -> MARIDAJE. N:M sin atributos.

## Clientes

- CLIENTE (_id_cliente_, nombre, tipo_documento, nro_documento, direccion, id_localidad FK -> LOCALIDAD, fecha_alta, tipo, descuento)
  - UNIQUE (id_cliente, tipo), la usan los subtipos en su FK.
- SOCIO (_id_cliente_, tipo, nro_carnet)
  - (id_cliente, tipo) FK -> CLIENTE, con tipo fijo en `socio`.
- DISTRIBUIDOR (_id_cliente_, tipo, zona_cobertura, nro_habilitacion)
  - (id_cliente, tipo) FK -> CLIENTE, con tipo fijo en `distribuidor`.
- EXPORTADOR (_id_cliente_, tipo, pais_destino)
  - (id_cliente, tipo) FK -> CLIENTE, con tipo fijo en `exportador`.
- PERMISO_EXPORTACION (_cod_permiso_, id_cliente FK -> EXPORTADOR, fecha_emision, fecha_vencimiento)

## Ventas y stock

- COMPROBANTE (_nro_comprobante_, fecha, id_cliente FK -> CLIENTE, id_sala FK -> SALA_VENTA, subtotal, descuento, total)
- RENGLON_COMPROBANTE (_nro_comprobante, cod_vino_, cantidad, precio_unitario, porc_descuento, subtotal)
  - nro_comprobante FK -> COMPROBANTE, cod_vino FK -> VINO. N:M comprobante-vino con atributos.
- STOCK_SALA (_id_sala, cod_vino_, cantidad)
  - id_sala FK -> SALA_VENTA, cod_vino FK -> VINO.
- STOCK_DEPOSITO (_cod_vino_, cantidad)
  - cod_vino FK -> VINO. Hay un solo depósito central, por eso la clave es solo el vino.

## Logística

- TRANSPORTISTA (_cod_transporte_, razon_social, cuit, email, telefono, domicilio)
- TRANSPORTISTA_LOCALIDAD (_cod_transporte, id_localidad_)
  - cod_transporte FK -> TRANSPORTISTA, id_localidad FK -> LOCALIDAD.
- INGRESO (_cod_ingreso_, fecha, estado, cod_transporte FK -> TRANSPORTISTA, cuit_bodega FK -> BODEGA)
- RENGLON_INGRESO (_cod_ingreso, cod_vino_, cantidad)
  - cod_ingreso FK -> INGRESO, cod_vino FK -> VINO.
- TRANSFERENCIA (_nro_transferencia_, id_sala FK -> SALA_VENTA, fecha_confeccion, estado)
- RENGLON_TRANSFERENCIA (_nro_transferencia, cod_vino_, cantidad)
  - nro_transferencia FK -> TRANSFERENCIA, cod_vino FK -> VINO.

## Auditoría

- AUDITORIA_PRECIO (_id_auditoria_, cod_vino FK -> VINO, precio_anterior, precio_nuevo, fecha_hora, usuario)

## Cardinalidades principales

| Relación | Cardinalidad | Cómo queda en el esquema |
|---|---|---|
| Departamento - Localidad | 1:N | FK en localidad |
| Localidad - Sala de venta | 1:N (una sala en una sola localidad) | FK NOT NULL en sala_venta |
| Sala - Empleado | 1:N (cada empleado en una sola sala) | FK NOT NULL en empleado |
| Departamento - Finca | 1:N | FK en finca |
| Finca - Parcela | 1:N, identificadora | FK que forma parte de la PK de parcela |
| Cepa - Parcela | 1:N (una cepa por parcela) | FK NOT NULL en parcela |
| Parcela - Lote de uva | 1:N, a lo sumo uno por campaña | FK en lote_uva, UNIQUE (parcela, campaña) en la etapa 2 |
| Bodega - Lote de uva | 1:N | FK en lote_uva |
| Lote - Análisis de calidad | 1:N (uno o más) | FK en analisis_calidad |
| Bodega - Vino | 1:N | FK NOT NULL en vino |
| Vino - Cepa | N:M con porcentaje | tabla composicion |
| Vino - Maridaje | N:M | tabla vino_maridaje |
| Cliente - Socio / Distribuidor / Exportador | jerarquía exclusiva | una tabla por subtipo con FK (id_cliente, tipo) |
| Exportador - Permiso | 1:N | FK en permiso_exportacion |
| Cliente - Comprobante | 1:N | FK en comprobante |
| Sala - Comprobante | 1:N | FK en comprobante |
| Comprobante - Vino | N:M con cantidad, precio, descuento y subtotal | tabla renglon_comprobante |
| Sala - Vino (stock) | N:M con cantidad | tabla stock_sala |
| Vino - Depósito | 1:1 | tabla stock_deposito con PK cod_vino |
| Transportista - Localidad | N:M | tabla transportista_localidad |
| Transportista - Ingreso, Bodega - Ingreso | 1:N | FK en ingreso |
| Ingreso - Vino | N:M con cantidad | tabla renglon_ingreso |
| Sala - Transferencia | 1:N | FK en transferencia |
| Transferencia - Vino | N:M con cantidad | tabla renglon_transferencia |
| Vino - Auditoría de precio | 1:N | FK en auditoria_precio |
