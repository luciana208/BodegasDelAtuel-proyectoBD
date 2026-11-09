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


# clientes

def listar_clientes(conn, tipo, nombre, limite, desde):
    return conn.execute('''
        SELECT c.id_cliente, c.nombre, c.tipo_documento, c.nro_documento, c.tipo, c.descuento,
               l.nombre AS localidad, count(*) OVER () AS total_filas
          FROM cliente c
          JOIN localidad l ON l.id_localidad = c.id_localidad
         WHERE (%(tipo)s::tipo_cliente IS NULL OR c.tipo = %(tipo)s::tipo_cliente)
           AND (%(nombre)s::TEXT IS NULL OR c.nombre ILIKE '%%' || %(nombre)s::TEXT || '%%')
         ORDER BY c.id_cliente
         LIMIT %(limite)s OFFSET %(desde)s''',
        {'tipo': tipo, 'nombre': nombre, 'limite': limite, 'desde': desde}).fetchall()


def obtener_cliente(conn, id_cliente):
    cliente = conn.execute('''
        SELECT c.id_cliente, c.nombre, c.tipo_documento, c.nro_documento, c.direccion,
               c.id_localidad, l.nombre AS localidad, c.fecha_alta, c.tipo, c.descuento,
               s.nro_carnet, d.zona_cobertura, d.nro_habilitacion, e.pais_destino
          FROM cliente c
          JOIN localidad l ON l.id_localidad = c.id_localidad
          LEFT JOIN socio s ON s.id_cliente = c.id_cliente
          LEFT JOIN distribuidor d ON d.id_cliente = c.id_cliente
          LEFT JOIN exportador e ON e.id_cliente = c.id_cliente
         WHERE c.id_cliente = %s''', (id_cliente,)).fetchone()
    if cliente is None:
        return None
    cliente['permisos'] = conn.execute('''
        SELECT cod_permiso, fecha_emision, fecha_vencimiento
          FROM permiso_exportacion
         WHERE id_cliente = %s
         ORDER BY fecha_emision''', (id_cliente,)).fetchall()
    return cliente


def _guardar_subtipo(conn, id_cliente, cliente):
    if cliente.tipo == 'socio':
        conn.execute('INSERT INTO socio (id_cliente, nro_carnet) VALUES (%s, %s)', (id_cliente, cliente.nro_carnet))
    elif cliente.tipo == 'distribuidor':
        conn.execute('INSERT INTO distribuidor (id_cliente, zona_cobertura, nro_habilitacion) VALUES (%s, %s, %s)',
                     (id_cliente, cliente.zona_cobertura, cliente.nro_habilitacion))
    else:
        conn.execute('INSERT INTO exportador (id_cliente, pais_destino) VALUES (%s, %s)', (id_cliente, cliente.pais_destino))
        for permiso in cliente.permisos:
            conn.execute('''
                INSERT INTO permiso_exportacion (cod_permiso, id_cliente, fecha_emision, fecha_vencimiento)
                VALUES (%s, %s, %s, %s)''',
                (permiso.cod_permiso, id_cliente, permiso.fecha_emision, permiso.fecha_vencimiento))


def crear_cliente(conn, cliente):
    # el cliente y su subtipo se dan de alta juntos; el descuento lo pone el trigger segun el tipo
    with conn.transaction():
        id_cliente = conn.execute('''
            INSERT INTO cliente (nombre, tipo_documento, nro_documento, direccion, id_localidad, tipo)
            VALUES (%s, %s, %s, %s, %s, %s)
            RETURNING id_cliente''',
            (cliente.nombre, cliente.tipo_documento, cliente.nro_documento, cliente.direccion,
             cliente.id_localidad, cliente.tipo)).fetchone()['id_cliente']
        _guardar_subtipo(conn, id_cliente, cliente)
    return id_cliente


def actualizar_cliente(conn, id_cliente, cliente):
    # se reemplazan los datos del subtipo; si se intenta cambiar el tipo lo frena la fk compuesta
    with conn.transaction():
        fila = conn.execute('''
            UPDATE cliente
               SET nombre = %s, tipo_documento = %s, nro_documento = %s, direccion = %s,
                   id_localidad = %s, tipo = %s
             WHERE id_cliente = %s
            RETURNING id_cliente''',
            (cliente.nombre, cliente.tipo_documento, cliente.nro_documento, cliente.direccion,
             cliente.id_localidad, cliente.tipo, id_cliente)).fetchone()
        if fila is None:
            return False
        if cliente.tipo == 'socio':
            conn.execute('UPDATE socio SET nro_carnet = %s WHERE id_cliente = %s', (cliente.nro_carnet, id_cliente))
        elif cliente.tipo == 'distribuidor':
            conn.execute('UPDATE distribuidor SET zona_cobertura = %s, nro_habilitacion = %s WHERE id_cliente = %s',
                         (cliente.zona_cobertura, cliente.nro_habilitacion, id_cliente))
        else:
            conn.execute('UPDATE exportador SET pais_destino = %s WHERE id_cliente = %s', (cliente.pais_destino, id_cliente))
            conn.execute('DELETE FROM permiso_exportacion WHERE id_cliente = %s', (id_cliente,))
            for permiso in cliente.permisos:
                conn.execute('''
                    INSERT INTO permiso_exportacion (cod_permiso, id_cliente, fecha_emision, fecha_vencimiento)
                    VALUES (%s, %s, %s, %s)''',
                    (permiso.cod_permiso, id_cliente, permiso.fecha_emision, permiso.fecha_vencimiento))
    return True


def borrar_cliente(conn, id_cliente):
    # el subtipo y los permisos se borran por cascade; si tiene compras lo frena el restrict
    return conn.execute('DELETE FROM cliente WHERE id_cliente = %s', (id_cliente,)).rowcount > 0


# comprobantes

def crear_comprobante(conn, comprobante):
    # la venta completa en una transaccion: si un renglon no tiene stock se deshace todo
    with conn.transaction():
        nro = conn.execute('''
            INSERT INTO comprobante (id_cliente, id_sala) VALUES (%s, %s)
            RETURNING nro_comprobante''', (comprobante.id_cliente, comprobante.id_sala)).fetchone()['nro_comprobante']
        for renglon in comprobante.renglones:
            conn.execute('INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad) VALUES (%s, %s, %s)',
                         (nro, renglon.cod_vino, renglon.cantidad))
    return nro


def obtener_comprobante(conn, nro):
    comprobante = conn.execute('''
        SELECT c.nro_comprobante, c.fecha, c.id_cliente, cl.nombre AS cliente, cl.tipo AS tipo_cliente,
               c.id_sala, l.nombre AS localidad, c.subtotal, c.descuento, c.total
          FROM comprobante c
          JOIN cliente cl ON cl.id_cliente = c.id_cliente
          JOIN sala_venta s ON s.id_sala = c.id_sala
          JOIN localidad l ON l.id_localidad = s.id_localidad
         WHERE c.nro_comprobante = %s''', (nro,)).fetchone()
    if comprobante is None:
        return None
    comprobante['renglones'] = conn.execute('''
        SELECT r.cod_vino, v.nombre, v.anada, v.volumen_ml, r.cantidad, r.precio_unitario,
               r.porc_descuento, r.subtotal
          FROM renglon_comprobante r
          JOIN vino v ON v.cod_vino = r.cod_vino
         WHERE r.nro_comprobante = %s
         ORDER BY r.cod_vino''', (nro,)).fetchall()
    return comprobante


def salud(conn):
    return conn.execute('SELECT current_user AS usuario, current_database() AS base, version() AS version').fetchone()
