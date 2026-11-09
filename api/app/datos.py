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


# transferencias

def listar_transferencias(conn, id_sala, estado, limite, desde):
    return conn.execute('''
        SELECT t.nro_transferencia, t.id_sala, l.nombre AS localidad, t.fecha_confeccion, t.estado,
               (SELECT count(*) FROM renglon_transferencia r WHERE r.nro_transferencia = t.nro_transferencia) AS renglones,
               count(*) OVER () AS total_filas
          FROM transferencia t
          JOIN sala_venta s ON s.id_sala = t.id_sala
          JOIN localidad l ON l.id_localidad = s.id_localidad
         WHERE (%(sala)s::INTEGER IS NULL OR t.id_sala = %(sala)s::INTEGER)
           AND (%(estado)s::estado_documento IS NULL OR t.estado = %(estado)s::estado_documento)
         ORDER BY t.nro_transferencia DESC
         LIMIT %(limite)s OFFSET %(desde)s''',
        {'sala': id_sala, 'estado': estado, 'limite': limite, 'desde': desde}).fetchall()


def crear_transferencia(conn, id_sala):
    # la fecha de confeccion la fuerza el trigger y el estado arranca en confeccion
    return conn.execute('INSERT INTO transferencia (id_sala) VALUES (%s) RETURNING nro_transferencia',
                        (id_sala,)).fetchone()['nro_transferencia']


def obtener_transferencia(conn, nro):
    transferencia = conn.execute('''
        SELECT t.nro_transferencia, t.id_sala, l.nombre AS localidad, t.fecha_confeccion, t.estado
          FROM transferencia t
          JOIN sala_venta s ON s.id_sala = t.id_sala
          JOIN localidad l ON l.id_localidad = s.id_localidad
         WHERE t.nro_transferencia = %s''', (nro,)).fetchone()
    if transferencia is None:
        return None
    transferencia['renglones'] = conn.execute('''
        SELECT r.cod_vino, v.nombre, v.anada, v.volumen_ml, r.cantidad,
               COALESCE(d.cantidad, 0) AS stock_deposito
          FROM renglon_transferencia r
          JOIN vino v ON v.cod_vino = r.cod_vino
          LEFT JOIN stock_deposito d ON d.cod_vino = r.cod_vino
         WHERE r.nro_transferencia = %s
         ORDER BY r.cod_vino''', (nro,)).fetchall()
    return transferencia


def agregar_renglon_transferencia(conn, nro, renglon):
    conn.execute('INSERT INTO renglon_transferencia (nro_transferencia, cod_vino, cantidad) VALUES (%s, %s, %s)',
                 (nro, renglon.cod_vino, renglon.cantidad))


def terminar_transferencia(conn, nro):
    # el trigger de estados valida la transicion
    return conn.execute("UPDATE transferencia SET estado = 'terminado' WHERE nro_transferencia = %s",
                        (nro,)).rowcount > 0


def procesar_transferencia(conn, nro):
    conn.execute('CALL sp_procesar_transferencia(%s)', (nro,))


# ingresos

def crear_ingreso(conn, ingreso):
    return conn.execute('INSERT INTO ingreso (cod_transporte, cuit_bodega) VALUES (%s, %s) RETURNING cod_ingreso',
                        (ingreso.cod_transporte, ingreso.cuit_bodega)).fetchone()['cod_ingreso']


def obtener_ingreso(conn, cod):
    ingreso = conn.execute('''
        SELECT i.cod_ingreso, i.fecha, i.estado, i.cod_transporte, t.razon_social AS transportista,
               i.cuit_bodega, b.razon_social AS bodega
          FROM ingreso i
          JOIN transportista t ON t.cod_transporte = i.cod_transporte
          JOIN bodega b ON b.cuit = i.cuit_bodega
         WHERE i.cod_ingreso = %s''', (cod,)).fetchone()
    if ingreso is None:
        return None
    ingreso['renglones'] = conn.execute('''
        SELECT r.cod_vino, v.nombre, v.anada, v.volumen_ml, r.cantidad
          FROM renglon_ingreso r
          JOIN vino v ON v.cod_vino = r.cod_vino
         WHERE r.cod_ingreso = %s
         ORDER BY r.cod_vino''', (cod,)).fetchall()
    return ingreso


def agregar_renglon_ingreso(conn, cod, renglon):
    conn.execute('INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad) VALUES (%s, %s, %s)',
                 (cod, renglon.cod_vino, renglon.cantidad))


def terminar_ingreso(conn, cod):
    return conn.execute("UPDATE ingreso SET estado = 'terminado' WHERE cod_ingreso = %s", (cod,)).rowcount > 0


def procesar_ingreso(conn, cod):
    conn.execute('CALL sp_procesar_ingreso(%s)', (cod,))


# reportes

def top_vinos(conn, limite):
    return conn.execute('''
        SELECT v.cod_vino, v.nombre, v.anada, v.volumen_ml, SUM(r.cantidad) AS botellas
          FROM renglon_comprobante r
          JOIN vino v ON v.cod_vino = r.cod_vino
         GROUP BY v.cod_vino, v.nombre, v.anada, v.volumen_ml
         ORDER BY botellas DESC
         LIMIT %s''', (limite,)).fetchall()


def ventas_por_sala(conn, meses):
    return conn.execute('''
        SELECT c.id_sala, l.nombre AS localidad, count(*) AS comprobantes, SUM(c.total) AS monto
          FROM comprobante c
          JOIN sala_venta s ON s.id_sala = c.id_sala
          JOIN localidad l ON l.id_localidad = s.id_localidad
         WHERE c.fecha >= CURRENT_DATE - make_interval(months => %s)
         GROUP BY c.id_sala, l.nombre
         ORDER BY monto DESC''', (meses,)).fetchall()


def vinos_sin_stock(conn, id_sala):
    return conn.execute('''
        SELECT v.cod_vino, v.nombre, v.anada, v.volumen_ml, d.cantidad AS stock_deposito
          FROM vino v
          JOIN stock_deposito d ON d.cod_vino = v.cod_vino
         WHERE d.cantidad > 0
           AND NOT EXISTS (SELECT 1 FROM stock_sala s
                            WHERE s.id_sala = %s AND s.cod_vino = v.cod_vino AND s.cantidad > 0)
         ORDER BY v.nombre, v.anada''', (id_sala,)).fetchall()


def transportista_activo(conn):
    return conn.execute('''
        WITH actividad AS (
          SELECT t.cod_transporte, t.razon_social, count(DISTINCT i.cod_ingreso) AS ingresos,
                 COALESCE(SUM(r.cantidad), 0) AS botellas
            FROM transportista t
            JOIN ingreso i ON i.cod_transporte = t.cod_transporte
            LEFT JOIN renglon_ingreso r ON r.cod_ingreso = i.cod_ingreso
           WHERE i.fecha >= CURRENT_DATE - INTERVAL '1 month'
           GROUP BY t.cod_transporte, t.razon_social)
        SELECT * FROM actividad
         WHERE ingresos = (SELECT max(ingresos) FROM actividad)
         ORDER BY botellas DESC''').fetchall()


def trazabilidad_vino(conn, cod_vino):
    # recorrido de un vino: de que bodega viene, por que ingresos entro, a que salas se transfirio y donde se vendio
    vino = obtener_vino(conn, cod_vino)
    if vino is None:
        return None
    vino['ingresos'] = conn.execute('''
        SELECT i.cod_ingreso, i.fecha, i.estado, t.razon_social AS transportista, r.cantidad
          FROM renglon_ingreso r
          JOIN ingreso i ON i.cod_ingreso = r.cod_ingreso
          JOIN transportista t ON t.cod_transporte = i.cod_transporte
         WHERE r.cod_vino = %s
         ORDER BY i.fecha, i.cod_ingreso''', (cod_vino,)).fetchall()
    vino['transferencias'] = conn.execute('''
        SELECT t.nro_transferencia, t.fecha_confeccion, t.estado, t.id_sala, r.cantidad
          FROM renglon_transferencia r
          JOIN transferencia t ON t.nro_transferencia = r.nro_transferencia
         WHERE r.cod_vino = %s
         ORDER BY t.fecha_confeccion, t.nro_transferencia''', (cod_vino,)).fetchall()
    vino['ventas_por_sala'] = conn.execute('''
        SELECT c.id_sala, l.nombre AS localidad, SUM(r.cantidad) AS botellas,
               fn_stock_sala(c.id_sala, %(vino)s) AS stock_actual
          FROM renglon_comprobante r
          JOIN comprobante c ON c.nro_comprobante = r.nro_comprobante
          JOIN sala_venta s ON s.id_sala = c.id_sala
          JOIN localidad l ON l.id_localidad = s.id_localidad
         WHERE r.cod_vino = %(vino)s
         GROUP BY c.id_sala, l.nombre
         ORDER BY botellas DESC''', {'vino': cod_vino}).fetchall()
    return vino


def salud(conn):
    return conn.execute('''
        SELECT current_user AS usuario, current_database() AS base, version() AS version,
               (SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid()) AS ssl''').fetchone()
