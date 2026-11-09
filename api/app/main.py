'''
api rest de bodegas del atuel. los controladores solo reciben el pedido, llaman a una
funcion del modulo de datos y devuelven el resultado. los errores de la base los traduce
el manejador central de errores.py
'''
from contextlib import asynccontextmanager

import psycopg
from fastapi import Depends, FastAPI, HTTPException, Query, Response
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from starlette.exceptions import HTTPException as StarletteHTTPException

from . import datos
from .config import origenes_cors
from .db import obtener_conexion, pool
from .errores import manejar_error_base, manejar_error_http, manejar_error_validacion
from .modelos import ClienteEntrada, ComprobanteEntrada, Corte, IngresoEntrada, Permiso, Renglon, TransferenciaEntrada, VinoEntrada


@asynccontextmanager
async def ciclo_de_vida(app):
    pool.open()
    yield
    pool.close()


app = FastAPI(
    title='Bodegas del Atuel',
    description='API de gestion de vinos, clientes, ventas, ingresos y transferencias.',
    version='1.0.0',
    lifespan=ciclo_de_vida,
)
app.add_middleware(CORSMiddleware, allow_origins=origenes_cors(), allow_methods=['*'], allow_headers=['*'])
app.add_exception_handler(psycopg.Error, manejar_error_base)
app.add_exception_handler(RequestValidationError, manejar_error_validacion)
app.add_exception_handler(StarletteHTTPException, manejar_error_http)


def pagina(filas, numero, tamanio):
    total = filas[0]['total_filas'] if filas else 0
    for f in filas:
        f.pop('total_filas')
    return {'pagina': numero, 'tamanio': tamanio, 'total': total, 'datos': filas}


def no_encontrado(que):
    raise HTTPException(status_code=404, detail=f'{que} no existe')


# salud

@app.get('/salud', tags=['salud'], summary='Estado de la API y de la base')
def salud(conn=Depends(obtener_conexion)):
    fila = datos.salud(conn)
    return {'estado': 'ok', **fila}


# catalogos

@app.get('/cepas', tags=['catalogos'], summary='Listar cepas')
def cepas(conn=Depends(obtener_conexion)):
    return datos.listar_cepas(conn)


@app.get('/bodegas', tags=['catalogos'], summary='Listar bodegas')
def bodegas(conn=Depends(obtener_conexion)):
    return datos.listar_bodegas(conn)


@app.get('/maridajes', tags=['catalogos'], summary='Listar maridajes')
def maridajes(conn=Depends(obtener_conexion)):
    return datos.listar_maridajes(conn)


@app.get('/salas', tags=['catalogos'], summary='Listar salas de venta')
def salas(conn=Depends(obtener_conexion)):
    return datos.listar_salas(conn)


@app.get('/localidades', tags=['catalogos'], summary='Listar localidades')
def localidades(conn=Depends(obtener_conexion)):
    return datos.listar_localidades(conn)


@app.get('/transportistas', tags=['catalogos'], summary='Listar transportistas')
def transportistas(conn=Depends(obtener_conexion)):
    return datos.listar_transportistas(conn)


# vinos

@app.get('/vinos', tags=['vinos'], summary='Catalogo de vinos con filtros y paginacion')
def listar_vinos(tipo: str | None = Query(None, description='tinto, blanco, rosado o espumante'),
                 cepa: int | None = Query(None, description='id de cepa que forma parte del corte'),
                 bodega: str | None = Query(None, description='cuit de la bodega'),
                 anada: int | None = None,
                 nombre: str | None = Query(None, description='parte del nombre'),
                 pagina_nro: int = Query(1, alias='pagina', ge=1),
                 tamanio: int = Query(20, ge=1, le=100),
                 conn=Depends(obtener_conexion)):
    filas = datos.listar_vinos(conn, tipo, cepa, bodega, anada, nombre, tamanio, (pagina_nro - 1) * tamanio)
    return pagina(filas, pagina_nro, tamanio)


@app.get('/vinos/{cod_vino}', tags=['vinos'], summary='Detalle de un vino con cepas, maridajes y stock')
def obtener_vino(cod_vino: int, conn=Depends(obtener_conexion)):
    vino = datos.obtener_vino(conn, cod_vino)
    if vino is None:
        no_encontrado('El vino')
    return vino


@app.post('/vinos', tags=['vinos'], status_code=201, summary='Alta de un vino con su composicion')
def crear_vino(vino: VinoEntrada, conn=Depends(obtener_conexion)):
    cod_vino = datos.crear_vino(conn, vino)
    return datos.obtener_vino(conn, cod_vino)


@app.put('/vinos/{cod_vino}', tags=['vinos'], summary='Modificacion de un vino (el cambio de precio queda auditado)')
def actualizar_vino(cod_vino: int, vino: VinoEntrada, conn=Depends(obtener_conexion)):
    if not datos.actualizar_vino(conn, cod_vino, vino):
        no_encontrado('El vino')
    return datos.obtener_vino(conn, cod_vino)


@app.delete('/vinos/{cod_vino}', tags=['vinos'], status_code=204, summary='Baja de un vino sin movimientos')
def borrar_vino(cod_vino: int, conn=Depends(obtener_conexion)):
    if not datos.borrar_vino(conn, cod_vino):
        no_encontrado('El vino')
    return Response(status_code=204)


# clientes

@app.get('/clientes', tags=['clientes'], summary='Listado de clientes con filtros y paginacion')
def listar_clientes(tipo: str | None = Query(None, description='socio, distribuidor o exportador'),
                    nombre: str | None = Query(None, description='parte del nombre'),
                    pagina_nro: int = Query(1, alias='pagina', ge=1),
                    tamanio: int = Query(20, ge=1, le=100),
                    conn=Depends(obtener_conexion)):
    filas = datos.listar_clientes(conn, tipo, nombre, tamanio, (pagina_nro - 1) * tamanio)
    return pagina(filas, pagina_nro, tamanio)


@app.get('/clientes/{id_cliente}', tags=['clientes'], summary='Detalle de un cliente con los datos de su tipo')
def obtener_cliente(id_cliente: int, conn=Depends(obtener_conexion)):
    cliente = datos.obtener_cliente(conn, id_cliente)
    if cliente is None:
        no_encontrado('El cliente')
    return cliente


@app.post('/clientes', tags=['clientes'], status_code=201, summary='Alta de un cliente de cualquiera de los tres tipos')
def crear_cliente(cliente: ClienteEntrada, conn=Depends(obtener_conexion)):
    id_cliente = datos.crear_cliente(conn, cliente)
    return datos.obtener_cliente(conn, id_cliente)


@app.put('/clientes/{id_cliente}', tags=['clientes'], summary='Modificacion de un cliente')
def actualizar_cliente(id_cliente: int, cliente: ClienteEntrada, conn=Depends(obtener_conexion)):
    if not datos.actualizar_cliente(conn, id_cliente, cliente):
        no_encontrado('El cliente')
    return datos.obtener_cliente(conn, id_cliente)


@app.delete('/clientes/{id_cliente}', tags=['clientes'], status_code=204, summary='Baja de un cliente sin compras')
def borrar_cliente(id_cliente: int, conn=Depends(obtener_conexion)):
    if not datos.borrar_cliente(conn, id_cliente):
        no_encontrado('El cliente')
    return Response(status_code=204)


# comprobantes

@app.post('/comprobantes', tags=['ventas'], status_code=201, summary='Registrar una venta completa en una transaccion')
def crear_comprobante(comprobante: ComprobanteEntrada, conn=Depends(obtener_conexion)):
    nro = datos.crear_comprobante(conn, comprobante)
    return datos.obtener_comprobante(conn, nro)


@app.get('/comprobantes/{nro}', tags=['ventas'], summary='Comprobante con sus renglones')
def obtener_comprobante(nro: int, conn=Depends(obtener_conexion)):
    comprobante = datos.obtener_comprobante(conn, nro)
    if comprobante is None:
        no_encontrado('El comprobante')
    return comprobante


# transferencias

@app.get('/transferencias', tags=['transferencias'], summary='Listado de transferencias')
def listar_transferencias(sala: int | None = None,
                          estado: str | None = Query(None, description='en_confeccion, terminado o procesado'),
                          pagina_nro: int = Query(1, alias='pagina', ge=1),
                          tamanio: int = Query(20, ge=1, le=100),
                          conn=Depends(obtener_conexion)):
    filas = datos.listar_transferencias(conn, sala, estado, tamanio, (pagina_nro - 1) * tamanio)
    return pagina(filas, pagina_nro, tamanio)


@app.post('/transferencias', tags=['transferencias'], status_code=201, summary='Crear una transferencia en confeccion')
def crear_transferencia(transferencia: TransferenciaEntrada, conn=Depends(obtener_conexion)):
    nro = datos.crear_transferencia(conn, transferencia.id_sala)
    return datos.obtener_transferencia(conn, nro)


@app.get('/transferencias/{nro}', tags=['transferencias'], summary='Transferencia con sus renglones')
def obtener_transferencia(nro: int, conn=Depends(obtener_conexion)):
    transferencia = datos.obtener_transferencia(conn, nro)
    if transferencia is None:
        no_encontrado('La transferencia')
    return transferencia


@app.post('/transferencias/{nro}/renglones', tags=['transferencias'], status_code=201,
          summary='Agregar un renglon mientras esta en confeccion')
def agregar_renglon_transferencia(nro: int, renglon: Renglon, conn=Depends(obtener_conexion)):
    datos.agregar_renglon_transferencia(conn, nro, renglon)
    return datos.obtener_transferencia(conn, nro)


@app.post('/transferencias/{nro}/terminar', tags=['transferencias'], summary='Pasar la transferencia a terminado')
def terminar_transferencia(nro: int, conn=Depends(obtener_conexion)):
    if not datos.terminar_transferencia(conn, nro):
        no_encontrado('La transferencia')
    return datos.obtener_transferencia(conn, nro)


@app.post('/transferencias/{nro}/procesar', tags=['transferencias'],
          summary='Procesar la transferencia: mueve el stock del deposito a la sala')
def procesar_transferencia(nro: int, conn=Depends(obtener_conexion)):
    datos.procesar_transferencia(conn, nro)
    return datos.obtener_transferencia(conn, nro)


# ingresos

@app.post('/ingresos', tags=['ingresos'], status_code=201, summary='Crear un ingreso en confeccion')
def crear_ingreso(ingreso: IngresoEntrada, conn=Depends(obtener_conexion)):
    cod = datos.crear_ingreso(conn, ingreso)
    return datos.obtener_ingreso(conn, cod)


@app.get('/ingresos/{cod}', tags=['ingresos'], summary='Ingreso con sus renglones')
def obtener_ingreso(cod: int, conn=Depends(obtener_conexion)):
    ingreso = datos.obtener_ingreso(conn, cod)
    if ingreso is None:
        no_encontrado('El ingreso')
    return ingreso


@app.post('/ingresos/{cod}/renglones', tags=['ingresos'], status_code=201,
          summary='Agregar un renglon mientras esta en confeccion')
def agregar_renglon_ingreso(cod: int, renglon: Renglon, conn=Depends(obtener_conexion)):
    datos.agregar_renglon_ingreso(conn, cod, renglon)
    return datos.obtener_ingreso(conn, cod)


@app.post('/ingresos/{cod}/terminar', tags=['ingresos'], summary='Pasar el ingreso a terminado')
def terminar_ingreso(cod: int, conn=Depends(obtener_conexion)):
    if not datos.terminar_ingreso(conn, cod):
        no_encontrado('El ingreso')
    return datos.obtener_ingreso(conn, cod)


@app.post('/ingresos/{cod}/procesar', tags=['ingresos'], summary='Procesar el ingreso: suma el stock al deposito')
def procesar_ingreso(cod: int, conn=Depends(obtener_conexion)):
    datos.procesar_ingreso(conn, cod)
    return datos.obtener_ingreso(conn, cod)
