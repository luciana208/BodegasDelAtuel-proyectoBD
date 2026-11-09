comparacion antes y despues de 008_indices.sql
mediana de 5 ejecuciones de EXPLAIN (ANALYZE, BUFFERS) con la cache caliente

| Consulta | Tiempo antes | Tiempo despues | Mejora | Recorridos antes | Recorridos despues | Filas leidas antes | Filas leidas despues | Buffers antes | Buffers despues |
|---|---|---|---|---|---|---|---|---|---|
| S1 | 70.99 ms | 82.60 ms | 0.9 veces | Seq Scan renglon_comprobante, Seq Scan vino | Seq Scan renglon_comprobante, Seq Scan vino | 508104 | 508104 | 3811 | 3811 |
| S3 | 9.39 ms | 0.12 ms | 77.0 veces | Seq Scan comprobante, Index Only Scan cliente_id_cliente_tipo_key | Bitmap Heap Scan comprobante, Bitmap Index Scan idx_comprobante_sala_fecha, Index Only Scan cliente_id_cliente_tipo_key | 150045 | 135 | 1431 | 99 |
| S4 | 0.81 ms | 0.37 ms | 2.2 veces | Seq Scan renglon_transferencia, Seq Scan transferencia | Bitmap Heap Scan renglon_transferencia, Bitmap Index Scan idx_renglon_transferencia_vino, Seq Scan transferencia | 13451 | 3798 | 96 | 76 |
| S8 | 13.41 ms | 2.97 ms | 4.5 veces | Seq Scan comprobante | Bitmap Heap Scan comprobante, Bitmap Index Scan idx_comprobante_fecha_brin | 150000 | 13036 | 1287 | 130 |
| S12 | 135802.67 ms | 596.49 ms | 227.7 veces | Seq Scan cliente, Seq Scan vino, Seq Scan bodega, Seq Scan comprobante, Index Only Scan renglon_comprobante_pkey | Seq Scan cliente, Seq Scan vino, Seq Scan bodega, Bitmap Heap Scan comprobante, Bitmap Index Scan idx_comprobante_cliente, Index Only Scan renglon_comprobante_pkey | 3568282272 | 547563 | 30641446 | 669317 |

creacion de los indices de 008
| Indice | Tiempo de creacion | Tamanio |
|---|---|---|
| idx_comprobante_sala_fecha | 0.10 s | 2360 kB |
| idx_comprobante_fecha_brin | 0.02 s | 24 kB |
| idx_comprobante_cliente | 0.08 s | 1424 kB |
| idx_renglon_comprobante_vino | 0.27 s | 11 MB |
| idx_renglon_transferencia_vino | 0.01 s | 96 kB |
| idx_transferencia_pendientes | 0.00 s | 16 kB |

costo de escritura: INSERT ... SELECT de toda la tabla en una copia con los mismos indices
| Tabla | Filas | Sin los indices de 008 | Con los indices de 008 | Diferencia |
|---|---|---|---|---|
| comprobante | 150000 | 0.39 s | 0.85 s | +117 % |
| renglon_comprobante | 506878 | 1.07 s | 1.79 s | +67 % |

indices evaluados y descartados
- idx_comprobante_fecha_btree: b-tree sobre la fecha en lugar del brin, probado con S8. tamanio 1040 kB
  con los indices de 008: 2.97 ms, Bitmap Heap Scan comprobante, Bitmap Index Scan idx_comprobante_fecha_brin, filas leidas 13036, buffers 130
  con idx_comprobante_fecha_btree: 1.98 ms, Index Scan idx_comprobante_fecha_btree, filas leidas 6409, buffers 62, lo usa el planificador: si
- idx_comprobante_fecha_sala: compuesto con las columnas al reves, probado con las ventas de la sala 1 del ultimo anio. tamanio 2360 kB
  con los indices de 008: 0.51 ms, Bitmap Heap Scan comprobante, Bitmap Index Scan idx_comprobante_sala_fecha, filas leidas 3332, buffers 215
  con idx_comprobante_fecha_sala: 0.73 ms, Bitmap Heap Scan comprobante, Bitmap Index Scan idx_comprobante_fecha_sala, filas leidas 3332, buffers 262, lo usa el planificador: si
- idx_cliente_tipo: indice sobre el tipo de cliente, probado trayendo los socios. tamanio 152 kB
  con los indices de 008: 2.62 ms, Seq Scan cliente, filas leidas 20000, buffers 320
  con idx_cliente_tipo: 2.64 ms, Seq Scan cliente, filas leidas 20000, buffers 320, lo usa el planificador: no

caso en que el planificador no usa un indice existente
  SELECT id_sala, count(*), SUM(total) FROM comprobante WHERE id_sala BETWEEN 2 AND 30 GROUP BY id_sala
  la condicion deja pasar el 93.5 % de los comprobantes
  plan elegido: Seq Scan comprobante, 35.86 ms
  forzando el indice con enable_seqscan = off: Bitmap Heap Scan comprobante, Bitmap Index Scan idx_comprobante_sala_fecha, 37.40 ms
