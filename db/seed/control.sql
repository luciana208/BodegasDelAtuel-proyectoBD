-- consultas de control despues de la carga masiva

\pset pager off

-- conteo de filas por tabla
SELECT 'departamento' AS tabla, count(*) AS filas FROM departamento
UNION ALL SELECT 'localidad', count(*) FROM localidad
UNION ALL SELECT 'sala_venta', count(*) FROM sala_venta
UNION ALL SELECT 'empleado', count(*) FROM empleado
UNION ALL SELECT 'cepa', count(*) FROM cepa
UNION ALL SELECT 'finca', count(*) FROM finca
UNION ALL SELECT 'parcela', count(*) FROM parcela
UNION ALL SELECT 'bodega', count(*) FROM bodega
UNION ALL SELECT 'lote_uva', count(*) FROM lote_uva
UNION ALL SELECT 'analisis_calidad', count(*) FROM analisis_calidad
UNION ALL SELECT 'vino', count(*) FROM vino
UNION ALL SELECT 'composicion', count(*) FROM composicion
UNION ALL SELECT 'maridaje', count(*) FROM maridaje
UNION ALL SELECT 'vino_maridaje', count(*) FROM vino_maridaje
UNION ALL SELECT 'cliente', count(*) FROM cliente
UNION ALL SELECT 'socio', count(*) FROM socio
UNION ALL SELECT 'distribuidor', count(*) FROM distribuidor
UNION ALL SELECT 'exportador', count(*) FROM exportador
UNION ALL SELECT 'permiso_exportacion', count(*) FROM permiso_exportacion
UNION ALL SELECT 'comprobante', count(*) FROM comprobante
UNION ALL SELECT 'renglon_comprobante', count(*) FROM renglon_comprobante
UNION ALL SELECT 'stock_sala', count(*) FROM stock_sala
UNION ALL SELECT 'stock_deposito', count(*) FROM stock_deposito
UNION ALL SELECT 'transportista', count(*) FROM transportista
UNION ALL SELECT 'transportista_localidad', count(*) FROM transportista_localidad
UNION ALL SELECT 'ingreso', count(*) FROM ingreso
UNION ALL SELECT 'renglon_ingreso', count(*) FROM renglon_ingreso
UNION ALL SELECT 'transferencia', count(*) FROM transferencia
UNION ALL SELECT 'renglon_transferencia', count(*) FROM renglon_transferencia
UNION ALL SELECT 'auditoria_precio', count(*) FROM auditoria_precio
ORDER BY filas DESC;

-- cada control cuenta las filas inconsistentes, todos tienen que dar 0
SELECT 'comprobantes sin renglones' AS control, count(*) AS inconsistencias
  FROM comprobante c
 WHERE NOT EXISTS (SELECT 1 FROM renglon_comprobante r WHERE r.nro_comprobante = c.nro_comprobante)
UNION ALL
SELECT 'ingresos sin renglones', count(*)
  FROM ingreso i
 WHERE NOT EXISTS (SELECT 1 FROM renglon_ingreso r WHERE r.cod_ingreso = i.cod_ingreso)
UNION ALL
SELECT 'transferencias sin renglones', count(*)
  FROM transferencia t
 WHERE NOT EXISTS (SELECT 1 FROM renglon_transferencia r WHERE r.nro_transferencia = t.nro_transferencia)
UNION ALL
SELECT 'clientes sin su fila de subtipo', count(*)
  FROM cliente c
 WHERE NOT EXISTS (SELECT 1 FROM socio s WHERE s.id_cliente = c.id_cliente)
   AND NOT EXISTS (SELECT 1 FROM distribuidor d WHERE d.id_cliente = c.id_cliente)
   AND NOT EXISTS (SELECT 1 FROM exportador e WHERE e.id_cliente = c.id_cliente)
UNION ALL
SELECT 'renglones huerfanos de comprobante', count(*)
  FROM renglon_comprobante r
  LEFT JOIN comprobante c ON c.nro_comprobante = r.nro_comprobante
 WHERE c.nro_comprobante IS NULL
UNION ALL
SELECT 'stock de sala negativo', count(*) FROM stock_sala WHERE cantidad < 0
UNION ALL
SELECT 'stock de deposito negativo', count(*) FROM stock_deposito WHERE cantidad < 0
UNION ALL
SELECT 'comprobantes cuyo total no es la suma de sus renglones', count(*)
  FROM comprobante c
  JOIN (SELECT nro_comprobante, SUM(subtotal) AS total, SUM(cantidad * precio_unitario) AS bruto
          FROM renglon_comprobante GROUP BY nro_comprobante) r ON r.nro_comprobante = c.nro_comprobante
 WHERE c.total <> r.total OR c.subtotal <> r.bruto OR c.descuento <> c.subtotal - c.total
UNION ALL
SELECT 'renglones con subtotal mal calculado', count(*)
  FROM renglon_comprobante
 WHERE subtotal <> fn_subtotal_renglon(cantidad, precio_unitario, porc_descuento)
UNION ALL
SELECT 'renglones con un descuento distinto al del cliente', count(*)
  FROM renglon_comprobante r
  JOIN comprobante c ON c.nro_comprobante = r.nro_comprobante
  JOIN cliente cl ON cl.id_cliente = c.id_cliente
 WHERE r.porc_descuento <> cl.descuento
UNION ALL
SELECT 'clientes con descuento distinto al de su tipo', count(*)
  FROM cliente WHERE descuento <> fn_descuento_tipo(tipo)
UNION ALL
SELECT 'renglones con un precio que el vino nunca tuvo', count(*)
  FROM renglon_comprobante r
  JOIN vino v ON v.cod_vino = r.cod_vino
 WHERE r.precio_unitario <> v.precio
   AND NOT EXISTS (SELECT 1 FROM auditoria_precio a WHERE a.cod_vino = r.cod_vino AND a.precio_anterior = r.precio_unitario)
UNION ALL
SELECT 'vinos cuyo corte no suma 100', count(*)
  FROM vino v
 WHERE (SELECT COALESCE(SUM(porcentaje), 0) FROM composicion c WHERE c.cod_vino = v.cod_vino) <> 100
UNION ALL
SELECT 'stock de sala distinto a lo transferido menos lo vendido', count(*)
  FROM stock_sala s
  LEFT JOIN (SELECT t.id_sala, r.cod_vino, SUM(r.cantidad) AS cantidad
               FROM renglon_transferencia r JOIN transferencia t ON t.nro_transferencia = r.nro_transferencia
              WHERE t.estado = 'procesado'
              GROUP BY t.id_sala, r.cod_vino) e ON e.id_sala = s.id_sala AND e.cod_vino = s.cod_vino
  LEFT JOIN (SELECT c.id_sala, r.cod_vino, SUM(r.cantidad) AS cantidad
               FROM renglon_comprobante r JOIN comprobante c ON c.nro_comprobante = r.nro_comprobante
              GROUP BY c.id_sala, r.cod_vino) v ON v.id_sala = s.id_sala AND v.cod_vino = s.cod_vino
 WHERE s.cantidad <> COALESCE(e.cantidad, 0) - COALESCE(v.cantidad, 0)
UNION ALL
SELECT 'stock de deposito distinto a lo ingresado menos lo transferido', count(*)
  FROM stock_deposito d
  LEFT JOIN (SELECT r.cod_vino, SUM(r.cantidad) AS cantidad
               FROM renglon_ingreso r JOIN ingreso i ON i.cod_ingreso = r.cod_ingreso
              WHERE i.estado = 'procesado'
              GROUP BY r.cod_vino) e ON e.cod_vino = d.cod_vino
  LEFT JOIN (SELECT r.cod_vino, SUM(r.cantidad) AS cantidad
               FROM renglon_transferencia r JOIN transferencia t ON t.nro_transferencia = r.nro_transferencia
              WHERE t.estado = 'procesado'
              GROUP BY r.cod_vino) t ON t.cod_vino = d.cod_vino
 WHERE d.cantidad <> COALESCE(e.cantidad, 0) - COALESCE(t.cantidad, 0)
UNION ALL
SELECT 'ventas anteriores al alta del cliente', count(*)
  FROM comprobante c JOIN cliente cl ON cl.id_cliente = c.id_cliente
 WHERE c.fecha < cl.fecha_alta
UNION ALL
SELECT 'ventas de un vino antes de que llegue a la sala', count(*)
  FROM renglon_comprobante r
  JOIN comprobante c ON c.nro_comprobante = r.nro_comprobante
  LEFT JOIN (SELECT t.id_sala, rt.cod_vino, min(t.fecha_confeccion) AS llegada
               FROM transferencia t JOIN renglon_transferencia rt ON rt.nro_transferencia = t.nro_transferencia
              WHERE t.estado = 'procesado'
              GROUP BY t.id_sala, rt.cod_vino) p ON p.id_sala = c.id_sala AND p.cod_vino = r.cod_vino
 WHERE p.llegada IS NULL OR c.fecha < p.llegada
UNION ALL
SELECT 'transferencias de un vino antes de su primer ingreso', count(*)
  FROM renglon_transferencia rt
  JOIN transferencia t ON t.nro_transferencia = rt.nro_transferencia
  LEFT JOIN (SELECT ri.cod_vino, min(i.fecha) AS primero
               FROM ingreso i JOIN renglon_ingreso ri ON ri.cod_ingreso = i.cod_ingreso
              WHERE i.estado = 'procesado'
              GROUP BY ri.cod_vino) p ON p.cod_vino = rt.cod_vino
 WHERE t.estado = 'procesado' AND (p.primero IS NULL OR t.fecha_confeccion < p.primero)
UNION ALL
SELECT 'ingresos de un vino antes del anio siguiente a su aniada', count(*)
  FROM renglon_ingreso r JOIN ingreso i ON i.cod_ingreso = r.cod_ingreso JOIN vino v ON v.cod_vino = r.cod_vino
 WHERE EXTRACT(YEAR FROM i.fecha) <= v.anada
UNION ALL
SELECT 'ingresos de un vino de otra bodega', count(*)
  FROM renglon_ingreso r JOIN ingreso i ON i.cod_ingreso = r.cod_ingreso JOIN vino v ON v.cod_vino = r.cod_vino
 WHERE v.cuit_bodega <> i.cuit_bodega
UNION ALL
SELECT 'analisis anteriores a la cosecha', count(*)
  FROM analisis_calidad a JOIN lote_uva l ON l.nro_lote = a.nro_lote
 WHERE a.fecha < l.fecha_cosecha
UNION ALL
SELECT 'documentos con fecha futura', count(*)
  FROM (SELECT fecha FROM comprobante UNION ALL SELECT fecha FROM ingreso
        UNION ALL SELECT fecha_confeccion FROM transferencia UNION ALL SELECT fecha_cosecha FROM lote_uva) f
 WHERE f.fecha > CURRENT_DATE
UNION ALL
SELECT 'triggers propios deshabilitados', count(*)
  FROM pg_trigger WHERE NOT tgisinternal AND tgenabled = 'D';

-- datos que usan las consultas por periodo
SELECT 'comprobantes de la ultima semana' AS dato, count(*) AS cantidad FROM comprobante WHERE fecha > CURRENT_DATE - 7
UNION ALL SELECT 'comprobantes del ultimo trimestre', count(*) FROM comprobante WHERE fecha > CURRENT_DATE - INTERVAL '3 months'
UNION ALL SELECT 'comprobantes de socios con mas de 5 anios', count(*)
  FROM comprobante c JOIN cliente cl ON cl.id_cliente = c.id_cliente
 WHERE cl.tipo = 'socio' AND c.fecha < CURRENT_DATE - INTERVAL '5 years'
UNION ALL SELECT 'transferencias de los ultimos 15 dias', count(*) FROM transferencia WHERE fecha_confeccion > CURRENT_DATE - 15
UNION ALL SELECT 'transferencias pendientes', count(*) FROM transferencia WHERE estado <> 'procesado'
UNION ALL SELECT 'ingresos del ultimo mes', count(*) FROM ingreso WHERE fecha > CURRENT_DATE - INTERVAL '1 month'
UNION ALL SELECT 'ingresos procesados de hace mas de 365 dias', count(*) FROM ingreso WHERE estado = 'procesado' AND fecha < CURRENT_DATE - 365
UNION ALL SELECT 'socios sin compras dados de alta hace mas de 5 anios', count(*)
  FROM cliente c WHERE c.tipo = 'socio' AND c.fecha_alta < CURRENT_DATE - INTERVAL '5 years'
   AND NOT EXISTS (SELECT 1 FROM comprobante co WHERE co.id_cliente = c.id_cliente)
UNION ALL SELECT 'empleados con mas de 5 anios', count(*) FROM empleado WHERE fn_antiguedad_anios(fecha_ingreso) > 5
UNION ALL SELECT 'exportadores con mas de 3 permisos', count(*)
  FROM (SELECT id_cliente FROM permiso_exportacion GROUP BY id_cliente HAVING count(*) > 3) e
UNION ALL SELECT 'pares sala-vino con stock 0', count(*) FROM stock_sala WHERE cantidad = 0;
