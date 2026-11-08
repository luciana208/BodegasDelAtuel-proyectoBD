-- huella md5 de cada tabla, para comparar dos cargas hechas con la misma semilla

\pset pager off

SELECT * FROM (
SELECT 'departamento' AS tabla, count(*) AS filas, md5(string_agg(t::TEXT, '|' ORDER BY t.id_departamento)) AS huella FROM departamento t
UNION ALL SELECT 'localidad', count(*), md5(string_agg(t::TEXT, '|' ORDER BY t.id_localidad)) FROM localidad t
UNION ALL SELECT 'sala_venta', count(*), md5(string_agg(t::TEXT, '|' ORDER BY t.id_sala)) FROM sala_venta t
UNION ALL SELECT 'empleado', count(*), md5(string_agg(t::TEXT, '|' ORDER BY t.cuit)) FROM empleado t
UNION ALL SELECT 'cepa', count(*), md5(string_agg(t::TEXT, '|' ORDER BY t.id_cepa)) FROM cepa t
UNION ALL SELECT 'finca', count(*), md5(string_agg(t::TEXT, '|' ORDER BY t.id_finca)) FROM finca t
UNION ALL SELECT 'parcela', count(*), md5(string_agg(t::TEXT, '|' ORDER BY t.id_finca, t.nro_parcela)) FROM parcela t
UNION ALL SELECT 'bodega', count(*), md5(string_agg(t::TEXT, '|' ORDER BY t.cuit)) FROM bodega t
UNION ALL SELECT 'lote_uva', count(*), md5(string_agg(t::TEXT, '|' ORDER BY t.nro_lote)) FROM lote_uva t
UNION ALL SELECT 'analisis_calidad', count(*), md5(string_agg(t::TEXT, '|' ORDER BY t.id_analisis)) FROM analisis_calidad t
UNION ALL SELECT 'vino', count(*), md5(string_agg(t::TEXT, '|' ORDER BY t.cod_vino)) FROM vino t
UNION ALL SELECT 'composicion', count(*), md5(string_agg(t::TEXT, '|' ORDER BY t.cod_vino, t.id_cepa)) FROM composicion t
UNION ALL SELECT 'maridaje', count(*), md5(string_agg(t::TEXT, '|' ORDER BY t.id_maridaje)) FROM maridaje t
UNION ALL SELECT 'vino_maridaje', count(*), md5(string_agg(t::TEXT, '|' ORDER BY t.cod_vino, t.id_maridaje)) FROM vino_maridaje t
UNION ALL SELECT 'cliente', count(*), md5(string_agg(t::TEXT, '|' ORDER BY t.id_cliente)) FROM cliente t
UNION ALL SELECT 'socio', count(*), md5(string_agg(t::TEXT, '|' ORDER BY t.id_cliente)) FROM socio t
UNION ALL SELECT 'distribuidor', count(*), md5(string_agg(t::TEXT, '|' ORDER BY t.id_cliente)) FROM distribuidor t
UNION ALL SELECT 'exportador', count(*), md5(string_agg(t::TEXT, '|' ORDER BY t.id_cliente)) FROM exportador t
UNION ALL SELECT 'permiso_exportacion', count(*), md5(string_agg(t::TEXT, '|' ORDER BY t.cod_permiso)) FROM permiso_exportacion t
UNION ALL SELECT 'comprobante', count(*), md5(string_agg(t::TEXT, '|' ORDER BY t.nro_comprobante)) FROM comprobante t
UNION ALL SELECT 'renglon_comprobante', count(*), md5(string_agg(t::TEXT, '|' ORDER BY t.nro_comprobante, t.cod_vino)) FROM renglon_comprobante t
UNION ALL SELECT 'stock_sala', count(*), md5(string_agg(t::TEXT, '|' ORDER BY t.id_sala, t.cod_vino)) FROM stock_sala t
UNION ALL SELECT 'stock_deposito', count(*), md5(string_agg(t::TEXT, '|' ORDER BY t.cod_vino)) FROM stock_deposito t
UNION ALL SELECT 'transportista', count(*), md5(string_agg(t::TEXT, '|' ORDER BY t.cod_transporte)) FROM transportista t
UNION ALL SELECT 'transportista_localidad', count(*), md5(string_agg(t::TEXT, '|' ORDER BY t.cod_transporte, t.id_localidad)) FROM transportista_localidad t
UNION ALL SELECT 'ingreso', count(*), md5(string_agg(t::TEXT, '|' ORDER BY t.cod_ingreso)) FROM ingreso t
UNION ALL SELECT 'renglon_ingreso', count(*), md5(string_agg(t::TEXT, '|' ORDER BY t.cod_ingreso, t.cod_vino)) FROM renglon_ingreso t
UNION ALL SELECT 'transferencia', count(*), md5(string_agg(t::TEXT, '|' ORDER BY t.nro_transferencia)) FROM transferencia t
UNION ALL SELECT 'renglon_transferencia', count(*), md5(string_agg(t::TEXT, '|' ORDER BY t.nro_transferencia, t.cod_vino)) FROM renglon_transferencia t
UNION ALL SELECT 'auditoria_precio', count(*), md5(string_agg(t::TEXT, '|' ORDER BY t.id_auditoria)) FROM auditoria_precio t
) h
ORDER BY tabla;
