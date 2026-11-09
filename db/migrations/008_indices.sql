-- indices disenados a partir de los planes de ejecucion

/* compuesto: ventas de una sala en un rango de fechas (s3, s11 y el tablero).
   va primero la sala porque se compara por igualdad y despues la fecha, que se filtra
   por rango: asi las filas de una sala quedan juntas y ordenadas por fecha */
CREATE INDEX idx_comprobante_sala_fecha ON comprobante (id_sala, fecha);

/* brin sobre la fecha del comprobante: los comprobantes se cargan en orden de fecha,
   asi que cada bloque de paginas cubre un rango corto de dias. sirve para filtrar
   periodos de todas las salas (s8, d1) y ocupa unas pocas paginas */
CREATE INDEX idx_comprobante_fecha_brin ON comprobante USING BRIN (fecha);

/* clave foranea: compras de un cliente (s12, d4, d6). tambien la usa el restrict
   cuando se borra un cliente, que si no tiene que recorrer todos los comprobantes */
CREATE INDEX idx_comprobante_cliente ON comprobante (id_cliente);

/* clave foranea con include: ventas de un vino. con la cantidad incluida las sumas
   por vino se resuelven leyendo solo el indice (s1, s2, u5 y el restrict de rn-14) */
CREATE INDEX idx_renglon_comprobante_vino ON renglon_comprobante (cod_vino) INCLUDE (cantidad);

-- clave foranea: transferencias de un vino (s4)
CREATE INDEX idx_renglon_transferencia_vino ON renglon_transferencia (cod_vino);

/* parcial: solo las transferencias que no estan procesadas, que son muy pocas
   (s5 y la vista de pendientes) */
CREATE INDEX idx_transferencia_pendientes ON transferencia (id_sala, fecha_confeccion)
  WHERE estado <> 'procesado';
