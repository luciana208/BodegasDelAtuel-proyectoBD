'''
inyeccion sql fallida: los filtros viajan como parametros, asi que un texto malicioso
se compara como un texto comun y no cambia la consulta
'''

MALICIOSOS = [
    "' OR '1'='1",
    "'; DROP TABLE vino; --",
    "x' UNION SELECT cuit, razon_social FROM bodega --",
]


def test_inyeccion_en_el_filtro_de_nombre(api, datos):
    total = api.get('/vinos').json()['total']
    for texto in MALICIOSOS:
        r = api.get('/vinos', params={'nombre': texto})
        assert r.status_code == 200
        # se busco un vino con ese nombre y no hay ninguno
        assert r.json()['total'] == 0
    # la tabla sigue entera
    assert api.get('/vinos').json()['total'] == total
    assert datos['conn'].execute("SELECT to_regclass('public.vino') IS NOT NULL AS existe").fetchone()['existe']


def test_inyeccion_en_un_filtro_con_tipo(api):
    # en el filtro de tipo el texto se intenta convertir al enum y la base lo rechaza como formato invalido
    r = api.get('/vinos', params={'tipo': "tinto' OR '1'='1"})
    assert r.status_code == 400
    assert r.json()['sqlstate'] == '22P02'
