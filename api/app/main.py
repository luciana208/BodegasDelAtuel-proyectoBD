'''
api rest de bodegas del atuel. los controladores solo reciben el pedido, llaman a una
funcion del modulo de datos y devuelven el resultado.
'''
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI
from fastapi.middleware.cors import CORSMiddleware

from . import datos
from .config import origenes_cors
from .db import obtener_conexion, pool


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


# salud

@app.get('/salud', tags=['salud'], summary='Estado de la API y de la base')
def salud(conn=Depends(obtener_conexion)):
    fila = datos.salud(conn)
    return {'estado': 'ok', **fila}
