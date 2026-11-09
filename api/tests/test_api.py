'''
pruebas de la api contra la base real. las que provocan errores verifican el codigo http
y que el mensaje sea el de la regla de la base
'''


def vino_nuevo(datos, **cambios):
    vino = {'nombre': 'Vino Pytest Nuevo', 'tipo': 'tinto', 'anada': 2023, 'volumen_ml': 750,
            'graduacion': 13.5, 'precio': 8000, 'cuit_bodega': datos['bodega'],
            'composicion': [{'id_cepa': datos['cepa'], 'porcentaje': 100}], 'maridajes': [datos['maridaje']]}
    vino.update(cambios)
    return vino


def test_salud_con_rol_de_la_api(api):
    r = api.get('/salud')
    assert r.status_code == 200
    assert r.json()['usuario'] == 'bodega_app'


def test_catalogo_paginado(api):
    r1 = api.get('/vinos', params={'pagina': 1, 'tamanio': 5})
    r2 = api.get('/vinos', params={'pagina': 2, 'tamanio': 5})
    assert r1.status_code == 200 and r2.status_code == 200
    assert len(r1.json()['datos']) == 5
    assert r1.json()['total'] == r2.json()['total']
    codigos_1 = {v['cod_vino'] for v in r1.json()['datos']}
    codigos_2 = {v['cod_vino'] for v in r2.json()['datos']}
    assert not codigos_1 & codigos_2


def test_catalogo_con_filtros(api, datos):
    r = api.get('/vinos', params={'tipo': 'tinto', 'cepa': datos['cepa'], 'bodega': datos['bodega'], 'anada': 2022})
    assert r.status_code == 200
    vinos = r.json()['datos']
    assert [v['cod_vino'] for v in vinos] == [datos['vino']]
    assert all(v['tipo'] == 'tinto' and v['anada'] == 2022 for v in vinos)


def test_detalle_con_cepas_maridajes_y_stock(api, datos):
    r = api.get(f'/vinos/{datos["vino"]}')
    assert r.status_code == 200
    vino = r.json()
    assert vino['composicion'][0]['porcentaje'] == 100
    assert len(vino['maridajes']) == 1
    assert vino['stock_total'] == vino['stock_deposito'] + vino['stock_salas']


def test_alta_modificacion_y_baja_de_vino(api, datos):
    r = api.post('/vinos', json=vino_nuevo(datos))
    assert r.status_code == 201
    cod = r.json()['cod_vino']
    r = api.put(f'/vinos/{cod}', json=vino_nuevo(datos, precio=8800))
    assert r.status_code == 200 and r.json()['precio'] == 8800
    # el cambio de precio quedo auditado por el trigger
    fila = datos['conn'].execute('SELECT precio_anterior, precio_nuevo, usuario FROM auditoria_precio WHERE cod_vino = %s',
                                 (cod,)).fetchone()
    assert fila['precio_anterior'] == 8000 and fila['precio_nuevo'] == 8800 and fila['usuario'] == 'bodega_app'
    datos['conn'].execute('DELETE FROM auditoria_precio WHERE cod_vino = %s', (cod,))
    assert api.delete(f'/vinos/{cod}').status_code == 204
    assert api.get(f'/vinos/{cod}').status_code == 404


def test_composicion_que_no_suma_100(api, datos):
    vino = vino_nuevo(datos, composicion=[{'id_cepa': datos['cepa'], 'porcentaje': 90}])
    r = api.post('/vinos', json=vino)
    assert r.status_code == 409
    assert r.json()['sqlstate'] == 'P0001'
    assert 'RN-05' in r.json()['error']


def test_precio_negativo(api, datos):
    r = api.post('/vinos', json=vino_nuevo(datos, precio=-500))
    assert r.status_code == 422
    assert r.json()['restriccion'] == 'chk_vino_precio'


def test_venta_con_totales_calculados_por_la_base(api, datos):
    r = api.post('/comprobantes', json={'id_cliente': datos['cliente'], 'id_sala': datos['sala'],
                                        'renglones': [{'cod_vino': datos['vino'], 'cantidad': 2}]})
    assert r.status_code == 201
    comprobante = r.json()
    # socio: 10 % de descuento sobre 2 botellas de 10000
    assert comprobante['subtotal'] == 20000
    assert comprobante['descuento'] == 2000
    assert comprobante['total'] == 18000
    assert comprobante['renglones'][0]['porc_descuento'] == 10
    assert api.get(f'/comprobantes/{comprobante["nro_comprobante"]}').status_code == 200


def test_venta_sin_stock_no_deja_datos(api, datos):
    conn = datos['conn']
    antes = conn.execute('SELECT count(*) AS n FROM comprobante WHERE id_sala = %s', (datos['sala'],)).fetchone()['n']
    stock = conn.execute('SELECT fn_stock_sala(%s, %s) AS s', (datos['sala'], datos['vino'])).fetchone()['s']
    r = api.post('/comprobantes', json={'id_cliente': datos['cliente'], 'id_sala': datos['sala'],
                                        'renglones': [{'cod_vino': datos['vino'], 'cantidad': 500}]})
    assert r.status_code == 409
    assert 'Stock insuficiente' in r.json()['error'] and 'RN-09' in r.json()['error']
    despues = conn.execute('SELECT count(*) AS n FROM comprobante WHERE id_sala = %s', (datos['sala'],)).fetchone()['n']
    assert despues == antes
    assert conn.execute('SELECT fn_stock_sala(%s, %s) AS s', (datos['sala'], datos['vino'])).fetchone()['s'] == stock


def test_cambio_de_estado_invalido(api, datos):
    nro = api.post('/transferencias', json={'id_sala': datos['sala']}).json()['nro_transferencia']
    r = api.post(f'/transferencias/{nro}/procesar')
    assert r.status_code == 409 and 'RN-11' in r.json()['error']
    r = api.post(f'/transferencias/{nro}/terminar')
    assert r.status_code == 409 and 'no tiene renglones' in r.json()['error']


def test_circuito_de_transferencia(api, datos):
    conn = datos['conn']
    deposito = conn.execute('SELECT cantidad FROM stock_deposito WHERE cod_vino = %s', (datos['vino'],)).fetchone()['cantidad']
    sala = conn.execute('SELECT fn_stock_sala(%s, %s) AS s', (datos['sala'], datos['vino'])).fetchone()['s']
    r = api.post('/transferencias', json={'id_sala': datos['sala']})
    assert r.status_code == 201 and r.json()['estado'] == 'en_confeccion'
    nro = r.json()['nro_transferencia']
    assert api.post(f'/transferencias/{nro}/renglones', json={'cod_vino': datos['vino'], 'cantidad': 10}).status_code == 201
    assert api.post(f'/transferencias/{nro}/terminar').json()['estado'] == 'terminado'
    # con la transferencia terminada no se aceptan renglones nuevos
    r = api.post(f'/transferencias/{nro}/renglones', json={'cod_vino': datos['vino'], 'cantidad': 1})
    assert r.status_code == 409 and 'RN-12' in r.json()['error']
    assert api.post(f'/transferencias/{nro}/procesar').json()['estado'] == 'procesado'
    assert conn.execute('SELECT cantidad FROM stock_deposito WHERE cod_vino = %s', (datos['vino'],)).fetchone()['cantidad'] == deposito - 10
    assert conn.execute('SELECT fn_stock_sala(%s, %s) AS s', (datos['sala'], datos['vino'])).fetchone()['s'] == sala + 10


def test_transferencia_sin_stock_en_deposito(api, datos):
    nro = api.post('/transferencias', json={'id_sala': datos['sala']}).json()['nro_transferencia']
    api.post(f'/transferencias/{nro}/renglones', json={'cod_vino': datos['vino'], 'cantidad': 100000})
    api.post(f'/transferencias/{nro}/terminar')
    r = api.post(f'/transferencias/{nro}/procesar')
    assert r.status_code == 409 and 'deposito central' in r.json()['error']
    assert api.get(f'/transferencias/{nro}').json()['estado'] == 'terminado'


def test_circuito_de_ingreso(api, datos):
    conn = datos['conn']
    deposito = conn.execute('SELECT cantidad FROM stock_deposito WHERE cod_vino = %s', (datos['vino'],)).fetchone()['cantidad']
    cod = api.post('/ingresos', json={'cod_transporte': datos['transportista'], 'cuit_bodega': datos['bodega']}).json()['cod_ingreso']
    assert api.post(f'/ingresos/{cod}/renglones', json={'cod_vino': datos['vino'], 'cantidad': 120}).status_code == 201
    r = api.post(f'/ingresos/{cod}/procesar')
    assert r.status_code == 409 and 'RN-10' in r.json()['error']
    api.post(f'/ingresos/{cod}/terminar')
    assert api.post(f'/ingresos/{cod}/procesar').json()['estado'] == 'procesado'
    assert conn.execute('SELECT cantidad FROM stock_deposito WHERE cod_vino = %s', (datos['vino'],)).fetchone()['cantidad'] == deposito + 120


def test_borrar_vino_con_movimientos(api, datos):
    r = api.delete(f'/vinos/{datos["vino"]}')
    assert r.status_code == 409
    assert r.json()['sqlstate'] == '23503'


def test_clientes_de_los_tres_tipos(api, datos):
    base = {'tipo_documento': 'CUIT', 'direccion': 'Calle 4', 'id_localidad': datos['localidad']}
    r = api.post('/clientes', json={**base, 'nombre': 'Exportador Pytest', 'nro_documento': '99999971', 'tipo': 'exportador',
                                    'pais_destino': 'Chile',
                                    'permisos': [{'cod_permiso': 'PE-PYTEST-1', 'fecha_emision': '2025-01-01',
                                                  'fecha_vencimiento': '2027-01-01'}]})
    assert r.status_code == 201
    exportador = r.json()
    assert exportador['descuento'] == 30 and len(exportador['permisos']) == 1
    r = api.post('/clientes', json={**base, 'nombre': 'Distribuidor Pytest', 'nro_documento': '99999972', 'tipo': 'distribuidor',
                                    'zona_cobertura': 'Sur', 'nro_habilitacion': 'HAB-PYTEST'})
    assert r.status_code == 201 and r.json()['descuento'] == 20
    distribuidor = r.json()['id_cliente']
    r = api.put(f'/clientes/{distribuidor}', json={**base, 'nombre': 'Distribuidor Pytest SA', 'nro_documento': '99999972',
                                                   'tipo': 'distribuidor', 'zona_cobertura': 'Norte',
                                                   'nro_habilitacion': 'HAB-PYTEST'})
    assert r.status_code == 200 and r.json()['zona_cobertura'] == 'Norte'
    # un documento repetido viola el unique
    r = api.post('/clientes', json={**base, 'nombre': 'Repetido', 'nro_documento': '99999972', 'tipo': 'distribuidor',
                                    'zona_cobertura': 'Sur', 'nro_habilitacion': 'HAB-PYTEST-2'})
    assert r.status_code == 409 and r.json()['sqlstate'] == '23505'
    # un permiso que vence antes de emitirse viola el check entre columnas
    r = api.post('/clientes', json={**base, 'nombre': 'Exportador Malo', 'nro_documento': '99999973', 'tipo': 'exportador',
                                    'pais_destino': 'Peru',
                                    'permisos': [{'cod_permiso': 'PE-PYTEST-2', 'fecha_emision': '2025-01-01',
                                                  'fecha_vencimiento': '2024-01-01'}]})
    assert r.status_code == 422 and r.json()['restriccion'] == 'chk_permiso_fechas'
    assert api.get('/clientes', params={'nombre': 'Pytest'}).json()['total'] >= 3
    assert api.delete(f'/clientes/{exportador["id_cliente"]}').status_code == 204
    assert api.delete(f'/clientes/{datos["cliente"]}').status_code == 409


def test_reportes(api, datos):
    assert api.get('/reportes/top-vinos').status_code == 200
    assert api.get('/reportes/ventas-por-sala').status_code == 200
    assert api.get('/reportes/vinos-sin-stock', params={'sala': 1}).status_code == 200
    assert api.get('/reportes/transportista-activo').status_code == 200
    r = api.get(f'/reportes/trazabilidad/{datos["vino"]}')
    assert r.status_code == 200
    assert {'ingresos', 'transferencias', 'ventas_por_sala'} <= set(r.json())


def test_formato_invalido(api):
    assert api.get('/vinos', params={'tipo': 'rojo'}).status_code == 400
    assert api.get('/vinos', params={'anada': 'dos mil'}).status_code == 422
    assert api.get('/vinos/999999').status_code == 404
