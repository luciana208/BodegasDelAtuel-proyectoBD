# Consultas

Resolución de las consultas de la sección 8 sobre la base cargada.

| Archivo | Consultas |
|---|---|
| `update.sql` | U1 a U6 |
| `insert.sql` | I1 a I6 |
| `delete.sql` | D1 a D6 |
| `select.sql` | S1 a S12 y, al final, los planes con `EXPLAIN (ANALYZE)` de S1, S3, S4, S8 y S9 a S12 |

Cada consulta tiene arriba un comentario con su código, el enunciado y la estrategia. Las que modifican datos corren cada una en su propia transacción: control previo, sentencia, control posterior y `ROLLBACK`, así los archivos se pueden correr enteros sin cambiar la base.

```
docker compose exec -T db psql -U bodega_owner -d bodegas -f - < consultas/update.sql
docker compose exec -T db psql -U bodega_owner -d bodegas -f - < consultas/insert.sql
docker compose exec -T db psql -U bodega_owner -d bodegas -f - < consultas/delete.sql
docker compose exec -T db psql -U bodega_owner -d bodegas -f - < consultas/select.sql
```

Los valores concretos (sala, vino, bodega, localidad, cliente) están en variables de psql definidas con `\set` justo antes de cada consulta, o al principio de `select.sql`. Para probar con otro valor se cambia ahí. Los elegimos entre los datos de la carga con semilla 2026 que no dependen de la fecha en que se corre la carga, así siguen sirviendo aunque se vuelva a cargar otro día:

| Variable | Valor | Qué es |
|---|---|---|
| `sala`, `sala_i3` | 1 | Sala de San Rafael, la que más vende |
| `vino` | 224 | Malbec Gran Reserva de 1500 ml, de los más pedidos por transferencias |
| `bodega` (select) | Bodega Boutique Cordoba | Bodega con tres vinos |
| `bodega` (U3), `bodega_i6` | Bodega Gonzalez | Elabora el Malbec Reserva de 750 ml del escenario (vino 1) |
| `cliente_u1` | 50 | Un exportador con compras |
| `cliente_i3` | 1 | Un distribuidor |
| `localidad_d3` | Tupungato | Localidad con una sola sala |
| `localidad_d6` | San Rafael | |
| `transportista_i6` | Expreso Rios | |

Las salidas de la última corrida están en `docs/resultados/consultas/`.
