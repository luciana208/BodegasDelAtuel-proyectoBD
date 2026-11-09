'''
capa de acceso a datos: una funcion por consulta, todas con parametros (%s o %(nombre)s),
nunca con texto del usuario pegado en el sql. los importes, descuentos y stock los
calculan las funciones y triggers de la base; aca solo se leen.
'''

# catalogos

def listar_cepas(conn):
    return conn.execute('SELECT id_cepa, nombre, tipo FROM cepa ORDER BY nombre').fetchall()


def listar_bodegas(conn):
    return conn.execute('SELECT cuit, razon_social, domicilio FROM bodega ORDER BY razon_social').fetchall()


def listar_maridajes(conn):
    return conn.execute('SELECT id_maridaje, nombre, temperatura_servicio FROM maridaje ORDER BY nombre').fetchall()


def listar_salas(conn):
    return conn.execute('''
        SELECT s.id_sala, s.calle, s.numero, s.dia_cierre, l.nombre AS localidad
          FROM sala_venta s
          JOIN localidad l ON l.id_localidad = s.id_localidad
         ORDER BY s.id_sala''').fetchall()


def listar_localidades(conn):
    return conn.execute('''
        SELECT l.id_localidad, l.nombre, l.cod_postal, d.nombre AS departamento, d.provincia
          FROM localidad l
          JOIN departamento d ON d.id_departamento = l.id_departamento
         ORDER BY l.nombre''').fetchall()


def listar_transportistas(conn):
    return conn.execute('SELECT cod_transporte, razon_social, cuit FROM transportista ORDER BY razon_social').fetchall()


# vinos

def listar_vinos(conn, tipo, cepa, bodega, anada, nombre, limite, desde):
    return conn.execute('''
        SELECT v.cod_vino, v.nombre, v.tipo, v.anada, v.volumen_ml, v.graduacion, v.precio,
               v.cuit_bodega, b.razon_social AS bodega,
               count(*) OVER () AS total_filas
          FROM vino v
          JOIN bodega b ON b.cuit = v.cuit_bodega
         WHERE (%(tipo)s::tipo_vino IS NULL OR v.tipo = %(tipo)s::tipo_vino)
           AND (%(bodega)s::TEXT IS NULL OR v.cuit_bodega = %(bodega)s::TEXT)
           AND (%(anada)s::INTEGER IS NULL OR v.anada = %(anada)s::INTEGER)
           AND (%(nombre)s::TEXT IS NULL OR v.nombre ILIKE '%%' || %(nombre)s::TEXT || '%%')
           AND (%(cepa)s::INTEGER IS NULL OR EXISTS (
                SELECT 1 FROM composicion c
                 WHERE c.cod_vino = v.cod_vino AND c.id_cepa = %(cepa)s::INTEGER))
         ORDER BY v.nombre, v.anada, v.volumen_ml
         LIMIT %(limite)s OFFSET %(desde)s''',
        {'tipo': tipo, 'cepa': cepa, 'bodega': bodega, 'anada': anada, 'nombre': nombre,
         'limite': limite, 'desde': desde}).fetchall()


def obtener_vino(conn, cod_vino):
    vino = conn.execute('''
        SELECT v.cod_vino, v.nombre, v.tipo, v.anada, v.volumen_ml, v.graduacion, v.precio,
               v.cuit_bodega, b.razon_social AS bodega,
               s.stock_deposito, s.stock_salas, s.stock_total
          FROM vino v
          JOIN bodega b ON b.cuit = v.cuit_bodega
          JOIN v_stock_total_vino s ON s.cod_vino = v.cod_vino
         WHERE v.cod_vino = %s''', (cod_vino,)).fetchone()
    if vino is None:
        return None
    vino['composicion'] = conn.execute('''
        SELECT c.id_cepa, ce.nombre AS cepa, ce.tipo, c.porcentaje
          FROM composicion c
          JOIN cepa ce ON ce.id_cepa = c.id_cepa
         WHERE c.cod_vino = %s
         ORDER BY c.porcentaje DESC, ce.nombre''', (cod_vino,)).fetchall()
    vino['maridajes'] = conn.execute('''
        SELECT m.id_maridaje, m.nombre, m.temperatura_servicio
          FROM vino_maridaje vm
          JOIN maridaje m ON m.id_maridaje = vm.id_maridaje
         WHERE vm.cod_vino = %s
         ORDER BY m.nombre''', (cod_vino,)).fetchall()
    return vino


def _guardar_composicion_y_maridajes(conn, cod_vino, vino):
    for corte in vino.composicion:
        conn.execute('INSERT INTO composicion (cod_vino, id_cepa, porcentaje) VALUES (%s, %s, %s)',
                     (cod_vino, corte.id_cepa, corte.porcentaje))
    for id_maridaje in vino.maridajes:
        conn.execute('INSERT INTO vino_maridaje (cod_vino, id_maridaje) VALUES (%s, %s)', (cod_vino, id_maridaje))


def crear_vino(conn, vino):
    # el constraint trigger diferido revisa que el corte sume 100 al hacer commit
    with conn.transaction():
        cod_vino = conn.execute('''
            INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
            RETURNING cod_vino''',
            (vino.nombre, vino.tipo, vino.anada, vino.volumen_ml, vino.graduacion, vino.precio,
             vino.cuit_bodega)).fetchone()['cod_vino']
        _guardar_composicion_y_maridajes(conn, cod_vino, vino)
    return cod_vino


def actualizar_vino(conn, cod_vino, vino):
    # si cambia el precio, el trigger de auditoria lo registra
    with conn.transaction():
        fila = conn.execute('''
            UPDATE vino
               SET nombre = %s, tipo = %s, anada = %s, volumen_ml = %s, graduacion = %s,
                   precio = %s, cuit_bodega = %s
             WHERE cod_vino = %s
            RETURNING cod_vino''',
            (vino.nombre, vino.tipo, vino.anada, vino.volumen_ml, vino.graduacion, vino.precio,
             vino.cuit_bodega, cod_vino)).fetchone()
        if fila is None:
            return False
        conn.execute('DELETE FROM composicion WHERE cod_vino = %s', (cod_vino,))
        conn.execute('DELETE FROM vino_maridaje WHERE cod_vino = %s', (cod_vino,))
        _guardar_composicion_y_maridajes(conn, cod_vino, vino)
    return True


def borrar_vino(conn, cod_vino):
    return conn.execute('DELETE FROM vino WHERE cod_vino = %s', (cod_vino,)).rowcount > 0


def salud(conn):
    return conn.execute('SELECT current_user AS usuario, current_database() AS base, version() AS version').fetchone()
