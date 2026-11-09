'''
capa de acceso a datos: una funcion por consulta, todas con parametros (%s o %(nombre)s),
nunca con texto del usuario pegado en el sql. los importes, descuentos y stock los
calculan las funciones y triggers de la base; aca solo se leen.
'''


def salud(conn):
    return conn.execute('SELECT current_user AS usuario, current_database() AS base, version() AS version').fetchone()
