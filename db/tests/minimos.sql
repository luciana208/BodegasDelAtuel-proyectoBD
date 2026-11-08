-- cuenta los elementos de la base: constraints, tipos, funciones, triggers, vistas y privilegios de los roles
\pset pager off
SELECT 'primary key' AS elemento, count(*) FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace WHERE n.nspname = 'public' AND contype = 'p'
UNION ALL SELECT 'tablas', count(*) FROM pg_tables WHERE schemaname = 'public'
UNION ALL SELECT 'foreign key', count(*) FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace WHERE n.nspname = 'public' AND contype = 'f'
UNION ALL SELECT 'unique', count(*) FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace WHERE n.nspname = 'public' AND contype = 'u'
UNION ALL SELECT 'check (tablas)', count(*) FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace WHERE n.nspname = 'public' AND contype = 'c' AND conrelid <> 0
UNION ALL SELECT 'check entre columnas', count(*) FROM pg_constraint c WHERE contype = 'c' AND conrelid <> 0 AND array_length(conkey, 1) > 1
UNION ALL SELECT 'default', count(*) FROM pg_attrdef d JOIN pg_class c ON c.oid = d.adrelid JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public'
UNION ALL SELECT 'enum', count(*) FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'public' AND typtype = 'e'
UNION ALL SELECT 'domain', count(*) FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'public' AND typtype = 'd'
UNION ALL SELECT 'funciones (sin las de trigger)', count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' AND prokind = 'f' AND prorettype <> 'trigger'::regtype
UNION ALL SELECT 'procedimientos', count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' AND prokind = 'p'
UNION ALL SELECT 'triggers', count(*) FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND NOT tgisinternal
UNION ALL SELECT 'vistas', count(*) FROM pg_views WHERE schemaname = 'public'
UNION ALL SELECT 'roles bodega_*', count(*) FROM pg_roles WHERE rolname LIKE 'bodega%';

SELECT c.relname AS tabla, t.tgname AS trigger,
       CASE WHEN t.tgconstraint <> 0 THEN 'constraint trigger diferido'
            WHEN t.tgtype & 2 = 2 THEN 'before' ELSE 'after' END AS momento,
       p.proname AS funcion
  FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_proc p ON p.oid = t.tgfoid
 WHERE NOT t.tgisinternal ORDER BY 1, 2;

SELECT p.proname AS funcion, CASE p.provolatile WHEN 'i' THEN 'immutable' WHEN 's' THEN 'stable' ELSE 'volatile' END AS volatilidad,
       pg_get_function_arguments(p.oid) AS parametros
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND prokind = 'f' AND prorettype <> 'trigger'::regtype ORDER BY 1;

SELECT r.rolname, has_table_privilege(r.rolname, 'vino', 'SELECT') AS select_vino,
       has_table_privilege(r.rolname, 'vino', 'INSERT') AS insert_vino,
       has_table_privilege(r.rolname, 'auditoria_precio', 'DELETE') AS delete_auditoria,
       has_table_privilege(r.rolname, 'vino', 'TRUNCATE') AS truncate_vino,
       has_schema_privilege(r.rolname, 'public', 'CREATE') AS create_en_public,
       r.rolsuper AS superusuario
  FROM pg_roles r WHERE r.rolname IN ('bodega_app', 'bodega_lectura') ORDER BY 1;
