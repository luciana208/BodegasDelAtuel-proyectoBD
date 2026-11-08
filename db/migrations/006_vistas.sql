-- vistas

-- stock de cada vino en el deposito, en las salas y en total
CREATE VIEW v_stock_total_vino AS
SELECT v.cod_vino,
       v.nombre,
       v.anada,
       v.volumen_ml,
       COALESCE(d.cantidad, 0) AS stock_deposito,
       COALESCE(s.cantidad, 0) AS stock_salas,
       COALESCE(d.cantidad, 0) + COALESCE(s.cantidad, 0) AS stock_total
  FROM vino v
  LEFT JOIN stock_deposito d ON d.cod_vino = v.cod_vino
  LEFT JOIN (SELECT cod_vino, SUM(cantidad) AS cantidad
               FROM stock_sala
              GROUP BY cod_vino) s ON s.cod_vino = v.cod_vino;

-- ventas de cada sala agrupadas por mes
CREATE VIEW v_ventas_mensuales_sala AS
SELECT c.id_sala,
       l.nombre AS localidad,
       date_trunc('month', c.fecha)::DATE AS mes,
       count(*) AS cantidad_comprobantes,
       SUM(c.total) AS total_vendido
  FROM comprobante c
  JOIN sala_venta s ON s.id_sala = c.id_sala
  JOIN localidad l ON l.id_localidad = s.id_localidad
 GROUP BY c.id_sala, l.nombre, date_trunc('month', c.fecha);

-- ingresos y transferencias que todavia no se procesaron
CREATE VIEW v_documentos_pendientes AS
SELECT 'ingreso' AS documento,
       i.cod_ingreso AS numero,
       i.fecha,
       i.estado,
       b.razon_social AS origen_destino,
       (SELECT count(*) FROM renglon_ingreso r WHERE r.cod_ingreso = i.cod_ingreso) AS renglones,
       (SELECT COALESCE(SUM(r.cantidad), 0) FROM renglon_ingreso r WHERE r.cod_ingreso = i.cod_ingreso) AS botellas
  FROM ingreso i
  JOIN bodega b ON b.cuit = i.cuit_bodega
 WHERE i.estado <> 'procesado'
UNION ALL
SELECT 'transferencia',
       t.nro_transferencia,
       t.fecha_confeccion,
       t.estado,
       'Sala ' || t.id_sala,
       (SELECT count(*) FROM renglon_transferencia r WHERE r.nro_transferencia = t.nro_transferencia),
       (SELECT COALESCE(SUM(r.cantidad), 0) FROM renglon_transferencia r WHERE r.nro_transferencia = t.nro_transferencia)
  FROM transferencia t
 WHERE t.estado <> 'procesado';

/* ficha de cada vino: bodega, cepas con su porcentaje, maridajes y stock total.
   las cepas y los maridajes se agregan en subconsultas para no multiplicar filas */
CREATE VIEW v_ficha_vino AS
SELECT v.cod_vino,
       v.nombre,
       v.tipo,
       v.anada,
       v.volumen_ml,
       v.graduacion,
       v.precio,
       b.razon_social AS bodega,
       (SELECT string_agg(ce.nombre || ' ' || co.porcentaje || '%', ', ' ORDER BY co.porcentaje DESC, ce.nombre)
          FROM composicion co JOIN cepa ce ON ce.id_cepa = co.id_cepa
         WHERE co.cod_vino = v.cod_vino) AS cepas,
       (SELECT string_agg(m.nombre || ' (' || m.temperatura_servicio || ' C)', ', ' ORDER BY m.nombre)
          FROM vino_maridaje vm JOIN maridaje m ON m.id_maridaje = vm.id_maridaje
         WHERE vm.cod_vino = v.cod_vino) AS maridajes,
       fn_stock_total(v.cod_vino) AS stock_total
  FROM vino v
  JOIN bodega b ON b.cuit = v.cuit_bodega;
