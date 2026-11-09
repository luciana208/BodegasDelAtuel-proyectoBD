'''
traduccion central de los errores de postgresql a respuestas http segun el sqlstate.
el mensaje de la base (por ejemplo el del RAISE EXCEPTION de un trigger) se devuelve tal cual
'''
import psycopg
from fastapi import Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

CODIGOS_HTTP = {
    '23505': 409,  # unique violado
    '23503': 409,  # foreign key violada
    '23514': 422,  # check violado
    '23502': 422,  # not null violado
    'P0001': 409,  # regla rechazada por un trigger o procedimiento
    '22P02': 400,  # texto con formato invalido para el tipo
    '22003': 422,  # numero fuera de rango
    '22007': 400,  # fecha con formato invalido
    '22008': 400,  # fecha fuera de rango
    '40001': 503,  # fallo de serializacion
    '40P01': 503,  # deadlock
}


async def manejar_error_base(request: Request, exc: psycopg.Error):
    sqlstate = exc.sqlstate
    estado = CODIGOS_HTTP.get(sqlstate, 500)
    cuerpo = {
        'error': exc.diag.message_primary or str(exc),
        'sqlstate': sqlstate,
    }
    if exc.diag.message_detail:
        cuerpo['detalle'] = exc.diag.message_detail
    if exc.diag.constraint_name:
        cuerpo['restriccion'] = exc.diag.constraint_name
    encabezados = {}
    if estado == 503:
        cuerpo['reintentar'] = True
        encabezados['Retry-After'] = '1'
    if estado == 500:
        cuerpo = {'error': 'Error interno de la base de datos', 'sqlstate': sqlstate}
    return JSONResponse(status_code=estado, content=cuerpo, headers=encabezados)


async def manejar_error_validacion(request: Request, exc: RequestValidationError):
    # errores de formato del pedido (tipos, campos que faltan) antes de llegar a la base
    detalles = []
    for e in exc.errors():
        campo = '.'.join(str(p) for p in e['loc'] if p != 'body')
        detalles.append(f'{campo}: {e["msg"]}')
    return JSONResponse(status_code=422, content={'error': 'Datos con formato invalido', 'detalle': '; '.join(detalles)})


async def manejar_error_http(request: Request, exc):
    # mismo formato que los errores de la base, por ejemplo un recurso que no existe
    return JSONResponse(status_code=exc.status_code, content={'error': exc.detail})
