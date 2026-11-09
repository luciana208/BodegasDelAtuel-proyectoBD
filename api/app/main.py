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
from .modelos import Corte, VinoEntrada


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
