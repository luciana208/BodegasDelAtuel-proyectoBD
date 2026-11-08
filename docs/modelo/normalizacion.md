# Normalización

## Dependencias funcionales relevantes

Escribimos las dependencias que salen del escenario. Del lado izquierdo siempre queda la clave de la tabla donde terminó cada atributo.

| Tabla | Dependencia funcional |
|---|---|
| departamento | id_departamento -> nombre, provincia |
| localidad | id_localidad -> nombre, cod_postal, id_departamento, encargado_regional |
| sala_venta | id_sala -> calle, numero, dia_cierre, id_localidad |
| empleado | cuit -> nombre, fecha_ingreso, salario, id_sala |
| cepa | id_cepa -> nombre, tipo |
| finca | id_finca -> nombre, superficie_ha, id_departamento |
| parcela | (id_finca, nro_parcela) -> superficie_ha, anio_plantacion, id_cepa |
| bodega | cuit -> razon_social, domicilio |
| lote_uva | nro_lote -> id_finca, nro_parcela, campania, fecha_cosecha, kilos, cuit_bodega |
| lote_uva | (id_finca, nro_parcela, campania) -> nro_lote (clave candidata) |
| analisis_calidad | id_analisis -> nro_lote, fecha, brix, ph, acidez_total |
| vino | cod_vino -> nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega |
| vino | (nombre, anada, volumen_ml) -> cod_vino (clave candidata) |
| composicion | (cod_vino, id_cepa) -> porcentaje |
| maridaje | id_maridaje -> nombre, temperatura_servicio |
| cliente | id_cliente -> nombre, tipo_documento, nro_documento, direccion, id_localidad, fecha_alta, tipo, descuento |
| socio | id_cliente -> nro_carnet |
| distribuidor | id_cliente -> zona_cobertura, nro_habilitacion |
| exportador | id_cliente -> pais_destino |
| permiso_exportacion | cod_permiso -> id_cliente, fecha_emision, fecha_vencimiento |
| comprobante | nro_comprobante -> fecha, id_cliente, id_sala, subtotal, descuento, total |
| renglon_comprobante | (nro_comprobante, cod_vino) -> cantidad, precio_unitario, porc_descuento, subtotal |
| stock_sala | (id_sala, cod_vino) -> cantidad |
| stock_deposito | cod_vino -> cantidad |
| transportista | cod_transporte -> razon_social, cuit, email, telefono, domicilio |
| ingreso | cod_ingreso -> fecha, estado, cod_transporte, cuit_bodega |
| renglon_ingreso | (cod_ingreso, cod_vino) -> cantidad |
| transferencia | nro_transferencia -> id_sala, fecha_confeccion, estado |
| renglon_transferencia | (nro_transferencia, cod_vino) -> cantidad |
| auditoria_precio | id_auditoria -> cod_vino, precio_anterior, precio_nuevo, fecha_hora, usuario |

Dependencias que obligaron a separar tablas:

- `localidad -> encargado_regional`. Si el encargado se guardaba en la sala, en una localidad con varias salas se repetiría y podría quedar distinto en cada una. Como depende solo de la localidad, va en `localidad` y la sala solo guarda `id_localidad`.
- `localidad -> departamento -> provincia`. La provincia depende del departamento, no de la localidad en forma directa. Si guardábamos la provincia en `localidad` y en `finca` aparecía una dependencia transitiva. Por eso hay una tabla `departamento` y la provincia de una localidad o una finca se obtiene por su departamento.
- `sala -> localidad` y `cliente -> localidad`: se guardan como FK y no se copian nombre ni código postal.
- `vino -> bodega`: el vino guarda solo el CUIT de la bodega, la razón social queda en `bodega`.
- `cod_permiso -> fechas`: como un exportador tiene varios permisos, no se pueden poner en `exportador` sin repetir filas, entonces van en su propia tabla.

## Primera forma normal

Todos los atributos son atómicos. Los atributos multivaluados del escenario (las cepas de un vino, sus maridajes, los permisos de un exportador, las localidades de un transportista, los vinos de un comprobante, ingreso o transferencia) se pasaron a tablas aparte con una fila por valor. La dirección de la sala se separó en calle y número porque así la pide el escenario.

## Segunda forma normal

Las tablas con clave compuesta son `parcela`, `composicion`, `vino_maridaje`, `renglon_comprobante`, `stock_sala`, `transportista_localidad`, `renglon_ingreso` y `renglon_transferencia`. En todas, los atributos que no son clave dependen de la clave completa:

- En `parcela`, la superficie, el año de plantación y la cepa dependen de la finca y del número juntos (el número 3 se repite en muchas fincas).
- En `composicion`, el porcentaje depende del vino y de la cepa.
- En `renglon_comprobante`, la cantidad, el precio unitario, el descuento y el subtotal son de ese vino en ese comprobante. El precio unitario no depende solo del vino porque es el precio al momento de la venta, y el porcentaje de descuento no depende solo del comprobante porque se guarda por renglón como pide el escenario.
- En `stock_sala` y en los renglones de ingreso y transferencia, la cantidad depende del par completo.

No quedan dependencias parciales.

## Tercera forma normal

En cada tabla los atributos no clave dependen solo de la clave y no de otro atributo no clave. Los casos que revisamos:

- `localidad`: `encargado_regional` depende de la localidad. El código postal no determina la localidad (en Mendoza hay localidades que comparten código postal), así que no hay dependencia transitiva por ese lado.
- `sala_venta`: no guarda datos de la localidad, solo la FK.
- `empleado`: no guarda datos de la sala.
- `vino`: no guarda datos de la bodega.
- `lote_uva`: no guarda la cepa ni la superficie de la parcela, se llega a ellas por la FK compuesta.
- `cliente`: el descuento se guarda en el cliente. Arranca con el valor que corresponde a su tipo, pero puede cambiar para un cliente puntual (por ejemplo un exportador con muchos permisos al que se le sube al 35 %), así que no es una dependencia `tipo -> descuento` sino un dato propio del cliente.

### Atributos derivados guardados a propósito

`comprobante.subtotal`, `comprobante.descuento`, `comprobante.total` y `renglon_comprobante.subtotal` se pueden calcular a partir de otros datos. Estrictamente, `(cantidad, precio_unitario, porc_descuento) -> subtotal` es una dependencia entre atributos no clave, así que estas columnas son una desnormalización hecha a propósito. Se guardan porque el escenario los pide en el comprobante y porque así no hay que recalcularlos en cada consulta de ventas. Para que no se vuelvan inconsistentes nunca se cargan a mano: los mantienen triggers y funciones de la base (etapa 2), y hay consultas de control que verifican que coincidan con los renglones.

Fuera de esos atributos derivados, que están controlados, el esquema queda en 3FN.
