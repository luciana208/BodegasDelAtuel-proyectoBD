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
