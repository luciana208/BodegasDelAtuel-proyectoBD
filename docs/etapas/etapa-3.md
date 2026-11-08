# Etapa 3: carga masiva

## Qué hicimos

Escribimos `db/seed/cargar.py`, que genera todos los datos con random y Faker (`es_AR`) usando una semilla fija y los carga con COPY. Corre en su propio contenedor, así que alcanza con un comando:

```
docker compose run --rm seed
```

Los catálogos reales (departamentos y localidades de Mendoza con su código postal, cepas, maridajes, tipos de vino y presentaciones) están en CSV en `db/seed/catalogos/`. El resto se genera.

Lo más difícil fue que los datos sean coherentes y que el stock no quede negativo. Lo resolvimos generando la historia en orden (ingresos, transferencias, ventas) y calculando las cantidades al final, hacia atrás: cada transferencia lleva lo que después se vendió en esa sala, y cada ingreso lo que después se transfirió, más un sobrante. El detalle está en `db/seed/README.md`.

Todas las fechas se calculan desde el día en que se corre la carga. Las ventas cubren seis años para que haya comprobantes de más de cinco años, y los lotes de uva las últimas cinco campañas. También usamos datos del escenario: el vino "Malbec Reserva" de 750 ml con 85 % Malbec y 15 % Cabernet Sauvignon, a $12.500 y con 14°, recomendado con carnes rojas y quesos duros.

Algunas cosas las generamos pensando en las consultas de la etapa 5: una bodega chica con tres vinos muy vendidos (para que haya clientes que compraron todos sus vinos), un 6 % de clientes que nunca compran, cepas que no se usan, exportadores con más de 3 permisos, salas con cierre lunes o miércoles y pares sala-vino con stock 0.

### Triggers

Para la carga histórica deshabilitamos los triggers propios con `ALTER TABLE ... DISABLE TRIGGER USER` y los volvimos a habilitar al final. Si no, cada renglón de venta hubiera descontado stock otra vez, las transferencias viejas quedaban con la fecha de hoy y no se podían cargar documentos ya procesados. Las FK, los CHECK y los UNIQUE siguen activos durante la carga. El riesgo es que mientras están apagados la base no revisa las reglas que dependen de otras filas, por eso después de cargar corremos `db/seed/control.sql`. Los riesgos y el orden de carga están explicados en `db/seed/README.md`.

### Tiempos

Para comparar cargamos los 20.000 clientes de tres formas antes de la carga real:

| Forma | Tiempo | Filas por segundo |
|---|---|---|
| Fila por fila (un INSERT por fila en una transacción) | 2,76 s | 7.242 |
| Por lotes con `executemany` | 0,83 s | 24.140 |
| Por lotes con COPY | 0,26 s | 78.302 |

COPY fue unas 10 veces más rápido que fila por fila. La carga entera, incluidos los 506.878 renglones de comprobante, tarda unos 14 segundos en la base más unos 6 segundos de generación en Python. Los tiempos de cada tabla están en `docs/resultados/carga_tiempos.txt`.

### Volúmenes

| Tabla | Filas |
|---|---|
| renglon_comprobante | 506.878 |
| comprobante | 150.000 |
| cliente | 20.000 (15.028 socios, 3.425 distribuidores, 1.547 exportadores) |
| renglon_transferencia | 10.423 |
| analisis_calidad | 6.903 |
| renglon_ingreso | 4.169 |
| permiso_exportacion | 4.008 |
| transferencia | 3.028 |
| lote_uva | 2.741 |
| stock_sala | 2.341 |
| ingreso | 1.650 |
| vino_maridaje, composicion, parcela, vino, stock_deposito | 837, 665, 605, 409, 409 |
| empleado | 159 |
| catálogos (localidad, cepa, maridaje, bodega, transportista, cobertura, finca, sala, departamento, auditoría) | entre 12 y 80 |

El conteo completo está en `docs/resultados/carga_control.txt`.

### Volcado

El volcado de la base cargada está en `db/seed/dump_completo.sql.gz` (unos 6 MB) y se vuelve a generar con `bash db/seed/generar_dump.sh`. Lo probamos restaurándolo en una base nueva y dio los mismos 506.878 renglones, con los permisos de los roles incluidos.

## Criterios de aceptación

- [x] Se cumplen los mínimos de volumen. Todas las tablas tienen filas, cinco superan las 10.000 (`renglon_comprobante`, `comprobante`, `cliente`, `socio` y `renglon_transferencia`) y `renglon_comprobante` supera las 500.000. Se ve en `docs/resultados/carga_control.txt`.
- [x] Dos ejecuciones con la misma semilla producen los mismos datos. Corrimos la carga cuatro veces (una sobre una base recién creada) con `SEMILLA=2026` y la misma fecha, y `db/seed/huella.sql` dio el mismo md5 en las 30 tablas. La huella está en `docs/resultados/carga_huella.txt` y el procedimiento para repetirlo en `db/seed/README.md`.
- [x] Las consultas de control no encuentran inconsistencias. Los 23 controles de `db/seed/control.sql` dan 0 (`docs/resultados/carga_control.txt`).
- [x] El informe compara la carga fila por fila con la carga por lotes. Tabla de tiempos de arriba y `docs/resultados/carga_tiempos.txt`.
- [x] Está documentado cómo se manejaron los triggers durante la carga. Sección "Triggers" de este archivo y de `db/seed/README.md`.
