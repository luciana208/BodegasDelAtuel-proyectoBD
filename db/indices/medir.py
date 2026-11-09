'''
mide las consultas con EXPLAIN (ANALYZE, BUFFERS) sin los indices de 008_indices.sql
y con ellos, y guarda los planes y una tabla comparativa en docs/resultados/indices.
tambien mide el costo de escritura, los indices descartados y un caso en que el
planificador no usa un indice que existe. al terminar la base queda con los indices.
'''
import json
import os
import re
import statistics
import time

import psycopg

RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SALIDA = os.path.join(RAIZ, 'docs', 'resultados', 'indices')
ARCHIVO_INDICES = os.path.join(RAIZ, 'db', 'migrations', '008_indices.sql')
REPETICIONES = 5
LIMITE = '180s'

CONSULTAS = [
    ('S1', 'ranking de los 10 vinos con mas botellas vendidas', '''
SELECT v.cod_vino, v.nombre, SUM(r.cantidad) AS botellas
  FROM renglon_comprobante r
  JOIN vino v ON v.cod_vino = r.cod_vino
 GROUP BY v.cod_vino, v.nombre
 ORDER BY botellas DESC
 LIMIT 10'''),
    ('S3', 'clientes de cada tipo que compraron en la sala 1 en la ultima semana', '''
SELECT cl.tipo, count(DISTINCT cl.id_cliente) AS clientes
  FROM comprobante c
  JOIN cliente cl ON cl.id_cliente = c.id_cliente
 WHERE c.id_sala = 1
   AND c.fecha > CURRENT_DATE - 7
 GROUP BY cl.tipo'''),
    ('S4', 'top 5 de salas que pidieron el vino 224 por transferencias en los ultimos 15 dias', '''
SELECT t.id_sala, SUM(r.cantidad) AS botellas
  FROM transferencia t
  JOIN renglon_transferencia r ON r.nro_transferencia = t.nro_transferencia
 WHERE r.cod_vino = 224
   AND t.fecha_confeccion >= CURRENT_DATE - 15
 GROUP BY t.id_sala
 ORDER BY botellas DESC
 LIMIT 5'''),
    ('S8', 'monto de ventas por sala en el ultimo trimestre', '''
SELECT c.id_sala, SUM(c.total) AS monto
  FROM comprobante c
 WHERE c.fecha >= CURRENT_DATE - INTERVAL '3 months'
 GROUP BY c.id_sala
 ORDER BY monto DESC'''),
    ('S12', 'clientes que compraron todos los vinos de la Bodega Boutique Cordoba', '''
SELECT cl.id_cliente, cl.nombre
  FROM cliente cl
 WHERE NOT EXISTS (
       SELECT 1
         FROM vino v
         JOIN bodega b ON b.cuit = v.cuit_bodega
        WHERE b.razon_social = 'Bodega Boutique Cordoba'
          AND NOT EXISTS (
              SELECT 1
                FROM comprobante c
                JOIN renglon_comprobante r ON r.nro_comprobante = c.nro_comprobante
               WHERE c.id_cliente = cl.id_cliente
                 AND r.cod_vino = v.cod_vino))'''),
]

# indices que evaluamos y no quedaron en 008: nombre, sentencia, consulta de prueba,
# indice de 008 que se quita mientras se prueba y descripcion
VENTAS_SALA_ANIO = """
SELECT count(*) AS comprobantes, SUM(total) AS monto
  FROM comprobante
 WHERE id_sala = 1
   AND fecha >= CURRENT_DATE - INTERVAL '1 year'"""
SOCIOS = "SELECT id_cliente, nombre FROM cliente WHERE tipo = 'socio'"
DESCARTADOS = [
    ('idx_comprobante_fecha_btree', 'CREATE INDEX idx_comprobante_fecha_btree ON comprobante (fecha)',
     CONSULTAS[3][2], 'idx_comprobante_fecha_brin', 'b-tree sobre la fecha en lugar del brin, probado con S8'),
    ('idx_comprobante_fecha_sala', 'CREATE INDEX idx_comprobante_fecha_sala ON comprobante (fecha, id_sala)',
     VENTAS_SALA_ANIO, 'idx_comprobante_sala_fecha',
     'compuesto con las columnas al reves, probado con las ventas de la sala 1 del ultimo anio'),
    ('idx_cliente_tipo', 'CREATE INDEX idx_cliente_tipo ON cliente (tipo)',
     SOCIOS, None, 'indice sobre el tipo de cliente, probado trayendo los socios'),
]


def nombres_indices():
    texto = open(ARCHIVO_INDICES, encoding='utf-8').read()
    return re.findall(r'CREATE INDEX (\w+)', texto)


def recorridos(nodo, lista):
    # junta los nodos que leen tablas o indices con las filas que leyeron
    tipo = nodo['Node Type']
    if 'Scan' in tipo:
        loops = nodo.get('Actual Loops', 1)
        leidas = (nodo.get('Actual Rows', 0) + nodo.get('Rows Removed by Filter', 0)
                  + nodo.get('Rows Removed by Index Recheck', 0)) * loops
        objeto = nodo.get('Index Name') or nodo.get('Relation Name') or ''
        lista.append((tipo, objeto, int(leidas)))
    for hijo in nodo.get('Plans', []):
        recorridos(hijo, lista)
    return lista


def medir(cur, sql):
    tiempos = []
    plan = None
    for _ in range(REPETICIONES):
        cur.execute('EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' + sql)
        plan = cur.fetchone()[0][0]
        tiempos.append(plan['Execution Time'])
        # una consulta de varios segundos no se repite
        if plan['Execution Time'] > 5000:
            break
    raiz = plan['Plan']
    nodos = recorridos(raiz, [])
    buffers = raiz.get('Shared Hit Blocks', 0) + raiz.get('Shared Read Blocks', 0)
    if plan['Execution Time'] > 5000:
        texto = json.dumps(plan, indent=2)
    else:
        cur.execute('EXPLAIN (ANALYZE, BUFFERS) ' + sql)
        texto = '\n'.join(fila[0] for fila in cur.fetchall())
    return {'tiempo': statistics.median(tiempos), 'nodos': nodos, 'buffers': buffers, 'texto': texto,
            'filas_leidas': sum(n[2] for n in nodos)}


def medir_con_limite(cur, sql):
    # si la consulta supera el limite se guarda el plan estimado sin ejecutar
    try:
        return medir(cur, sql)
    except psycopg.errors.QueryCanceled:
        cur.execute('EXPLAIN ' + sql)
        texto = '\n'.join(fila[0] for fila in cur.fetchall())
        return {'tiempo': None, 'nodos': [], 'buffers': None, 'filas_leidas': None,
                'texto': f'la consulta supero {LIMITE} y se cancelo; plan estimado sin ejecutar:\n' + texto}


def resumen_recorridos(nodos):
    vistos = []
    for tipo, objeto, _ in nodos:
        texto = f'{tipo} {objeto}'.strip()
        if texto not in vistos:
            vistos.append(texto)
    return ', '.join(vistos)


def formato_tiempo(t):
    return f'mas de {LIMITE}' if t is None else f'{t:.2f} ms'


def medir_todas(cur, momento):
    resultados = {}
    with open(os.path.join(SALIDA, f'planes_{momento}.txt'), 'w', encoding='utf-8') as f:
        for codigo, descripcion, sql in CONSULTAS:
            r = medir_con_limite(cur, sql)
            resultados[codigo] = r
            f.write(f'{codigo}: {descripcion}\n{sql.strip()}\n\n{r["texto"]}\n\n\n')
    return resultados


def copiar_tablas(cur):
    # carga masiva de copias de las dos tablas grandes con los indices que existan en ese momento
    tiempos = {}
    for tabla, columnas in [('comprobante', 'nro_comprobante'), ('renglon_comprobante', None)]:
        cur.execute(f'DROP TABLE IF EXISTS copia_{tabla}')
        cur.execute(f'CREATE TABLE copia_{tabla} (LIKE {tabla} INCLUDING ALL)')
        inicio = time.perf_counter()
        sobre = 'OVERRIDING SYSTEM VALUE ' if columnas else ''
        cur.execute(f'INSERT INTO copia_{tabla} {sobre}SELECT * FROM {tabla}')
        tiempos[tabla] = (time.perf_counter() - inicio, cur.rowcount)
        cur.execute(f'DROP TABLE copia_{tabla}')
    return tiempos


def main():
    os.makedirs(SALIDA, exist_ok=True)
    indices = nombres_indices()
    informe = []
    with psycopg.connect('', autocommit=True) as conn:
        cur = conn.cursor()
        cur.execute(f"SET statement_timeout = '{LIMITE}'")

        # antes: solo las claves primarias y los unique
        for nombre in indices + [d[0] for d in DESCARTADOS]:
            cur.execute(f'DROP INDEX IF EXISTS {nombre}')
        cur.execute('ANALYZE')
        antes = medir_todas(cur, 'antes')
        escritura_antes = copiar_tablas(cur)

        # se crean los indices de 008 midiendo cuanto tarda cada uno
        creacion = []
        texto = open(ARCHIVO_INDICES, encoding='utf-8').read()
        for sentencia in re.findall(r'CREATE INDEX .*?;', texto, re.S):
            nombre = re.search(r'CREATE INDEX (\w+)', sentencia).group(1)
            inicio = time.perf_counter()
            cur.execute(sentencia)
            demora = time.perf_counter() - inicio
            cur.execute('SELECT pg_size_pretty(pg_relation_size(%s::regclass))', (nombre,))
            creacion.append((nombre, demora, cur.fetchone()[0]))
        cur.execute('ANALYZE')
        despues = medir_todas(cur, 'despues')
        escritura_despues = copiar_tablas(cur)

        informe.append('comparacion antes y despues de 008_indices.sql')
        informe.append(f'mediana de {REPETICIONES} ejecuciones de EXPLAIN (ANALYZE, BUFFERS) con la cache caliente')
        informe.append('')
        informe.append('| Consulta | Tiempo antes | Tiempo despues | Mejora | Recorridos antes | Recorridos despues | Filas leidas antes | Filas leidas despues | Buffers antes | Buffers despues |')
        informe.append('|---|---|---|---|---|---|---|---|---|---|')
        for codigo, _, _ in CONSULTAS:
            a, d = antes[codigo], despues[codigo]
            if a['tiempo'] is None:
                mejora = 'mas de ' + str(int(float(LIMITE[:-1]) * 1000 / d['tiempo'])) + ' veces'
            else:
                mejora = f'{a["tiempo"] / d["tiempo"]:.1f} veces'
            informe.append(f'| {codigo} | {formato_tiempo(a["tiempo"])} | {formato_tiempo(d["tiempo"])} | {mejora} | '
                           f'{resumen_recorridos(a["nodos"]) or "-"} | {resumen_recorridos(d["nodos"])} | '
                           f'{a["filas_leidas"] if a["filas_leidas"] is not None else "-"} | {d["filas_leidas"]} | '
                           f'{a["buffers"] if a["buffers"] is not None else "-"} | {d["buffers"]} |')
        informe.append('')
        informe.append('creacion de los indices de 008')
        informe.append('| Indice | Tiempo de creacion | Tamanio |')
        informe.append('|---|---|---|')
        for nombre, demora, tam in creacion:
            informe.append(f'| {nombre} | {demora:.2f} s | {tam} |')
        informe.append('')
        informe.append('costo de escritura: INSERT ... SELECT de toda la tabla en una copia con los mismos indices')
        informe.append('| Tabla | Filas | Sin los indices de 008 | Con los indices de 008 | Diferencia |')
        informe.append('|---|---|---|---|---|')
        for tabla in escritura_antes:
            ta, filas = escritura_antes[tabla]
            td, _ = escritura_despues[tabla]
            informe.append(f'| {tabla} | {filas} | {ta:.2f} s | {td:.2f} s | {100 * (td - ta) / ta:+.0f} % |')
        informe.append('')

        # indices descartados: se mide con el indice de 008, se lo cambia por el candidato y se vuelve a medir
        informe.append('indices evaluados y descartados')
        with open(os.path.join(SALIDA, 'planes_descartados.txt'), 'w', encoding='utf-8') as f:
            for nombre, sentencia, sql, quitar, descripcion in DESCARTADOS:
                con_008 = medir(cur, sql)
                if quitar:
                    cur.execute(f'DROP INDEX {quitar}')
                cur.execute(sentencia)
                cur.execute('ANALYZE')
                cur.execute('SELECT pg_size_pretty(pg_relation_size(%s::regclass))', (nombre,))
                tam = cur.fetchone()[0]
                r = medir(cur, sql)
                usado = nombre in r['texto']
                informe.append(f'- {nombre}: {descripcion}. tamanio {tam}')
                informe.append(f'  con los indices de 008: {con_008["tiempo"]:.2f} ms, {resumen_recorridos(con_008["nodos"])}, '
                               f'filas leidas {con_008["filas_leidas"]}, buffers {con_008["buffers"]}')
                informe.append(f'  con {nombre}: {r["tiempo"]:.2f} ms, {resumen_recorridos(r["nodos"])}, '
                               f'filas leidas {r["filas_leidas"]}, buffers {r["buffers"]}, lo usa el planificador: {"si" if usado else "no"}')
                f.write(f'{nombre}\n{sql.strip()}\n\ncon los indices de 008\n{con_008["texto"]}\n\ncon {nombre}\n{r["texto"]}\n\n\n')
                cur.execute(f'DROP INDEX {nombre}')
                if quitar:
                    sentencia_008 = re.search(rf'CREATE INDEX {quitar} .*?;', texto, re.S).group(0)
                    cur.execute(sentencia_008)
                cur.execute('ANALYZE')
        informe.append('')

        # caso en que el planificador no usa un indice que existe
        sql = 'SELECT id_sala, count(*), SUM(total) FROM comprobante WHERE id_sala BETWEEN 2 AND 30 GROUP BY id_sala'
        normal = medir(cur, sql)
        cur.execute('SET enable_seqscan = off')
        forzado = medir(cur, sql)
        cur.execute('RESET enable_seqscan')
        cur.execute('SELECT round(100.0 * count(*) FILTER (WHERE id_sala BETWEEN 2 AND 30) / count(*), 1) FROM comprobante')
        porcentaje = cur.fetchone()[0]
        informe.append('caso en que el planificador no usa un indice existente')
        informe.append(f'  {sql}')
        informe.append(f'  la condicion deja pasar el {porcentaje} % de los comprobantes')
        informe.append(f'  plan elegido: {resumen_recorridos(normal["nodos"])}, {normal["tiempo"]:.2f} ms')
        informe.append(f'  forzando el indice con enable_seqscan = off: {resumen_recorridos(forzado["nodos"])}, {forzado["tiempo"]:.2f} ms')
        with open(os.path.join(SALIDA, 'planes_no_usa_indice.txt'), 'w', encoding='utf-8') as f:
            f.write(f'{sql}\n\nplan elegido por el planificador\n{normal["texto"]}\n\n'
                    f'con enable_seqscan = off\n{forzado["texto"]}\n')

    texto = '\n'.join(informe) + '\n'
    print(texto)
    with open(os.path.join(SALIDA, 'comparacion.md'), 'w', encoding='utf-8') as f:
        f.write(texto)


if __name__ == '__main__':
    main()
