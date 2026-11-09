'''
pool de conexiones a la base. las conexiones trabajan en autocommit, asi cada sentencia
suelta es su propia transaccion; cuando una operacion tiene varias sentencias se abre
una transaccion explicita con conn.transaction() en el modulo de datos
'''
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

from .config import POOL_MAX, POOL_MIN, cadena_conexion

pool = ConnectionPool(
    cadena_conexion(),
    min_size=POOL_MIN,
    max_size=POOL_MAX,
    kwargs={'autocommit': True, 'row_factory': dict_row},
    open=False,
)


def obtener_conexion():
    # dependencia de fastapi: presta una conexion del pool durante el pedido
    with pool.connection() as conn:
        yield conn
