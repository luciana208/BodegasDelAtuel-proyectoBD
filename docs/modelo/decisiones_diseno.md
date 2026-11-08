# Decisiones de diseño

## Jerarquía de clientes

Opciones que comparamos:

| Opción | Ventajas | Desventajas |
|---|---|---|
| Tabla única con columna de tipo | Una sola tabla, consultas simples, sin joins | Columnas que quedan nulas según el tipo (zona y habilitación en socios, país en distribuidores). No se puede poner NOT NULL en los datos propios de cada subtipo |
| Una tabla por subtipo, sin supertipo | Cada tabla tiene solo sus columnas | Los datos comunes se repiten en tres tablas. Comprobante tendría que apuntar a tres tablas distintas, y una FK no puede hacer eso |
| Supertipo más una tabla por subtipo | Los datos comunes están una sola vez, comprobante apunta a una sola tabla, los datos propios pueden ser NOT NULL | Hace falta un join para ver los datos del subtipo y hay que cuidar que un cliente no quede en dos subtipos |

Elegimos **supertipo más subtipos**: `cliente` tiene los datos comunes y la columna `tipo`, y `socio`, `distribuidor` y `exportador` tienen sus datos propios con la misma clave `id_cliente`. Los permisos de exportación cuelgan de `exportador`, así solo un exportador puede tener permisos.

Para que la jerarquía sea exclusiva (un cliente no puede ser socio y distribuidor a la vez) cada subtipo repite la columna `tipo` con un CHECK que la fija (`tipo = 'socio'`, etc.) y la FK es compuesta: `(id_cliente, tipo) REFERENCES cliente (id_cliente, tipo)`. Para eso `cliente` tiene un UNIQUE sobre `(id_cliente, tipo)`. Si un cliente es de tipo `socio`, la única fila de subtipo que se puede crear es en `socio`.

Lo que no controla el esquema es que todo cliente tenga sí o sí su fila de subtipo (la jerarquía total). Eso lo resuelve la API dando de alta las dos filas en la misma transacción. El descuento se guarda en `cliente` porque es común a los tres tipos.

## Claves naturales o subrogadas

| Tabla | Clave | Por qué |
|---|---|---|
| bodega | CUIT (natural) | El CUIT identifica a la empresa, no cambia y lo piden en el escenario. Las FK a bodega llevan ON UPDATE CASCADE por si hubiera que corregir un CUIT mal cargado |
| empleado | CUIT (natural) | Mismo criterio. Ninguna tabla apunta a empleado |
| localidad | id_localidad (subrogada) | El código postal no sirve como clave: en Mendoza varias localidades comparten código postal. Se guarda como atributo |
| departamento | id_departamento (subrogada) | El nombre solo no alcanza (puede repetirse en otra provincia) y una clave numérica es más cómoda para las FK |
| transportista | cod_transporte (subrogada) | El escenario habla de un código de transporte. El CUIT queda como atributo único en la etapa 2 |
| cliente | id_cliente (subrogada) | Un cliente puede tener DNI o CUIT, y el número de documento podría corregirse. El escenario pide un ID |
| sala_venta, finca, cepa, maridaje, vino, lote_uva, analisis_calidad | identity (subrogada) | El escenario les da un ID o código. Para cepa y maridaje el nombre queda como UNIQUE |
| ingreso, transferencia, comprobante | identity (subrogada) | Son números de documento correlativos |
| parcela | (id_finca, nro_parcela) | Es entidad débil: el número solo se repite entre fincas |
| permiso_exportacion | cod_permiso (natural) | Es el código que emite el organismo, ya es único |
| renglones, composición, stock, coberturas | compuesta por las dos FK | Un vino aparece una sola vez por documento, por sala o por corte |

Las claves subrogadas usan `GENERATED ALWAYS AS IDENTITY`, que no deja cargar el valor a mano por error.

## Tipos de datos

- Importes (`precio`, `salario`, `subtotal`, `descuento`, `total`, `precio_unitario`) con `NUMERIC(p,2)`. Nunca FLOAT, porque FLOAT no representa exacto los decimales y en sumas de muchos renglones aparecen diferencias de centavos.
- Medidas con decimales (`superficie_ha`, `kilos`, `graduacion`, `brix`, `ph`, `acidez_total`, `porcentaje`, `temperatura_servicio`) también con NUMERIC y la escala justa para cada una.
- Fechas con `DATE`. La auditoría de precio usa `TIMESTAMP` porque interesa la hora exacta del cambio.
- Estados con el ENUM `estado_documento`. También son ENUM el tipo de cliente, de cepa, de vino y el día de cierre, para que no se pueda cargar texto libre.
- CUIT con el dominio `cuit_dom` (11 dígitos) y código postal con `cod_postal_dom` (4 dígitos), así la validación se escribe una sola vez.
- Años (`anada`, `campania`, `anio_plantacion`) y números chicos con SMALLINT. Cantidades de botellas con INTEGER.

## Atributos derivados

| Atributo | Se guarda | Cómo se mantiene |
|---|---|---|
| renglon_comprobante.precio_unitario | Sí | Es el precio del vino al momento de la venta. Si después cambia el precio, el renglón viejo no tiene que cambiar, por eso no alcanza con leerlo de `vino` |
| renglon_comprobante.porc_descuento | Sí | Lo completa un trigger con el descuento del cliente (etapa 2) |
| renglon_comprobante.subtotal | Sí | Lo calcula un trigger: cantidad por precio unitario menos el descuento |
| comprobante.subtotal, descuento, total | Sí | Los recalcula un trigger cada vez que se agrega, cambia o borra un renglón. Nunca se cargan a mano |
| stock_sala.cantidad, stock_deposito.cantidad | Sí | Se podrían sacar sumando todos los movimientos, pero sería muy caro. Los actualizan los triggers de venta y los procedimientos de ingreso y transferencia |
| Stock total de un vino | No | Se calcula con una función y una vista (depósito más salas) |
| Antigüedad de un empleado, rendimiento por hectárea | No | Se calculan en las consultas porque dependen de la fecha actual |

## Acciones referenciales

Criterio general:

- **ON DELETE RESTRICT** en todo lo que es un movimiento o un dato maestro con historia: no se puede borrar un vino, una bodega o un transportista que aparezcan en ingresos, ventas, transferencias o lotes (RN-14). Tampoco una sala con empleados, ventas o stock, ni un cliente con comprobantes.
- **ON DELETE CASCADE** solo en lo que no existe sin su cabecera: renglones de comprobante, de ingreso y de transferencia, parcelas de una finca, análisis de un lote, composición y maridajes de un vino, subtipos de un cliente, permisos de un exportador y coberturas de un transportista.
- **ON UPDATE CASCADE** en las FK que apuntan a claves naturales que podrían corregirse (CUIT de bodega, parcela).
- **ON UPDATE RESTRICT** en las FK que apuntan a claves identity, porque esas claves no cambian.

| FK | ON DELETE | ON UPDATE | Motivo |
|---|---|---|---|
| localidad.id_departamento, finca.id_departamento | RESTRICT | RESTRICT | Catálogo con datos que dependen de él |
| sala_venta.id_localidad, cliente.id_localidad, transportista_localidad.id_localidad | RESTRICT | RESTRICT | No se borra una localidad en uso |
| empleado.id_sala | RESTRICT | RESTRICT | Hay que reasignar o dar de baja los empleados antes |
| parcela.id_finca | CASCADE | RESTRICT | Entidad débil, no existe sin la finca. Si la parcela tiene lotes, el RESTRICT de lote_uva frena el borrado |
| parcela.id_cepa, composicion.id_cepa | RESTRICT | RESTRICT | No se borra una cepa plantada o usada en un corte |
| lote_uva (id_finca, nro_parcela) | RESTRICT | CASCADE | Historia de cosechas |
| lote_uva.cuit_bodega, vino.cuit_bodega, ingreso.cuit_bodega | RESTRICT | CASCADE | RN-14, y el CUIT podría corregirse |
| analisis_calidad.nro_lote | CASCADE | RESTRICT | El análisis no existe sin su lote |
| composicion.cod_vino, vino_maridaje.cod_vino | CASCADE | RESTRICT | Son parte de la definición del vino |
| vino_maridaje.id_maridaje | CASCADE | RESTRICT | Si se quita un maridaje del catálogo, se quita la recomendación |
| socio, distribuidor, exportador (id_cliente, tipo) | CASCADE | RESTRICT | El subtipo no existe sin el cliente. El RESTRICT en update impide cambiar el tipo de un cliente que ya tiene subtipo |
| permiso_exportacion.id_cliente | CASCADE | RESTRICT | El permiso no existe sin el exportador |
| comprobante.id_cliente, comprobante.id_sala | RESTRICT | RESTRICT | Historia de ventas |
| renglon_comprobante.nro_comprobante, renglon_ingreso.cod_ingreso, renglon_transferencia.nro_transferencia | CASCADE | RESTRICT | Renglones que no existen sin su cabecera |
| renglones.cod_vino | RESTRICT | RESTRICT | RN-14 |
| stock_sala.id_sala, stock_sala.cod_vino, stock_deposito.cod_vino | RESTRICT | RESTRICT | No se borra un vino ni una sala con stock registrado |
| transportista_localidad.cod_transporte | CASCADE | RESTRICT | La cobertura no existe sin el transportista |
| ingreso.cod_transporte | RESTRICT | RESTRICT | RN-14 |
| transferencia.id_sala | RESTRICT | RESTRICT | Historia de movimientos |
| auditoria_precio.cod_vino | RESTRICT | RESTRICT | La auditoría no se pierde: un vino con cambios de precio registrados no se borra |

## Guía para el DER

Lo que tiene que aparecer en el diagrama, sacado del esquema:

- Entidad débil `Parcela`, con relación identificadora con `Finca` y discriminante `nro_parcela`.
- Jerarquía `Cliente` con los subtipos `Socio`, `Distribuidor` y `Exportador`, exclusiva (disjunta) y total. `Exportador` se relaciona 1:N con `Permiso de exportación`.
- Relaciones N:M con atributos: `Composición` (vino-cepa, porcentaje), `Renglón de comprobante` (comprobante-vino, cantidad, precio unitario, descuento, subtotal), `Stock de sala` (sala-vino, cantidad), `Renglón de ingreso` y `Renglón de transferencia` (cantidad).
- Relaciones N:M sin atributos: `Vino-Maridaje` y `Transportista cubre Localidad`.
- `Lote de uva` relacionado con `Parcela` (1:N con la restricción de una vez por campaña) y con `Bodega` destino.
- Las cardinalidades mínimas y máximas están en la tabla del final de `esquema_relacional.md`.
