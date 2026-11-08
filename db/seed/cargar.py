'''
carga masiva de bodegas del atuel.

genera datos coherentes con random y faker a partir de una semilla fija. las fechas
se calculan desde la fecha base (por defecto el dia en que se corre), asi siempre hay
datos de la ultima semana, del ultimo mes y de hace mas de cinco anios.

el orden de generacion sigue la historia real: primero los ingresos al deposito, despues
las transferencias a las salas y por ultimo las ventas. las cantidades de los ingresos y
de las transferencias se calculan al final a partir de lo que se vendio, asi el stock
nunca queda negativo en ningun momento.

la carga se hace con copy y con los triggers deshabilitados.
'''
import bisect
import csv
import os
import random
import time
from datetime import date, datetime, timedelta
from decimal import Decimal, ROUND_HALF_UP

import psycopg
from faker import Faker

inicio_global = time.perf_counter()

SEMILLA = int(os.environ.get('SEMILLA', '2026'))
FECHA_BASE = os.environ.get('FECHA_BASE') or date.today().isoformat()
RESULTADOS = os.environ.get('RESULTADOS', '/resultados')
CATALOGOS = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'catalogos')

CANT_CLIENTES = 20000
CANT_COMPROBANTES = 150000
CANT_INGRESOS = 2000
TRANSFERENCIAS_POR_SALA = 100

HOY = date.fromisoformat(FECHA_BASE)
ANIO = HOY.year
# ventana de ventas: los ultimos seis anios
INICIO_VENTAS = HOY - timedelta(days=6 * 365)
INICIO_TRANSFERENCIAS = INICIO_VENTAS - timedelta(days=60)
INICIO_INGRESOS = INICIO_VENTAS - timedelta(days=200)

rnd = random.Random(SEMILLA)
fake = Faker('es_AR')
fake.seed_instance(SEMILLA)


def leer_csv(nombre):
    with open(os.path.join(CATALOGOS, nombre), encoding='utf-8', newline='') as f:
        return list(csv.DictReader(f))


def dos_decimales(x):
    return Decimal(str(x)).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)


def redondear_cien(x):
    return Decimal(int(round(x / 100.0)) * 100).quantize(Decimal('0.01'))


def fecha_entre(desde, hasta):
    return desde + timedelta(days=rnd.randint(0, (hasta - desde).days))


cuits_usados = set()


def nuevo_cuit(prefijo):
    # cuit con digito verificador valido y sin repetir
    pesos = [5, 4, 3, 2, 7, 6, 5, 4, 3, 2]
    while True:
        base = prefijo + str(rnd.randint(10000000, 99999999))
        resto = sum(int(d) * p for d, p in zip(base, pesos)) % 11
        dv = 11 - resto
        if dv == 11:
            dv = 0
        if dv == 10 or base.startswith('3099999') or base.startswith('2099999'):
            continue
        cuit = base + str(dv)
        if cuit not in cuits_usados:
            cuits_usados.add(cuit)
            return cuit


def elegir_distintos(items, acumulados, cantidad, largo=None):
    # elige sin repetir segun pesos acumulados, mirando solo los primeros 'largo' items
    if largo is None:
        largo = len(items)
    cantidad = min(cantidad, largo)
    total = acumulados[largo - 1]
    elegidos = []
    vistos = set()
    intentos = 0
    while len(elegidos) < cantidad and intentos < cantidad * 20:
        intentos += 1
        i = bisect.bisect_right(acumulados, rnd.random() * total, 0, largo)
        if i >= largo:
            i = largo - 1
        if i not in vistos:
            vistos.add(i)
            elegidos.append(items[i])
    return elegidos


def acumular(pesos):
    acumulados = []
    suma = 0
    for p in pesos:
        suma += p
        acumulados.append(suma)
    return acumulados


def nombre_unico(generador, usados):
    while True:
        nombre = generador()
        if nombre not in usados:
            usados.add(nombre)
            return nombre


# catalogos
departamentos = []
id_departamento = {}
for i, fila in enumerate(leer_csv('departamentos.csv'), 1):
    departamentos.append((i, fila['nombre'], fila['provincia']))
    id_departamento[fila['nombre']] = i

localidades = []
id_localidad = {}
for i, fila in enumerate(leer_csv('localidades.csv'), 1):
    localidades.append((i, fila['nombre'], fila['cod_postal'], id_departamento[fila['departamento']], fake.name()))
    id_localidad[fila['nombre']] = i

cepas = []
id_cepa = {}
peso_cepa = {}
for i, fila in enumerate(leer_csv('cepas.csv'), 1):
    cepas.append((i, fila['nombre'], fila['tipo']))
    id_cepa[fila['nombre']] = i
    peso_cepa[fila['nombre']] = int(fila['peso'])

maridajes = []
id_maridaje = {}
for i, fila in enumerate(leer_csv('maridajes.csv'), 1):
    maridajes.append((i, fila['nombre'], Decimal(fila['temperatura_servicio'])))
    id_maridaje[fila['nombre']] = i

tipos_vino = leer_csv('tipos_vino.csv')
presentaciones = leer_csv('presentaciones.csv')

# bodegas: la ultima es una bodega chica con pocos vinos
bodegas = []
razones = set()
for i in range(12):
    if i == 11:
        razon = 'Bodega Boutique ' + fake.last_name()
    else:
        razon = nombre_unico(lambda: 'Bodega ' + fake.last_name(), razones)
    localidad = rnd.choice(['San Rafael', 'Luján de Cuyo', 'Maipú', 'Tupungato', 'Tunuyán', 'San Carlos', 'General Alvear'])
    domicilio = f'{fake.street_name()} {rnd.randint(100, 9000)}, {localidad}'
    bodegas.append((nuevo_cuit('30'), razon, domicilio[:120]))

# transportistas y las localidades que cubren
transportistas = []
transportista_localidad = []
razones = set()
for i in range(1, 16):
    apellido = nombre_unico(fake.last_name, razones)
    razon = rnd.choice(['Transportes {}', 'Logística {}', 'Expreso {}', '{} Cargas']).format(apellido)
    correo = apellido.lower().replace(' ', '').replace('ñ', 'n')
    for a, b in zip('áéíóúü', 'aeiouu'):
        correo = correo.replace(a, b)
    transportistas.append((i, razon, nuevo_cuit('30'), f'contacto@{correo}.com.ar', fake.phone_number()[:20],
                           fake.street_address()[:120]))
    for loc in rnd.sample(range(1, len(localidades) + 1), rnd.randint(3, 4)):
        transportista_localidad.append((i, loc))

# salas de venta
localidades_sala = ['San Rafael', 'Mendoza', 'Godoy Cruz', 'Maipú', 'Luján de Cuyo', 'General Alvear',
                    'San Rafael', 'Tunuyán', 'San Martín', 'Malargüe', 'Mendoza', 'Rivadavia', 'Tupungato',
                    'San Carlos', 'Villa Nueva', 'Las Heras', 'Chacras de Coria', 'Junín', 'Villa Atuel',
                    'Real del Padre', 'Monte Comán', 'Palmira', 'Santa Rosa', 'La Paz', 'Villa 25 de Mayo',
                    'Mendoza', 'San Rafael', 'Godoy Cruz', 'Maipú', 'Bowen']
dias = ['lunes', 'martes', 'miercoles', 'jueves', 'viernes', 'sabado', 'domingo']
salas = []
for i, loc in enumerate(localidades_sala, 1):
    dia = rnd.choices(dias, weights=[9, 3, 7, 3, 1, 1, 6])[0]
    salas.append((i, fake.street_name()[:80], rnd.randint(10, 2500), dia, id_localidad[loc]))

# empleados
empleados = []
for sala in salas:
    for _ in range(rnd.randint(4, 7)):
        ingreso = HOY - timedelta(days=rnd.randint(20, 15 * 365))
        salario = dos_decimales(rnd.randint(750, 1800) * 1000 + rnd.choice([0, 250, 500, 750]))
        empleados.append((nuevo_cuit(rnd.choice(['20', '27'])), fake.name()[:80], ingreso, salario, sala[0]))

# fincas y parcelas
deptos_vino = ['San Rafael', 'General Alvear', 'Luján de Cuyo', 'Maipú', 'Tupungato', 'Tunuyán', 'San Carlos',
               'Rivadavia', 'Junín', 'San Martín', 'Lavalle', 'Santa Rosa']
cepas_plantables = [c for c in peso_cepa if peso_cepa[c] > 0]
acum_cepas = acumular([peso_cepa[c] for c in cepas_plantables])
fincas = []
parcelas = []
nombres_finca = set()
for i in range(1, 41):
    nombre = nombre_unico(lambda: rnd.choice(['Finca ', 'Finca La ', 'Viñedo ', 'Finca El ']) + fake.last_name(), nombres_finca)
    suma = Decimal('0')
    for nro in range(1, rnd.randint(10, 20) + 1):
        sup = dos_decimales(rnd.uniform(2, 25))
        suma += sup
        cepa = elegir_distintos(cepas_plantables, acum_cepas, 1)[0]
        parcelas.append((i, nro, sup, rnd.randint(1965, ANIO - 6), id_cepa[cepa]))
    fincas.append((i, nombre, dos_decimales(float(suma) * rnd.uniform(1.05, 1.3)),
                   id_departamento[rnd.choice(deptos_vino)]))

# lotes de uva de las ultimas cinco campanias ya cosechadas y sus analisis
ultima = ANIO if HOY >= date(ANIO, 5, 1) else ANIO - 1
campanias = list(range(ultima - 4, ultima + 1))
lotes = []
analisis = []
for campania in campanias:
    for p in parcelas:
        if rnd.random() < 0.9:
            cosecha = date(campania, 2, 10) + timedelta(days=rnd.randint(0, 79))
            kilos = dos_decimales(float(p[2]) * rnd.uniform(6000, 14000))
            nro_lote = len(lotes) + 1
            lotes.append((nro_lote, p[0], p[1], campania, cosecha, kilos, rnd.choice(bodegas)[0]))
            for _ in range(rnd.randint(1, 4)):
                fecha = min(cosecha + timedelta(days=rnd.randint(0, 12)), HOY)
                analisis.append((len(analisis) + 1, nro_lote, fecha,
                                 Decimal(str(round(rnd.uniform(19, 27), 1))),
                                 dos_decimales(rnd.uniform(3.2, 3.9)),
                                 dos_decimales(rnd.uniform(4.5, 8.0))))

# vinos: cada producto tiene varias aniadas o presentaciones con el mismo nombre
lineas = [('Joven', 4200, 14), ('Clásico', 5200, 12), ('Roble', 7000, 16), ('Reserva', 12500, 24),
          ('Gran Reserva', 21000, 14), ('Single Vineyard', 30000, 6), ('Icono', 48000, 4)]
acum_lineas = acumular([l[2] for l in lineas])
acum_tipos = acumular([int(t['peso']) for t in tipos_vino])
acum_vol = acumular([int(p['peso']) for p in presentaciones])
factor_vol = {int(p['volumen_ml']): float(p['factor_precio']) for p in presentaciones}
espumantes = ['Extra Brut', 'Brut Nature', 'Brut Rosé', 'Dulce Natural']

vinos = []
composicion = []
vino_maridaje = []
claves_vino = set()
datos_vino = {}


def agregar_vino(nombre, tipo, anada, volumen, graduacion, precio, cuit, corte, mars):
    if (nombre, anada, volumen) in claves_vino:
        return None
    claves_vino.add((nombre, anada, volumen))
    cod = len(vinos) + 1
    vinos.append((cod, nombre, tipo, anada, volumen, graduacion, precio, cuit))
    for cepa, porcentaje in corte:
        composicion.append((cod, id_cepa[cepa], dos_decimales(porcentaje)))
    for m in mars:
        vino_maridaje.append((cod, id_maridaje[m]))
    datos_vino[cod] = {'anada': anada, 'tipo': tipo, 'precio': precio, 'bodega': cuit,
                       'disponible': date(anada + 1, 3, 1)}
    return cod


def armar_corte(cepas_tipo):
    pesos = [max(peso_cepa[c], 1) for c in cepas_tipo]
    acum = acumular(pesos)
    if rnd.random() < 0.6:
        return [(elegir_distintos(cepas_tipo, acum, 1)[0], 100)]
    elegidas = elegir_distintos(cepas_tipo, acum, rnd.choice([2, 3]))
    if len(elegidas) == 1:
        return [(elegidas[0], 100)]
    principal = rnd.randrange(50, 90, 5)
    if len(elegidas) == 2:
        return [(elegidas[0], principal), (elegidas[1], 100 - principal)]
    resto = 100 - principal
    segunda = rnd.randrange(5, resto, 5) if resto > 5 else 5
    if resto - segunda <= 0:
        return [(elegidas[0], principal), (elegidas[1], resto)]
    return [(elegidas[0], principal), (elegidas[1], segunda), (elegidas[2], resto - segunda)]


# el vino del ejemplo del escenario
agregar_vino('Malbec Reserva', 'tinto', ANIO - 5, 750, Decimal('14.00'), Decimal('12500.00'), bodegas[0][0],
             [('Malbec', 85), ('Cabernet Sauvignon', 15)], ['Carnes rojas', 'Quesos duros'])

for b, bodega in enumerate(bodegas):
    productos = 3 if b == 11 else 15
    apellido = bodega[1].split()[-1]
    for _ in range(productos):
        tipo = tipos_vino[bisect.bisect_right(acum_tipos, rnd.random() * acum_tipos[-1])]
        linea, precio_base, _ = lineas[bisect.bisect_right(acum_lineas, rnd.random() * acum_lineas[-1])]
        corte = armar_corte(tipo['cepas'].split('|'))
        principal = corte[0][0]
        if tipo['tipo'] == 'espumante':
            nombre = f'{apellido} {rnd.choice(espumantes)}'
            precio_base = rnd.choice([6500, 9000, 14000])
        elif tipo['tipo'] == 'rosado':
            nombre = f'Rosé de {principal}'
            precio_base = min(precio_base, 9000)
        elif len(corte) > 1:
            nombre = f'{apellido} Blend {linea}'
        else:
            nombre = f'{principal} {linea}'
        graduacion = rnd.uniform(float(tipo['graduacion_min']), float(tipo['graduacion_max']))
        mars = rnd.sample(tipo['maridajes'].split('|'), rnd.randint(1, 3))
        variantes = 1 if b == 11 else rnd.randint(2, 4)
        for _ in range(variantes):
            if b == 11:
                anada, volumen = ANIO - 8, 750
            else:
                anada = rnd.randint(ANIO - 8, ANIO - 1)
                volumen = int(presentaciones[bisect.bisect_right(acum_vol, rnd.random() * acum_vol[-1])]['volumen_ml'])
            precio = redondear_cien(precio_base * factor_vol[volumen] * rnd.uniform(0.85, 1.2) * (1 + 0.03 * (ANIO - anada)))
            grad = dos_decimales(min(max(graduacion + rnd.uniform(-0.3, 0.3), float(tipo['graduacion_min'])),
                                     float(tipo['graduacion_max'])))
            agregar_vino(nombre, tipo['tipo'], anada, volumen, grad, precio, bodega[0], corte, mars)

cod_vinos = [v[0] for v in vinos]

# popularidad: los mas vendidos son vinos viejos, disponibles desde antes del inicio de las ventas
viejos = [c for c in cod_vinos if datos_vino[c]['anada'] <= ANIO - 7]
boutique = [c for c in cod_vinos if datos_vino[c]['bodega'] == bodegas[11][0]]
top = boutique + [c for c in rnd.sample(viejos, min(len(viejos), 25)) if c not in boutique][:17]
popularidad = {c: 1 + 8 * rnd.random() ** 3 for c in cod_vinos}
for i, c in enumerate(top):
    popularidad[c] = 30 - i * 0.6

# historial de precios: algunos vinos tuvieron un aumento en la ventana de ventas
cambios_precio = {}
auditoria = []
usuario = os.environ.get('PGUSER', 'bodega_owner')
for c in sorted(rnd.sample(cod_vinos, 80)):
    desde = max(INICIO_VENTAS, datos_vino[c]['disponible'] + timedelta(days=60))
    if desde >= HOY - timedelta(days=5):
        continue
    cuando = fecha_entre(desde, HOY - timedelta(days=5))
    nuevo = datos_vino[c]['precio']
    anterior = redondear_cien(float(nuevo) / rnd.uniform(1.08, 1.25))
    if anterior == nuevo or anterior <= 0:
        continue
    cambios_precio[c] = (cuando, anterior)
    momento = datetime(cuando.year, cuando.month, cuando.day, rnd.randint(8, 19), rnd.randint(0, 59), rnd.randint(0, 59))
    auditoria.append((len(auditoria) + 1, c, anterior, nuevo, momento, usuario))


def precio_en(cod, fecha):
    cambio = cambios_precio.get(cod)
    if cambio and fecha < cambio[0]:
        return cambio[1]
    return datos_vino[cod]['precio']


# clientes y subtipos
clientes = []
socios = []
distribuidores = []
exportadores = []
permisos = []
zonas = ['Gran Mendoza', 'Sur mendocino', 'Valle de Uco', 'Este mendocino', 'Cuyo', 'Córdoba', 'Buenos Aires',
         'Litoral', 'Patagonia', 'NOA']
paises = ['Chile', 'Brasil', 'Estados Unidos', 'Reino Unido', 'China', 'Canadá', 'México', 'Paraguay', 'Uruguay',
          'Alemania', 'Países Bajos', 'Japón']
documentos = set()
locs_sala = [s[4] for s in salas]
compradores = []
for i in range(1, CANT_CLIENTES + 1):
    tipo = rnd.choices(['socio', 'distribuidor', 'exportador'], weights=[75, 17, 8])[0]
    alta = HOY - timedelta(days=int(rnd.triangular(0, 8 * 365, 600)))
    if tipo == 'socio':
        nombre = f'{fake.last_name()}, {fake.first_name()}'
        tipo_doc = 'DNI'
        doc = nombre_unico(lambda: str(rnd.randint(10000000, 45999999)), documentos)
        descuento = Decimal('10.00')
        socios.append((i, 'socio', 100000 + len(socios) + 1))
    else:
        nombre = f'{fake.last_name()} {rnd.choice(["S.A.", "S.R.L.", "Hnos.", "y Asociados"])}'
        tipo_doc = 'CUIT'
        doc = nuevo_cuit(rnd.choice(['30', '33']))
        if tipo == 'distribuidor':
            descuento = Decimal('20.00')
            distribuidores.append((i, 'distribuidor', rnd.choice(zonas), f'HAB-{len(distribuidores) + 1:06d}'))
        else:
            descuento = Decimal('30.00')
            exportadores.append((i, 'exportador', rnd.choice(paises)))
            for _ in range(rnd.choices([1, 2, 3, 4, 5, 6], weights=[30, 25, 20, 12, 8, 5])[0]):
                emision = fecha_entre(INICIO_VENTAS, HOY - timedelta(days=30))
                vencimiento = emision + timedelta(days=rnd.randint(365, 3 * 365))
                permisos.append((f'PE-{emision.year}-{len(permisos) + 1:05d}', i, emision, vencimiento))
    loc = rnd.choice(locs_sala) if rnd.random() < 0.6 else rnd.randint(1, len(localidades))
    clientes.append((i, nombre[:120], tipo_doc, doc, fake.street_address()[:120], loc, alta, tipo, descuento))
    # algunos clientes nunca compran
    if rnd.random() >= 0.06:
        compradores.append((alta, i, tipo, descuento))
compradores.sort()
altas_compradores = [c[0] for c in compradores]

# ingresos al deposito central
pesos_bodega = [3 if b == 11 else 15 for b in range(12)]
vinos_bodega = {b[0]: [c for c in cod_vinos if datos_vino[c]['bodega'] == b[0]] for b in bodegas}
ingresos = []
renglones_ingreso = []
fechas_ingreso = sorted(fecha_entre(INICIO_INGRESOS, HOY) for _ in range(CANT_INGRESOS))
for fecha in fechas_ingreso:
    cuit = bodegas[rnd.choices(range(12), weights=pesos_bodega)[0]][0]
    candidatos = sorted((datos_vino[c]['disponible'], c) for c in vinos_bodega[cuit])
    disponibles = [c for d, c in candidatos if d <= fecha]
    if not disponibles:
        continue
    if fecha > HOY - timedelta(days=20):
        estado = rnd.choices(['en_confeccion', 'terminado', 'procesado'], weights=[35, 35, 30])[0]
    else:
        estado = 'procesado'
    indice = len(ingresos)
    ingresos.append({'fecha': fecha, 'estado': estado, 'transporte': rnd.randint(1, len(transportistas)), 'cuit': cuit})
    acum = acumular([popularidad[c] for c in disponibles])
    for c in elegir_distintos(disponibles, acum, rnd.randint(3, 8)):
        renglones_ingreso.append({'ingreso': indice, 'vino': c, 'fecha': fecha, 'estado': estado, 'pedido': 0})

# primer ingreso procesado de cada vino y lista de ingresos por vino
ingresos_vino = {}
for r, ren in enumerate(renglones_ingreso):
    if ren['estado'] == 'procesado':
        ingresos_vino.setdefault(ren['vino'], []).append((ren['fecha'], r))
primer_ingreso = {c: lista[0][0] for c, lista in ingresos_vino.items()}

# transferencias del deposito a las salas
otros = [c for c in cod_vinos if c not in set(top)]
acum_otros = acumular([popularidad[c] for c in otros])
surtido = {}
for sala in salas:
    surtido[sala[0]] = top + elegir_distintos(otros, acum_otros, rnd.randint(90, 110))

transferencias = []
renglones_transferencia = []
for sala in salas:
    id_sala = sala[0]
    fechas = [fecha_entre(INICIO_TRANSFERENCIAS, HOY - timedelta(days=1)) for _ in range(TRANSFERENCIAS_POR_SALA)]
    # cada sala tiene al menos un pedido reciente
    fechas.append(HOY - timedelta(days=rnd.randint(0, 14)))
    for fecha in sorted(fechas):
        disponibles = [c for c in surtido[id_sala] if c in primer_ingreso and primer_ingreso[c] <= fecha]
        if not disponibles:
            continue
        if fecha > HOY - timedelta(days=15):
            estado = rnd.choices(['en_confeccion', 'terminado', 'procesado'], weights=[30, 30, 40])[0]
        else:
            estado = 'procesado'
        indice = len(transferencias)
        transferencias.append({'sala': id_sala, 'fecha': fecha, 'estado': estado})
        acum = acumular([popularidad[c] for c in disponibles])
        for c in elegir_distintos(disponibles, acum, rnd.randint(2, 5)):
            renglones_transferencia.append({'transferencia': indice, 'sala': id_sala, 'vino': c, 'fecha': fecha,
                                            'estado': estado, 'pedido': 0})

# por cada par sala-vino, transferencias procesadas ordenadas por fecha
transf_par = {}
for r, ren in enumerate(renglones_transferencia):
    if ren['estado'] == 'procesado':
        transf_par.setdefault((ren['sala'], ren['vino']), []).append((ren['fecha'], r))
fechas_par = {par: [f for f, _ in lista] for par, lista in transf_par.items()}

# por sala, los vinos ordenados por la fecha en que llegaron por primera vez
llegadas = {}
for sala in salas:
    pares = sorted((lista[0][0], vino) for (s, vino), lista in transf_par.items() if s == sala[0])
    llegadas[sala[0]] = {'fechas': [p[0] for p in pares], 'vinos': [p[1] for p in pares],
                         'acum': acumular([popularidad[p[1]] for p in pares])}

# ventas
pesos_sala = [2.0 if s[0] == 1 else rnd.uniform(0.6, 1.4) for s in salas]
ids_sala = [s[0] for s in salas]
fechas_venta = sorted(fecha_entre(INICIO_VENTAS, HOY) for _ in range(CANT_COMPROBANTES))
comprobantes = []
renglones_comprobante = []
vendido_par = {}
for fecha in fechas_venta:
    while True:
        id_sala = rnd.choices(ids_sala, weights=pesos_sala)[0]
        ll = llegadas[id_sala]
        largo = bisect.bisect_right(ll['fechas'], fecha)
        if largo > 0:
            break
    hasta = bisect.bisect_right(altas_compradores, fecha)
    _, id_cliente, tipo, descuento = compradores[rnd.randrange(hasta)]
    nro = len(comprobantes) + 1
    cantidad_renglones = rnd.choices([1, 2, 3, 4, 5, 6], weights=[12, 18, 25, 20, 15, 10])[0]
    subtotal = Decimal('0')
    total = Decimal('0')
    for vino in elegir_distintos(ll['vinos'], ll['acum'], cantidad_renglones, largo):
        if tipo == 'socio':
            cantidad = rnd.choices([1, 2, 3], weights=[55, 30, 15])[0]
        elif tipo == 'distribuidor':
            cantidad = rnd.randint(3, 24)
        else:
            cantidad = rnd.randint(6, 48)
        precio = precio_en(vino, fecha)
        sub = (cantidad * precio * (100 - descuento) / 100).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)
        subtotal += cantidad * precio
        total += sub
        renglones_comprobante.append((nro, vino, cantidad, precio, descuento, sub))
        # la venta sale de la ultima transferencia procesada antes de la fecha
        lista = transf_par[(id_sala, vino)]
        r = lista[bisect.bisect_right(fechas_par[(id_sala, vino)], fecha) - 1][1]
        renglones_transferencia[r]['pedido'] += cantidad
        vendido_par[(id_sala, vino)] = vendido_par.get((id_sala, vino), 0) + cantidad
    comprobantes.append((nro, fecha, id_cliente, id_sala, subtotal, subtotal - total, total))

# cantidades finales de las transferencias: lo vendido mas un sobrante en la ultima de cada par
for par, lista in transf_par.items():
    ultima_r = lista[-1][1]
    sobrante = 0 if rnd.random() < 0.15 else rnd.randint(1, 24)
    renglones_transferencia[ultima_r]['pedido'] += sobrante
for ren in renglones_transferencia:
    if ren['estado'] == 'procesado':
        ren['cantidad'] = ren['pedido']
    else:
        ren['cantidad'] = rnd.randint(6, 48)
renglones_transferencia = [r for r in renglones_transferencia if r['cantidad'] > 0]

# lo transferido sale del ultimo ingreso procesado antes de la fecha
fechas_ing_vino = {c: [f for f, _ in lista] for c, lista in ingresos_vino.items()}
for ren in renglones_transferencia:
    if ren['estado'] == 'procesado':
        lista = ingresos_vino[ren['vino']]
        r = lista[bisect.bisect_right(fechas_ing_vino[ren['vino']], ren['fecha']) - 1][1]
        renglones_ingreso[r]['pedido'] += ren['cantidad']
for c, lista in ingresos_vino.items():
    sobrante = 0 if rnd.random() < 0.1 else rnd.randint(1, 360)
    renglones_ingreso[lista[-1][1]]['pedido'] += sobrante
for ren in renglones_ingreso:
    if ren['estado'] == 'procesado':
        ren['cantidad'] = ren['pedido']
    else:
        ren['cantidad'] = rnd.randint(24, 600)
renglones_ingreso = [r for r in renglones_ingreso if r['cantidad'] > 0]

# numeracion final de ingresos y transferencias en orden de fecha, sin documentos vacios
usados = sorted(set(r['ingreso'] for r in renglones_ingreso))
nuevo_ing = {viejo: nuevo for nuevo, viejo in enumerate(usados, 1)}
tabla_ingreso = [(nuevo_ing[i], ingresos[i]['fecha'], ingresos[i]['estado'], ingresos[i]['transporte'], ingresos[i]['cuit'])
                 for i in usados]
tabla_renglon_ingreso = [(nuevo_ing[r['ingreso']], r['vino'], r['cantidad']) for r in renglones_ingreso]

orden = sorted(set(r['transferencia'] for r in renglones_transferencia),
               key=lambda i: (transferencias[i]['fecha'], i))
nuevo_tr = {viejo: nuevo for nuevo, viejo in enumerate(orden, 1)}
tabla_transferencia = [(nuevo_tr[i], transferencias[i]['sala'], transferencias[i]['fecha'], transferencias[i]['estado'])
                       for i in orden]
tabla_renglon_transferencia = sorted((nuevo_tr[r['transferencia']], r['vino'], r['cantidad']) for r in renglones_transferencia)

# stock final
entrado_sala = {}
for r in renglones_transferencia:
    if r['estado'] == 'procesado':
        par = (r['sala'], r['vino'])
        entrado_sala[par] = entrado_sala.get(par, 0) + r['cantidad']
stock_sala = sorted((s, v, cant - vendido_par.get((s, v), 0)) for (s, v), cant in entrado_sala.items())

entrado_dep = {}
for r in renglones_ingreso:
    if r['estado'] == 'procesado':
        entrado_dep[r['vino']] = entrado_dep.get(r['vino'], 0) + r['cantidad']
salido_dep = {}
for r in renglones_transferencia:
    if r['estado'] == 'procesado':
        salido_dep[r['vino']] = salido_dep.get(r['vino'], 0) + r['cantidad']
stock_deposito = [(c, entrado_dep.get(c, 0) - salido_dep.get(c, 0)) for c in cod_vinos]

# tablas en el orden de carga, respetando las claves foraneas
TABLAS = [
    ('departamento', 'id_departamento, nombre, provincia', departamentos),
    ('localidad', 'id_localidad, nombre, cod_postal, id_departamento, encargado_regional', localidades),
    ('cepa', 'id_cepa, nombre, tipo', cepas),
    ('maridaje', 'id_maridaje, nombre, temperatura_servicio', maridajes),
    ('bodega', 'cuit, razon_social, domicilio', bodegas),
    ('transportista', 'cod_transporte, razon_social, cuit, email, telefono, domicilio', transportistas),
    ('transportista_localidad', 'cod_transporte, id_localidad', transportista_localidad),
    ('sala_venta', 'id_sala, calle, numero, dia_cierre, id_localidad', salas),
    ('empleado', 'cuit, nombre, fecha_ingreso, salario, id_sala', empleados),
    ('finca', 'id_finca, nombre, superficie_ha, id_departamento', fincas),
    ('parcela', 'id_finca, nro_parcela, superficie_ha, anio_plantacion, id_cepa', parcelas),
    ('lote_uva', 'nro_lote, id_finca, nro_parcela, campania, fecha_cosecha, kilos, cuit_bodega', lotes),
    ('analisis_calidad', 'id_analisis, nro_lote, fecha, brix, ph, acidez_total', analisis),
    ('vino', 'cod_vino, nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega', vinos),
    ('composicion', 'cod_vino, id_cepa, porcentaje', composicion),
    ('vino_maridaje', 'cod_vino, id_maridaje', vino_maridaje),
    ('auditoria_precio', 'id_auditoria, cod_vino, precio_anterior, precio_nuevo, fecha_hora, usuario', auditoria),
    ('cliente', 'id_cliente, nombre, tipo_documento, nro_documento, direccion, id_localidad, fecha_alta, tipo, descuento', clientes),
    ('socio', 'id_cliente, tipo, nro_carnet', socios),
    ('distribuidor', 'id_cliente, tipo, zona_cobertura, nro_habilitacion', distribuidores),
    ('exportador', 'id_cliente, tipo, pais_destino', exportadores),
    ('permiso_exportacion', 'cod_permiso, id_cliente, fecha_emision, fecha_vencimiento', permisos),
    ('ingreso', 'cod_ingreso, fecha, estado, cod_transporte, cuit_bodega', tabla_ingreso),
    ('renglon_ingreso', 'cod_ingreso, cod_vino, cantidad', tabla_renglon_ingreso),
    ('transferencia', 'nro_transferencia, id_sala, fecha_confeccion, estado', tabla_transferencia),
    ('renglon_transferencia', 'nro_transferencia, cod_vino, cantidad', tabla_renglon_transferencia),
    ('comprobante', 'nro_comprobante, fecha, id_cliente, id_sala, subtotal, descuento, total', comprobantes),
    ('renglon_comprobante', 'nro_comprobante, cod_vino, cantidad, precio_unitario, porc_descuento, subtotal', renglones_comprobante),
    ('stock_deposito', 'cod_vino, cantidad', stock_deposito),
    ('stock_sala', 'id_sala, cod_vino, cantidad', stock_sala),
]

COLUMNAS_CLIENTE = [t[1] for t in TABLAS if t[0] == 'cliente'][0]

# tablas con triggers propios que se deshabilitan durante la carga historica
CON_TRIGGERS = ['cliente', 'comprobante', 'renglon_comprobante', 'ingreso', 'renglon_ingreso', 'transferencia',
                'renglon_transferencia', 'vino', 'composicion']


def copiar(cur, tabla, columnas, filas):
    with cur.copy(f'COPY {tabla} ({columnas}) FROM STDIN') as copy:
        for fila in filas:
            copy.write_row(fila)


def medir_carga_clientes(conn, informe):
    # compara la carga fila por fila con la carga por lotes sobre la tabla cliente
    sql = ('INSERT INTO cliente (id_cliente, nombre, tipo_documento, nro_documento, direccion, id_localidad, '
           'fecha_alta, tipo, descuento) OVERRIDING SYSTEM VALUE VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)')
    with conn.cursor() as cur:
        inicio = time.perf_counter()
        for fila in clientes:
            cur.execute(sql, fila)
        conn.commit()
        t_fila = time.perf_counter() - inicio
        cur.execute('TRUNCATE cliente CASCADE')
        conn.commit()

        inicio = time.perf_counter()
        cur.executemany(sql, clientes)
        conn.commit()
        t_lotes = time.perf_counter() - inicio
        cur.execute('TRUNCATE cliente CASCADE')
        conn.commit()

        inicio = time.perf_counter()
        copiar(cur, 'cliente', COLUMNAS_CLIENTE, clientes)
        conn.commit()
        t_copy = time.perf_counter() - inicio
        cur.execute('TRUNCATE cliente CASCADE')
        conn.commit()
    informe.append(f'carga de {len(clientes)} clientes')
    informe.append(f'  fila por fila (un INSERT por fila, una transaccion): {t_fila:8.2f} s  {len(clientes) / t_fila:10.0f} filas/s')
    informe.append(f'  por lotes con executemany:                           {t_lotes:8.2f} s  {len(clientes) / t_lotes:10.0f} filas/s')
    informe.append(f'  por lotes con COPY:                                  {t_copy:8.2f} s  {len(clientes) / t_copy:10.0f} filas/s')
    informe.append(f'  COPY es {t_fila / t_copy:.1f} veces mas rapido que fila por fila')


def main():
    informe = [f'semilla: {SEMILLA}', f'fecha base: {HOY}', '']
    inicio_total = time.perf_counter()
    with psycopg.connect('') as conn:
        with conn.cursor() as cur:
            nombres = ', '.join(t[0] for t in TABLAS)
            cur.execute(f'TRUNCATE {nombres} RESTART IDENTITY CASCADE')
            for tabla in CON_TRIGGERS:
                cur.execute(f'ALTER TABLE {tabla} DISABLE TRIGGER USER')
            conn.commit()

            informe.append('tiempo de carga con COPY por tabla')
            for tabla, columnas, filas in TABLAS:
                if tabla == 'cliente':
                    # antes de cargar los clientes se comparan las formas de insertar
                    medir_carga_clientes(conn, informe)
                inicio = time.perf_counter()
                copiar(cur, tabla, columnas, filas)
                conn.commit()
                informe.append(f'  {tabla:25s} {len(filas):8d} filas {time.perf_counter() - inicio:8.2f} s')

            # las identity siguen desde el maximo cargado
            cur.execute('''
                SELECT c.relname, a.attname
                  FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid
                  JOIN pg_namespace n ON n.oid = c.relnamespace
                 WHERE n.nspname = 'public' AND a.attidentity <> '' ''')
            for tabla, columna in cur.fetchall():
                cur.execute(f"SELECT setval(pg_get_serial_sequence('{tabla}', '{columna}'), "
                            f"COALESCE((SELECT max({columna}) FROM {tabla}), 0) + 1, false)")

            for tabla in CON_TRIGGERS:
                cur.execute(f'ALTER TABLE {tabla} ENABLE TRIGGER USER')
            conn.commit()
            conn.autocommit = True
            cur.execute('ANALYZE')

    informe.append('')
    informe.append(f'tiempo de generacion de los datos en python: {inicio_total - inicio_global:.1f} s')
    informe.append(f'tiempo de carga en la base (con la comparacion de clientes): {time.perf_counter() - inicio_total:.1f} s')
    texto = '\n'.join(informe) + '\n'
    print(texto)
    os.makedirs(RESULTADOS, exist_ok=True)
    with open(os.path.join(RESULTADOS, 'carga_tiempos.txt'), 'w', encoding='utf-8') as f:
        f.write(texto)


if __name__ == '__main__':
    main()
