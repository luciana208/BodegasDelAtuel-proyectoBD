'''
configuracion de la api leida de variables de entorno.
si existe DATABASE_URL se usa tal cual (es lo que dan los proveedores en la nube);
si no, la cadena se arma con las variables DB_*.
'''
import os

from psycopg.conninfo import make_conninfo


def cadena_conexion():
    url = os.environ.get('DATABASE_URL')
    sslmode = os.environ.get('DB_SSLMODE')
    if url:
        # el sslmode de la url se respeta salvo que DB_SSLMODE diga otra cosa
        return make_conninfo(url, sslmode=sslmode) if sslmode else url
    return make_conninfo(
        host=os.environ.get('DB_HOST', 'localhost'),
        port=os.environ.get('DB_PORT', '5432'),
        dbname=os.environ.get('DB_NAME', 'bodegas'),
        user=os.environ.get('DB_USER', 'bodega_app'),
        password=os.environ.get('DB_PASSWORD', ''),
        sslmode=sslmode or 'prefer',
    )


def origenes_cors():
    # lista separada por comas, por ejemplo http://localhost:8080,https://front.ejemplo.com
    valor = os.environ.get('CORS_ORIGINS', 'http://localhost:8080')
    return [o.strip() for o in valor.split(',') if o.strip()]


POOL_MIN = int(os.environ.get('DB_POOL_MIN', '1'))
POOL_MAX = int(os.environ.get('DB_POOL_MAX', '10'))
