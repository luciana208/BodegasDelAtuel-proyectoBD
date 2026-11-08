-- esquema fisico de bodegas del atuel

-- tipos enumerados
CREATE TYPE estado_documento AS ENUM ('en_confeccion', 'terminado', 'procesado');
CREATE TYPE tipo_cliente AS ENUM ('socio', 'distribuidor', 'exportador');
CREATE TYPE tipo_cepa AS ENUM ('tinta', 'blanca');
CREATE TYPE tipo_vino AS ENUM ('tinto', 'blanco', 'rosado', 'espumante');
CREATE TYPE dia_semana AS ENUM ('lunes', 'martes', 'miercoles', 'jueves', 'viernes', 'sabado', 'domingo');

-- dominios
CREATE DOMAIN cuit_dom AS CHAR(11)
  CHECK (VALUE ~ '^[0-9]{11}$');

CREATE DOMAIN cod_postal_dom AS VARCHAR(4)
  CHECK (VALUE ~ '^[0-9]{4}$');

-- localidades, salas y empleados
CREATE TABLE departamento (
   id_departamento SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
   nombre          VARCHAR(40) NOT NULL,
   provincia       VARCHAR(40) NOT NULL
);

CREATE TABLE localidad (
   id_localidad       INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
   nombre             VARCHAR(60)    NOT NULL,
   cod_postal         cod_postal_dom NOT NULL,
   id_departamento    SMALLINT       NOT NULL
                      REFERENCES departamento (id_departamento) ON DELETE RESTRICT ON UPDATE RESTRICT,
   encargado_regional VARCHAR(80)    NOT NULL
);

CREATE TABLE sala_venta (
   id_sala      INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
   calle        VARCHAR(80) NOT NULL,
   numero       INTEGER     NOT NULL,
   dia_cierre   dia_semana  NOT NULL,
   id_localidad INTEGER     NOT NULL
                REFERENCES localidad (id_localidad) ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE TABLE empleado (
   cuit          cuit_dom      PRIMARY KEY,
   nombre        VARCHAR(80)   NOT NULL,
   fecha_ingreso DATE          NOT NULL,
   salario       NUMERIC(12,2) NOT NULL,
   id_sala       INTEGER       NOT NULL
                 REFERENCES sala_venta (id_sala) ON DELETE RESTRICT ON UPDATE RESTRICT
);

-- produccion de uva
CREATE TABLE cepa (
   id_cepa SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
   nombre  VARCHAR(40) NOT NULL,
   tipo    tipo_cepa   NOT NULL
);

CREATE TABLE finca (
   id_finca        INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
   nombre          VARCHAR(80)  NOT NULL,
   superficie_ha   NUMERIC(8,2) NOT NULL,
   id_departamento SMALLINT     NOT NULL
                   REFERENCES departamento (id_departamento) ON DELETE RESTRICT ON UPDATE RESTRICT
);

-- entidad debil: se identifica por la finca y el numero dentro de ella
CREATE TABLE parcela (
   id_finca        INTEGER      NOT NULL
                   REFERENCES finca (id_finca) ON DELETE CASCADE ON UPDATE RESTRICT,
   nro_parcela     SMALLINT     NOT NULL,
   superficie_ha   NUMERIC(7,2) NOT NULL,
   anio_plantacion SMALLINT     NOT NULL,
   id_cepa         SMALLINT     NOT NULL
                   REFERENCES cepa (id_cepa) ON DELETE RESTRICT ON UPDATE RESTRICT,
   PRIMARY KEY (id_finca, nro_parcela)
);

CREATE TABLE bodega (
   cuit         cuit_dom     PRIMARY KEY,
   razon_social VARCHAR(100) NOT NULL,
   domicilio    VARCHAR(120) NOT NULL
);

CREATE TABLE lote_uva (
   nro_lote      INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
   id_finca      INTEGER       NOT NULL,
   nro_parcela   SMALLINT      NOT NULL,
   campania      SMALLINT      NOT NULL,
   fecha_cosecha DATE          NOT NULL,
   kilos         NUMERIC(10,2) NOT NULL,
   cuit_bodega   cuit_dom      NOT NULL
                 REFERENCES bodega (cuit) ON DELETE RESTRICT ON UPDATE CASCADE,
   FOREIGN KEY (id_finca, nro_parcela)
                 REFERENCES parcela (id_finca, nro_parcela) ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE TABLE analisis_calidad (
   id_analisis  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
   nro_lote     INTEGER      NOT NULL
                REFERENCES lote_uva (nro_lote) ON DELETE CASCADE ON UPDATE RESTRICT,
   fecha        DATE         NOT NULL,
   brix         NUMERIC(4,1) NOT NULL,
   ph           NUMERIC(3,2) NOT NULL,
   acidez_total NUMERIC(4,2) NOT NULL
);

-- vinos, composicion y maridajes
CREATE TABLE vino (
   cod_vino    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
   nombre      VARCHAR(80)   NOT NULL,
   tipo        tipo_vino     NOT NULL,
   anada       SMALLINT      NOT NULL,
   volumen_ml  INTEGER       NOT NULL,
   graduacion  NUMERIC(4,2)  NOT NULL,
   precio      NUMERIC(10,2) NOT NULL,
   cuit_bodega cuit_dom      NOT NULL
               REFERENCES bodega (cuit) ON DELETE RESTRICT ON UPDATE CASCADE
);

-- n:m entre vino y cepa con el porcentaje de corte
CREATE TABLE composicion (
   cod_vino   INTEGER      NOT NULL
              REFERENCES vino (cod_vino) ON DELETE CASCADE ON UPDATE RESTRICT,
   id_cepa    SMALLINT     NOT NULL
              REFERENCES cepa (id_cepa) ON DELETE RESTRICT ON UPDATE RESTRICT,
   porcentaje NUMERIC(5,2) NOT NULL,
   PRIMARY KEY (cod_vino, id_cepa)
);

CREATE TABLE maridaje (
   id_maridaje          SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
   nombre               VARCHAR(60)  NOT NULL,
   temperatura_servicio NUMERIC(4,1) NOT NULL
);

CREATE TABLE vino_maridaje (
   cod_vino    INTEGER  NOT NULL
               REFERENCES vino (cod_vino) ON DELETE CASCADE ON UPDATE RESTRICT,
   id_maridaje SMALLINT NOT NULL
               REFERENCES maridaje (id_maridaje) ON DELETE CASCADE ON UPDATE RESTRICT,
   PRIMARY KEY (cod_vino, id_maridaje)
);

/* jerarquia de clientes: supertipo cliente y una tabla por subtipo.
   cada subtipo repite la columna tipo con un valor fijo y la usa en la
   clave foranea compuesta, asi un cliente solo puede estar en el subtipo
   que dice su columna tipo */
CREATE TABLE cliente (
   id_cliente     INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
   nombre         VARCHAR(120) NOT NULL,
   tipo_documento VARCHAR(4)   NOT NULL,
   nro_documento  VARCHAR(13)  NOT NULL,
   direccion      VARCHAR(120) NOT NULL,
   id_localidad   INTEGER      NOT NULL
                  REFERENCES localidad (id_localidad) ON DELETE RESTRICT ON UPDATE RESTRICT,
   fecha_alta     DATE         NOT NULL,
   tipo           tipo_cliente NOT NULL,
   descuento      NUMERIC(5,2) NOT NULL,
   UNIQUE (id_cliente, tipo)
);

CREATE TABLE socio (
   id_cliente INTEGER      PRIMARY KEY,
   tipo       tipo_cliente NOT NULL DEFAULT 'socio' CHECK (tipo = 'socio'),
   nro_carnet INTEGER      NOT NULL,
   FOREIGN KEY (id_cliente, tipo)
              REFERENCES cliente (id_cliente, tipo) ON DELETE CASCADE ON UPDATE RESTRICT
);

CREATE TABLE distribuidor (
   id_cliente       INTEGER      PRIMARY KEY,
   tipo             tipo_cliente NOT NULL DEFAULT 'distribuidor' CHECK (tipo = 'distribuidor'),
   zona_cobertura   VARCHAR(80)  NOT NULL,
   nro_habilitacion VARCHAR(20)  NOT NULL,
   FOREIGN KEY (id_cliente, tipo)
                    REFERENCES cliente (id_cliente, tipo) ON DELETE CASCADE ON UPDATE RESTRICT
);

CREATE TABLE exportador (
   id_cliente   INTEGER      PRIMARY KEY,
   tipo         tipo_cliente NOT NULL DEFAULT 'exportador' CHECK (tipo = 'exportador'),
   pais_destino VARCHAR(60)  NOT NULL,
   FOREIGN KEY (id_cliente, tipo)
                REFERENCES cliente (id_cliente, tipo) ON DELETE CASCADE ON UPDATE RESTRICT
);

CREATE TABLE permiso_exportacion (
   cod_permiso       VARCHAR(20) PRIMARY KEY,
   id_cliente        INTEGER     NOT NULL
                     REFERENCES exportador (id_cliente) ON DELETE CASCADE ON UPDATE RESTRICT,
   fecha_emision     DATE        NOT NULL,
   fecha_vencimiento DATE        NOT NULL
);

-- ventas
CREATE TABLE comprobante (
   nro_comprobante INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
   fecha           DATE          NOT NULL,
   id_cliente      INTEGER       NOT NULL
                   REFERENCES cliente (id_cliente) ON DELETE RESTRICT ON UPDATE RESTRICT,
   id_sala         INTEGER       NOT NULL
                   REFERENCES sala_venta (id_sala) ON DELETE RESTRICT ON UPDATE RESTRICT,
   subtotal        NUMERIC(12,2) NOT NULL,
   descuento       NUMERIC(12,2) NOT NULL,
   total           NUMERIC(12,2) NOT NULL
);

CREATE TABLE renglon_comprobante (
   nro_comprobante INTEGER       NOT NULL
                   REFERENCES comprobante (nro_comprobante) ON DELETE CASCADE ON UPDATE RESTRICT,
   cod_vino        INTEGER       NOT NULL
                   REFERENCES vino (cod_vino) ON DELETE RESTRICT ON UPDATE RESTRICT,
   cantidad        INTEGER       NOT NULL,
   precio_unitario NUMERIC(10,2) NOT NULL,
   porc_descuento  NUMERIC(5,2)  NOT NULL,
   subtotal        NUMERIC(12,2) NOT NULL,
   PRIMARY KEY (nro_comprobante, cod_vino)
);

-- stock de cada sala y del deposito central
CREATE TABLE stock_sala (
   id_sala  INTEGER NOT NULL
            REFERENCES sala_venta (id_sala) ON DELETE RESTRICT ON UPDATE RESTRICT,
   cod_vino INTEGER NOT NULL
            REFERENCES vino (cod_vino) ON DELETE RESTRICT ON UPDATE RESTRICT,
   cantidad INTEGER NOT NULL,
   PRIMARY KEY (id_sala, cod_vino)
);

CREATE TABLE stock_deposito (
   cod_vino INTEGER PRIMARY KEY
            REFERENCES vino (cod_vino) ON DELETE RESTRICT ON UPDATE RESTRICT,
   cantidad INTEGER NOT NULL
);
