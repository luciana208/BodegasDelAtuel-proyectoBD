'''
datos de prueba propios para no depender de la carga. se crean con el rol propietario
antes de las pruebas y se borran al terminar, asi la base queda como estaba
'''
import os

import psycopg
import pytest
from fastapi.testclient import TestClient
from psycopg.rows import dict_row

from app.main import app

BODEGA = '30999999970'
TRANSPORTISTA = 'Transporte Pytest'


def conexion_propietario():
    return psycopg.connect(
        host=os.environ.get('DB_HOST', 'localhost'),
        port=os.environ.get('DB_PORT', '5432'),
        dbname=os.environ.get('DB_NAME', 'bodegas'),
        user=os.environ['PRUEBAS_OWNER_USER'],
        password=os.environ['PRUEBAS_OWNER_PASSWORD'],
        autocommit=True,
        row_factory=dict_row,
    )


def limpiar(cur):
    cur.execute("DELETE FROM comprobante WHERE id_sala IN (SELECT id_sala FROM sala_venta WHERE calle = 'Calle Pytest')")
    cur.execute("DELETE FROM transferencia WHERE id_sala IN (SELECT id_sala FROM sala_venta WHERE calle = 'Calle Pytest')")
    cur.execute('DELETE FROM ingreso WHERE cuit_bodega = %s', (BODEGA,))
    cur.execute('DELETE FROM stock_sala WHERE cod_vino IN (SELECT cod_vino FROM vino WHERE cuit_bodega = %s)', (BODEGA,))
    cur.execute('DELETE FROM stock_deposito WHERE cod_vino IN (SELECT cod_vino FROM vino WHERE cuit_bodega = %s)', (BODEGA,))
    cur.execute('DELETE FROM auditoria_precio WHERE cod_vino IN (SELECT cod_vino FROM vino WHERE cuit_bodega = %s)', (BODEGA,))
    cur.execute('DELETE FROM vino WHERE cuit_bodega = %s', (BODEGA,))
    cur.execute("DELETE FROM cliente WHERE nro_documento LIKE '9999997%%'")
    cur.execute("DELETE FROM sala_venta WHERE calle = 'Calle Pytest'")
    cur.execute("DELETE FROM localidad WHERE nombre = 'Localidad Pytest'")
    cur.execute("DELETE FROM departamento WHERE nombre = 'Departamento Pytest'")
    cur.execute('DELETE FROM bodega WHERE cuit = %s', (BODEGA,))
    cur.execute('DELETE FROM transportista WHERE razon_social = %s', (TRANSPORTISTA,))


@pytest.fixture(scope='session')
def datos():
    with conexion_propietario() as conn:
        cur = conn.cursor()
        limpiar(cur)
        with conn.transaction():
            depto = cur.execute("INSERT INTO departamento (nombre, provincia) VALUES ('Departamento Pytest', 'Mendoza') "
                                'RETURNING id_departamento').fetchone()['id_departamento']
            loc = cur.execute("INSERT INTO localidad (nombre, cod_postal, id_departamento, encargado_regional) "
                              "VALUES ('Localidad Pytest', '5600', %s, 'Encargado Pytest') RETURNING id_localidad",
                              (depto,)).fetchone()['id_localidad']
            sala = cur.execute("INSERT INTO sala_venta (calle, numero, dia_cierre, id_localidad) "
                               "VALUES ('Calle Pytest', 1, 'lunes', %s) RETURNING id_sala", (loc,)).fetchone()['id_sala']
            cur.execute("INSERT INTO bodega (cuit, razon_social, domicilio) VALUES (%s, 'Bodega Pytest', 'Calle 1')", (BODEGA,))
            transporte = cur.execute("INSERT INTO transportista (razon_social, cuit, email, telefono, domicilio) "
                                     "VALUES (%s, '20999999971', 'pytest@prueba.com', '0', 'Calle 2') "
                                     'RETURNING cod_transporte', (TRANSPORTISTA,)).fetchone()['cod_transporte']
            malbec = cur.execute("SELECT id_cepa FROM cepa WHERE nombre = 'Malbec'").fetchone()['id_cepa']
            vino = cur.execute("INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega) "
                               "VALUES ('Vino Pytest', 'tinto', 2022, 750, 14, 10000, %s) RETURNING cod_vino",
                               (BODEGA,)).fetchone()['cod_vino']
            cur.execute('INSERT INTO composicion (cod_vino, id_cepa, porcentaje) VALUES (%s, %s, 100)', (vino, malbec))
            maridaje = cur.execute('SELECT min(id_maridaje) AS m FROM maridaje').fetchone()['m']
            cur.execute('INSERT INTO vino_maridaje (cod_vino, id_maridaje) VALUES (%s, %s)', (vino, maridaje))
            cur.execute('INSERT INTO stock_deposito (cod_vino, cantidad) VALUES (%s, 100)', (vino,))
            cur.execute('INSERT INTO stock_sala (id_sala, cod_vino, cantidad) VALUES (%s, %s, 5)', (sala, vino))
            cliente = cur.execute("INSERT INTO cliente (nombre, tipo_documento, nro_documento, direccion, id_localidad, tipo) "
                                  "VALUES ('Socio Pytest', 'DNI', '99999970', 'Calle 3', %s, 'socio') RETURNING id_cliente",
                                  (loc,)).fetchone()['id_cliente']
            cur.execute('INSERT INTO socio (id_cliente, nro_carnet) VALUES (%s, 999970)', (cliente,))
        yield {'sala': sala, 'localidad': loc, 'vino': vino, 'cepa': malbec, 'maridaje': maridaje,
               'cliente': cliente, 'bodega': BODEGA, 'transportista': transporte, 'conn': conn}
        limpiar(cur)


@pytest.fixture(scope='session')
def api():
    with TestClient(app) as cliente:
        yield cliente
