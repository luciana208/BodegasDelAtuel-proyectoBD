# Carga masiva

Script en Python (psycopg 3, random y Faker con `es_AR`) que genera los datos de prueba y los carga en la base.

## Cómo se corre

Con la base levantada (`docker compose up -d db`):

```
docker compose run --rm seed
```

Esto construye la imagen de `db/seed/Dockerfile`, borra los datos que haya, genera todo de nuevo, lo carga con COPY y después corre las consultas de control. Tarda alrededor de medio minuto. Deja tres archivos en `docs/resultados/`:

- `carga_tiempos.txt`: tiempos por tabla y la comparación de la carga fila por fila contra la carga por lotes.
- `carga_control.txt`: conteo de filas por tabla, consultas de control y datos que usan las consultas por período.
- `carga_huella.txt`: un md5 por tabla para comparar dos cargas.

Variables (en el `.env`):

| Variable | Para qué | Valor por defecto |
|---|---|---|
| `SEMILLA` | Semilla de random y de Faker | 2026 |
| `FECHA_BASE` | Fecha desde la que se calculan las fechas, en formato aaaa-mm-dd | vacía, es el día de hoy |

Las consultas de control también se pueden correr solas:

```
docker compose exec -T db psql -U bodega_owner -d bodegas -f - < db/seed/control.sql
```

## Fechas relativas

Todas las fechas se calculan desde la fecha base, que por defecto es el día en que se corre la carga. Las ventas cubren los últimos seis años, los lotes de uva las últimas cinco campañas ya cosechadas (febrero a abril) y hay movimientos en los últimos días. Así las consultas de "última semana", "último mes", "último trimestre", "últimos 15 días" y "más de 5 años" siempre encuentran datos. Si dos personas cargan en días distintos los datos cambian un poco; para obtener exactamente los mismos datos hay que usar la misma semilla y la misma `FECHA_BASE`.

## Catálogos

Están en `db/seed/catalogos/` y no se generan al azar:

- `departamentos.csv`: los 18 departamentos de Mendoza.
- `localidades.csv`: 35 localidades de Mendoza con su código postal y su departamento.
- `cepas.csv`: cepas con su tipo. La columna `peso` indica qué tan seguido aparece cada una en parcelas y vinos; las que tienen peso 0 no se usan, para que haya cepas sin vinos ni parcelas.
- `maridajes.csv`: maridajes con su temperatura de servicio.
- `tipos_vino.csv`: los cuatro tipos con su rango de graduación, las cepas y los maridajes que les corresponden.
- `presentaciones.csv`: volúmenes con qué tan seguido aparecen y el factor de precio respecto de la botella de 750 ml.

Lo demás (nombres de bodegas, fincas, clientes, transportistas, empleados, direcciones y teléfonos) sale de Faker.

## Orden de carga

Las tablas se cargan de modo que cada una se carga después de las tablas a las que apuntan sus FK:

```
departamento ─┬─> localidad ─┬─> sala_venta ──> empleado
              │              ├─> transportista_localidad <── transportista
              │              └─> cliente ─┬─> socio
              │                           ├─> distribuidor
              │                           └─> exportador ──> permiso_exportacion
              └─> finca ──> parcela <── cepa
                              └─> lote_uva <── bodega
                                    └─> analisis_calidad

bodega ──> vino ─┬─> composicion <── cepa
                 ├─> vino_maridaje <── maridaje
                 └─> auditoria_precio

transportista + bodega ──> ingreso ──> renglon_ingreso <── vino
sala_venta ──> transferencia ──> renglon_transferencia <── vino
cliente + sala_venta ──> comprobante ──> renglon_comprobante <── vino
vino + sala_venta ──> stock_deposito, stock_sala
```

## Coherencia de los datos

El script arma la historia en el mismo orden en que pasaría en la realidad:

1. Cada vino recién está disponible desde marzo del año siguiente a su añada.
2. Los ingresos al depósito llevan solo vinos de su bodega que ya están disponibles.
3. Las transferencias a una sala llevan solo vinos que ya tuvieron un ingreso procesado.
4. Cada venta usa solo vinos que ya llegaron a esa sala por una transferencia procesada, y clientes que ya estaban dados de alta.
5. Al final se calculan las cantidades hacia atrás: cada transferencia lleva lo que se vendió de ese vino en esa sala hasta la transferencia siguiente, más un sobrante en la última; y cada ingreso lleva lo que se transfirió hasta el ingreso siguiente, más un sobrante. Así el stock nunca es negativo en ningún momento, y el stock final es exactamente lo que entró menos lo que salió.

Los documentos de los últimos días pueden estar en confección, terminados o procesados. Los que no están procesados no suman stock.

Los precios de 80 vinos tuvieron un aumento en algún momento de la ventana de ventas: las ventas anteriores usan el precio viejo y el cambio queda en `auditoria_precio`. El precio unitario de cada renglón es el precio que tenía el vino ese día. El descuento de cada renglón es el del cliente y los importes se calculan igual que en la base.

## Triggers durante la carga

Si la carga histórica pasara por los triggers, cada renglón de venta descontaría stock de la sala y recalcularía su comprobante, la fecha de confección de cada transferencia se pisaría con la fecha de hoy y no se podrían cargar documentos ya procesados. Por eso el script hace:

```
ALTER TABLE ... DISABLE TRIGGER USER;   -- antes de cargar
COPY ...;
ALTER TABLE ... ENABLE TRIGGER USER;    -- al terminar
```

`DISABLE TRIGGER USER` apaga solo los triggers propios. Las FK siguen activas, así que no puede quedar ningún renglón huérfano, y los CHECK, UNIQUE y NOT NULL tampoco se apagan.

Riesgos: mientras los triggers están apagados la base no controla el stock, los estados, la suma de los cortes ni los importes. Si el script tuviera un error podrían quedar datos que no cumplen las reglas, y los triggers no los revisan cuando se vuelven a encender porque solo actúan sobre filas nuevas. Por eso después de la carga corremos `control.sql`, que verifica stock, importes, descuentos, precios, cortes, fechas y que los triggers hayan quedado habilitados. Además, la carga se hace con el rol propietario, que es el único que puede deshabilitar triggers; la API no puede.

## Reproducibilidad

`random.Random(SEMILLA)` y `Faker.seed_instance(SEMILLA)` hacen que con la misma semilla y la misma fecha base se generen siempre los mismos datos. Las versiones de psycopg y Faker están fijas en `requirements.txt` porque otra versión de Faker puede generar otros nombres. Para comprobarlo se corre la carga dos veces y se comparan las huellas:

```
docker compose run --rm seed
cp docs/resultados/carga_huella.txt /tmp/huella_1.txt
docker compose run --rm seed
diff /tmp/huella_1.txt docs/resultados/carga_huella.txt
```

## Volcado

`dump_completo.sql.gz` es el volcado de la base cargada, hecho con pg_dump. Se genera con:

```
bash db/seed/generar_dump.sh
```

Para restaurarlo en una base nueva del mismo servidor:

```
docker compose exec -T db createdb -U bodega_owner bodegas_restaurada
zcat db/seed/dump_completo.sql.gz | docker compose exec -T db psql -U bodega_owner -d bodegas_restaurada
```
