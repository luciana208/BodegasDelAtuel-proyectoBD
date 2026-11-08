# Etapa 2: integridad y lógica en la base

## Qué hicimos

En esta etapa pusimos las reglas de negocio adentro de la base, para que se cumplan aunque alguien se conecte directo con psql y no pase por la API. Lo repartimos en un archivo por tipo de objeto:

- `002_constraints.sql`: 11 UNIQUE con nombre, 32 CHECK y 13 DEFAULT que se suman a los que ya venían en 001. Todos los CHECK son de una sola fila y no usan la fecha actual, así no se rompen al restaurar un backup. Los que comparan columnas son `chk_comprobante_total` (total = subtotal - descuento), `chk_permiso_fechas` (vencimiento posterior a emisión), `chk_lote_fecha_campania`, `chk_comprobante_importes` y `chk_auditoria_precios`.
- `003_funciones.sql`: 8 funciones. Las de cálculo puro (`fn_descuento_tipo`, `fn_subtotal_renglon`) son IMMUTABLE; las que leen tablas o usan `CURRENT_DATE` son STABLE.
- `004_procedimientos.sql`: `sp_procesar_ingreso` y `sp_procesar_transferencia`.
- `005_triggers.sql`: 13 triggers (9 BEFORE, 2 AFTER y 2 constraint triggers diferidos).
- `006_vistas.sql`: 4 vistas.
- `007_roles.sql` y `009_claves_roles.sh`: roles y privilegios. Las claves no están en el SQL: el script las toma de `APP_DB_PASSWORD` y `LECTURA_DB_PASSWORD` del `.env`.

### Cómo quedaron las ventas

Cuando se inserta un renglón de comprobante pasan varias cosas:

1. `trg_renglon_importes` (BEFORE) busca el precio del vino en ese momento, el descuento del cliente con `fn_descuento_cliente` y calcula el subtotal con `fn_subtotal_renglon`. Lo que mande el usuario en esas columnas se pisa.
2. `trg_renglon_valida_stock` (BEFORE) bloquea la fila de `stock_sala` con `FOR UPDATE` y, si `fn_stock_sala` no alcanza, rechaza la venta con un mensaje que dice cuánto hay y cuánto se pide.
3. `trg_renglon_actualiza` (AFTER) descuenta el stock y actualiza el comprobante.
4. `trg_comprobante_importes` (BEFORE en comprobante) recalcula subtotal, descuento y total desde los renglones en cada update, y al insertar un comprobante los pone en cero. Así nadie puede cargar un total a mano.

El descuento del cliente lo pone `trg_cliente_descuento` al darlo de alta, según su tipo. Se guarda en el cliente porque después puede cambiar para uno en particular (la consulta U6 se lo sube al 35 % a algunos exportadores), siempre dentro del rango del CHECK.

### Ingresos y transferencias

`trg_control_estado` se usa en las dos tablas. Un documento nuevo tiene que nacer en confección, y solo se puede avanzar de `en_confeccion` a `terminado` y de `terminado` a `procesado`. Además no deja terminar un documento sin renglones. Los renglones de los dos documentos tienen su trigger de bloqueo (RN-12) que rechaza insertar, modificar o borrar si la cabecera no está en confección.

Un detalle que apareció probando: al borrar un ingreso procesado, el `ON DELETE CASCADE` borra sus renglones y el trigger de bloqueo se disparaba y frenaba el borrado. Lo resolvimos así: si la cabecera ya no existe es porque se está borrando en cascada, y en ese caso se deja pasar.

Los procedimientos bloquean primero la cabecera y después las filas del depósito, siempre ordenadas por código de vino para que dos procesos al mismo tiempo no se traben entre sí. Para el caso que plantea el anexo A.6 (un vino del renglón sin fila en `stock_deposito`), `sp_procesar_transferencia` revisa antes de tocar nada que todos los vinos tengan fila y que alcance el stock. Si falta alguno, levanta un error que dice qué vino falla y como todo corre en la misma transacción no queda ningún cambio. `sp_procesar_ingreso` en cambio crea la fila del depósito si el vino no la tenía, con `INSERT ... ON CONFLICT`.

### Dónde va cada regla

| Tipo de regla | Herramienta | Dónde la usamos |
|---|---|---|
| Valor válido de una fila | NOT NULL, CHECK, DOMAIN | precio > 0, graduación, cantidades, stock >= 0, CUIT de 11 dígitos |
| Existencia de un dato relacionado | FOREIGN KEY | sala - localidad, empleado - sala, renglones - vino |
| Unicidad | UNIQUE o PRIMARY KEY | una cosecha por parcela y campaña, nombre + añada + volumen del vino |
| Depende de otras filas, tablas o de la fecha actual | Trigger | stock suficiente, estados, fecha de confección, suma de cortes |
| Cálculo que se usa en varios lugares | Función | descuento, subtotal, total, stock |
| Operación de varios pasos, todo o nada | Procedimiento | procesar ingreso y transferencia |

### Roles

| Rol | Para qué | Privilegios |
|---|---|---|
| `bodega_owner` | Propietario. Corre las migraciones y la carga | Dueño de todos los objetos |
| `bodega_app` | Lo usa la API | SELECT, INSERT, UPDATE y DELETE en las tablas, EXECUTE en funciones y procedimientos. Sin UPDATE ni DELETE en `auditoria_precio`, sin TRUNCATE ni CREATE |
| `bodega_lectura` | Reportes | SELECT y EXECUTE de funciones |

Se quitan los privilegios por defecto de PUBLIC sobre la base, el esquema y las funciones. En el contenedor local `bodega_owner` es el `POSTGRES_USER`, que la imagen de postgres crea como superusuario. En la nube el propietario va a ser un rol común.

### Concurrencia

Los scripts están en `db/tests/concurrencia/`. `preparar.sql` crea un vino, una sala y un cliente propios de la demostración con stock 1, `sesion_a.sql` y `sesion_b.sql` se corren en dos terminales al mismo tiempo y `limpiar.sql` borra todo al final. `demo.sh` hace todo junto y guarda la salida en `docs/resultados/concurrencia_sesion_a.txt` y `concurrencia_sesion_b.txt`.

Usamos el nivel de aislamiento por defecto de PostgreSQL, READ COMMITTED: cada sentencia ve lo que estaba confirmado cuando empezó. Hay tres partes:

1. Con `SELECT ... FOR UPDATE`: A bloquea la fila y lee 1. B hace la misma consulta y se queda esperando. Cuando A vende y hace COMMIT, B recibe el resultado, que ya es 0, y no vende. En la salida se ve que B pidió el dato a las 00:57:22 y recién lo recibió a las 00:57:25, cuando A confirmó.
2. Sin `FOR UPDATE`: las dos sesiones leen 1 porque ninguna bloquea. Cada una calcula 1 - 1 = 0 y lo guarda. Las dos ventas se confirman y la misma botella se vendió dos veces. En READ COMMITTED esto puede pasar porque el SELECT común no toma ningún bloqueo y el UPDATE de B no sabe que lo que leyó ya cambió.
3. Con la venta real (insertando renglones de comprobante): no hace falta escribir el `FOR UPDATE` porque lo hace el trigger `trg_renglon_valida_stock`. B queda esperando hasta que A confirma y después recibe `Stock insuficiente del vino ... hay 0 y se piden 1 (RN-09)`.

Aunque alguien se saltee el trigger, el stock no puede quedar negativo por `chk_stock_sala_cantidad`, y el descuento del stock se hace con `cantidad = cantidad - n`, que siempre trabaja sobre el valor más nuevo de la fila.

## Pruebas

`db/tests/db_tests.sql` arma datos propios dentro de una transacción, corre los casos y termina con ROLLBACK, así se puede correr las veces que haga falta sin ensuciar la base. Cada caso corre dentro de un procedimiento temporal con manejo de excepciones (`pg_temp.debe_fallar`, `pg_temp.debe_andar` y `pg_temp.verificar`), así un caso que falla no corta los siguientes. Los que tienen que fallar comparan el SQLSTATE que se obtuvo contra el esperado, que también está anotado en un comentario arriba de cada caso. Al final se muestra una tabla con todos los casos y un resumen.

```
docker compose exec -T db psql -U bodega_owner -d bodegas -f - < db/tests/db_tests.sql
```

La última corrida dio 90 casos, 90 ok y 15 reglas cubiertas. La salida completa está en `docs/resultados/db_tests.txt`. El conteo de constraints, funciones, triggers, vistas y privilegios sale de `db/tests/minimos.sql` y está guardado en `docs/resultados/minimos_etapa2.txt`.

## Trazabilidad

Los números de caso son los de la columna `nro` de la salida de `db_tests.sql`.

| Regla | Mecanismo | Casos |
|---|---|---|
| RN-01 precio único y mayor que cero | Columna `precio` solo en `vino` + `chk_vino_precio` | 1, 2, 3 |
| RN-02 sala en una localidad, un encargado por localidad | FK `sala_venta.id_localidad` NOT NULL, `encargado_regional` NOT NULL en `localidad` (3FN) | 4, 5, 6 |
| RN-03 empleado en una sola sala | FK `empleado.id_sala` NOT NULL | 7, 8, 9 |
| RN-04 una cepa por parcela, una cosecha por campaña | FK `parcela.id_cepa`, `uq_lote_parcela_campania`, `chk_lote_fecha_campania` | 10, 11, 12, 13 |
| RN-05 cortes suman 100 | Constraint triggers diferidos `trg_composicion_suma` y `trg_vino_composicion` | 14, 15, 16, 17 |
| RN-06 descuento por tipo de cliente | `fn_descuento_tipo`, `fn_descuento_cliente`, `trg_cliente_descuento`, `chk_cliente_descuento`, FK compuesta de subtipos | 18, 19, 20, 21, 22 |
| RN-07 varios permisos, vencimiento posterior | Tabla `permiso_exportacion` con FK a `exportador`, `chk_permiso_fechas` | 23, 24, 25, 26 |
| RN-08 total calculado, no cargado a mano | `fn_subtotal_renglon`, `fn_subtotal_comprobante`, `fn_total_comprobante`, `trg_renglon_importes`, `trg_renglon_actualiza`, `trg_comprobante_importes`, `chk_comprobante_total` | 27 a 32 |
| RN-09 no vender más que el stock, stock no negativo | `trg_renglon_valida_stock` (BEFORE, con FOR UPDATE), `trg_renglon_actualiza` (AFTER), `fn_stock_sala`, `chk_stock_sala_cantidad` | 33 a 40, demo de concurrencia |
| RN-10 estados del ingreso | ENUM `estado_documento`, `trg_ingreso_estado`, `sp_procesar_ingreso` | 41 a 52 |
| RN-11 estados y fecha de la transferencia | `trg_transferencia_estado`, `trg_transferencia_fecha`, `sp_procesar_transferencia` | 53 a 64 |
| RN-12 renglones bloqueados fuera de confección | `trg_renglon_ingreso_bloqueo`, `trg_renglon_transferencia_bloqueo` | 65, 66, 67, 68 |
| RN-13 auditoría de precio | `trg_vino_auditoria_precio` (AFTER UPDATE) + tabla `auditoria_precio`, sin UPDATE ni DELETE para la API | 69 a 73 |
| RN-14 no borrar con movimientos | FK con ON DELETE RESTRICT hacia vino, bodega y transportista | 74, 75, 76, 77 |
| RN-15 positivos y graduación entre 5 y 20 | CHECK de cantidades, superficies, kilos, precios y `chk_vino_graduacion` | 78 a 84 |
| Roles | `007_roles.sql` | 85 a 90 |

## Criterios de aceptación

- [x] Se alcanzan todos los mínimos de la tabla de requisitos. PK en las 30 tablas, 36 FK con ON DELETE y ON UPDATE explícitos, 12 UNIQUE, 35 CHECK (5 entre columnas), 16 DEFAULT, 5 ENUM y 2 DOMAIN, 8 funciones, 2 procedimientos, 13 triggers (BEFORE, AFTER y constraint triggers diferidos), 4 vistas y 3 roles. Se ve en `docs/resultados/minimos_etapa2.txt`, generado con `db/tests/minimos.sql`.
- [x] Cada regla RN-01 a RN-15 tiene su mecanismo y su caso de prueba. Tabla de trazabilidad de arriba y resumen de `db_tests.sql` con `reglas_cubiertas = 15`.
- [x] Los casos que deben fallar fallan con un mensaje de error claro y los que deben funcionar funcionan. `docs/resultados/db_tests.txt`: 90 de 90 ok, y cada error muestra su SQLSTATE y el mensaje de la regla.
- [x] Procesar una transferencia sin stock suficiente no deja ningún cambio a medias. Casos 56, 57, 59 y 60.
- [x] La API podrá conectarse con un rol que no es propietario y no tiene permisos de sobra. `bodega_app` no es superusuario ni dueño, no puede crear tablas, vaciarlas ni tocar la auditoría (casos 73 y 85 a 88, y la última tabla de `docs/resultados/minimos_etapa2.txt`).
