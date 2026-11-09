-- muestra con que usuario y con que cifrado se esta conectado
SELECT current_user AS usuario, current_database() AS base, ssl, version AS version_tls, cipher AS cifrado
  FROM pg_stat_ssl
 WHERE pid = pg_backend_pid();
