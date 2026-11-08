/* roles y privilegios. el propietario es el rol que corre las migraciones y es dueno
   de todos los objetos. las claves de los otros dos roles no van aca: las asigna
   009_claves_roles.sh leyendo variables de entorno */

-- rol de lectura y escritura que usa la api, y rol de solo lectura para reportes
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bodega_app') THEN
    CREATE ROLE bodega_app LOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bodega_lectura') THEN
    CREATE ROLE bodega_lectura LOGIN;
  END IF;
END;
$$;

-- se quitan los privilegios que postgres da por defecto a public
DO $$
BEGIN
  EXECUTE format('REVOKE ALL ON DATABASE %I FROM PUBLIC', current_database());
  EXECUTE format('GRANT CONNECT ON DATABASE %I TO bodega_app, bodega_lectura', current_database());
END;
$$;

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
REVOKE EXECUTE ON ALL ROUTINES IN SCHEMA public FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON ROUTINES FROM PUBLIC;

-- api: usa el esquema, lee y escribe datos, ejecuta funciones y procedimientos
GRANT USAGE ON SCHEMA public TO bodega_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO bodega_app;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO bodega_app;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA public TO bodega_app;

-- la auditoria solo se agrega, no se modifica ni se borra
REVOKE UPDATE, DELETE ON auditoria_precio FROM bodega_app;

-- reportes: solo lectura
GRANT USAGE ON SCHEMA public TO bodega_lectura;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO bodega_lectura;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO bodega_lectura;
