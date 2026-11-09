# Etapa 8: despliegue en la nube

## Qué hicimos

Dejamos todo preparado para publicar el sistema en la nube: la base en un servicio gestionado de PostgreSQL y la API y el front en Render. Los scripts sirven para cualquier proveedor, porque solo usan las variables estándar de conexión de PostgreSQL (`PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD` y `PGSSLMODE`) y siempre conectan con `sslmode=require`.

Como todavía no creamos las cuentas, probamos todo el circuito contra un servidor de ensayo en nuestra máquina que se comporta como el de un proveedor (ver "Ensayo local" más abajo).

### Proveedores

| | Neon | Supabase |
|---|---|---|
| Qué es | PostgreSQL gestionado | PostgreSQL gestionado más otros servicios (autenticación, almacenamiento) |
| Versión | 17 por defecto | La que ofrezca al crear el proyecto (a verificar) |
| Rol que da | Un propietario de la base sin superusuario, que puede crear roles | Rol `postgres` del proyecto, con más privilegios |
| Plan gratuito (a verificar) | Alrededor de 0,5 GB por proyecto; la base se suspende sola si no se usa y se despierta en la primera conexión | Alrededor de 500 MB; el proyecto se pausa después de una semana sin uso |
| SSL | Obligatorio | Disponible, se puede exigir |
| Restricción por IP | Existe ("IP Allow"), pero hay que confirmar si está en el plan gratuito | Existe ("Network Restrictions"), hay que confirmar en qué planes |

Nuestra propuesta es **Neon para la base** porque da exactamente lo que usamos (PostgreSQL puro, propietario sin superusuario, SSL obligatorio) y **Render para la API y el front**: la API como servicio Docker con el mismo `api/Dockerfile` y el front como sitio estático. En el plan gratuito de Render los servicios web se duermen después de un rato sin uso y el primer pedido tarda en responder; para la demo conviene abrir la página unos minutos antes. Los límites de los planes cambian seguido, así que antes de elegir hay que revisarlos en las páginas de cada proveedor y anotar en el informe los que estén vigentes.

La base completa ocupa unos 89 MB con los índices (`pg_database_size`), así que probablemente entre en el plan gratuito. Si no entra, está preparada la carga reducida.

## Archivos

| Archivo | Para qué |
|---|---|
| `.env.nube.example` | Variables de la base en la nube. Se copia a `.env.nube`, que está en `.gitignore` |
| `db/nube/aplicar_migraciones.sh` | Aplica `001` a `008` en orden con el rol propietario y después `009_claves_roles.sh`. Al final muestra con qué usuario y con qué cifrado quedó conectado |
| `db/nube/carga_reducida.sh` | Corre `db/seed/cargar.py` con menos volumen (3.000 clientes, 15.000 comprobantes, unos 50.000 renglones) y las consultas de control |
| `db/nube/backup.sh` | `pg_dump` en formato custom |
| `db/nube/restaurar.sh` | Crea una base nueva, restaura el backup con `pg_restore` y compara los conteos de las 30 tablas con la base de origen |
| `db/nube/probar_regla.sh` | Contra la URL de la API: muestra `/salud` e intenta vender un vino sin stock |
| `render.yaml` | Blueprint de Render con la API y el front |
| `db/nube/ensayo_local.sh` | El ensayo local de todo lo anterior |

Los scripts se corren con el servicio `nube` del compose, que tiene psql, pg_dump y Python y lee `.env.nube`:

```
docker compose run --rm nube bash db/nube/aplicar_migraciones.sh
docker compose run --rm nube bash db/nube/carga_reducida.sh
docker compose run --rm nube bash db/nube/backup.sh
docker compose run --rm nube bash db/nube/restaurar.sh backups/<archivo>.dump
```

Las herramientas del contenedor son de PostgreSQL 17, así que la base en la nube tiene que ser versión 17 (es la que crea Neon por defecto). Con una base 16 el backup se genera bien pero `pg_restore` falla al restaurarlo en otra base 16.

### API

- Lee la conexión de `DATABASE_URL` si existe. En la nube va la cadena del rol `bodega_app`, por ejemplo `postgresql://bodega_app:<clave>@<host>/bodegas?sslmode=require`. Nunca la del propietario.
- `DB_SSLMODE=require` fuerza el cifrado aunque la cadena no lo diga.
- `/salud` muestra el usuario y si la conexión va cifrada (`"ssl": true`).
- Toma el puerto de la variable `PORT`, que es la que usa Render.
- `CORS_ORIGINS` tiene que tener la URL pública del front.

### Front

En Render se publica como sitio estático. Al construirse, el comando del `render.yaml` escribe `js/config.js` con la variable `API_URL`, que es la URL pública de la API.

## Ensayo local

`db/nube/ensayo_local.sh` levanta un PostgreSQL 17 aparte que imita al de un proveedor: genera su propio certificado, exige SSL (`pg_hba.conf` rechaza cualquier conexión sin cifrar) y tiene un rol propietario `bodega_owner` sin superusuario, con permiso para crear roles y bases, igual que el que da Neon. Las claves se generan al azar en cada ensayo. Sobre ese servidor corre los mismos scripts que vamos a usar en la nube. La salida quedó en `docs/resultados/nube/`:

| Paso | Resultado | Archivo |
|---|---|---|
| Migraciones con el propietario | Las 8 migraciones y las claves de los roles se aplicaron sin errores, conectado como `bodega_owner` con TLS 1.3 | `migraciones.txt` |
| Carga reducida | 50.353 renglones de comprobante, 15.000 comprobantes y 3.000 clientes; los 23 controles dan 0 | `carga_reducida.txt`, `carga_control.txt` |
| Backup y restauración | El backup se restauró en `bodegas_restaurada` y los conteos de las 30 tablas coinciden | `backup_restauracion.txt`, `conteos_origen.txt`, `conteos_restaurada.txt` |
| Conexión sin SSL | Rechazada: `pg_hba.conf rejects connection ... no encryption` | `conexion_sin_ssl.txt` |
| Conexión con clave equivocada | Rechazada: `password authentication failed` | `conexion_clave_incorrecta.txt` |
| API contra esa base | Conectada como `bodega_app` con `"ssl": true`; la venta sin stock devuelve 409 con el mensaje de RN-09 | `regla_en_la_nube.txt` |

Esto prueba que los scripts y la configuración funcionan con una base que exige SSL y con un propietario que no es superusuario. Lo que no se puede probar sin las cuentas es la URL pública, el HTTPS de Render y la restricción de acceso por IP del proveedor.

## Pasos manuales que quedan

1. Revisar los planes vigentes de Neon, Supabase y Render, confirmar la elección y anotar los límites en el informe. Confirmar en especial si el plan gratuito de la base permite restringir el acceso por IP; si no, decidir entre pasar a un plan que lo tenga o usar el proveedor que sí lo permita, y justificarlo.
2. Crear la cuenta y el proyecto en Neon con PostgreSQL 17, una base `bodegas` y un rol propietario (por ejemplo `bodega_owner`).
3. Copiar `.env.nube.example` a `.env.nube` y completar host, base, usuario y clave del propietario, más dos claves nuevas y largas para `APP_DB_PASSWORD` y `LECTURA_DB_PASSWORD`.
4. Correr `docker compose run --rm nube bash db/nube/aplicar_migraciones.sh` y guardar la salida.
5. Cargar los datos: probar primero la carga completa (`docker compose run --rm -e CANT_CLIENTES=20000 -e CANT_COMPROBANTES=150000 -e CANT_INGRESOS=2000 -e TRANSFERENCIAS_POR_SALA=100 nube bash db/nube/carga_reducida.sh`) y si no entra en el plan usar la reducida (`docker compose run --rm nube bash db/nube/carga_reducida.sh`), justificándolo en el informe.
6. Crear la cuenta en Render y crear los servicios desde el `render.yaml` (Blueprint) apuntando al repositorio oficial.
7. Cargar en Render las variables: en la API `DATABASE_URL` con el rol `bodega_app` y `sslmode=require`, y `CORS_ORIGINS` con la URL del front; en el front `API_URL` con la URL de la API. Después volver a desplegar el front.
8. Abrir `https://<api>/salud` y verificar que `usuario` sea `bodega_app` y `ssl` sea `true`.
9. Restringir el acceso a la base por IP (o red interna) en el panel del proveedor y probar que una conexión desde una IP no permitida es rechazada. Si Render no tiene IP fija en el plan gratuito, anotar qué rango se habilitó y por qué.
10. Correr `docker compose run --rm nube bash db/nube/backup.sh` y `docker compose run --rm nube bash db/nube/restaurar.sh backups/<archivo>.dump`, y guardar la salida con los conteos.
11. Correr `bash db/nube/probar_regla.sh https://<api>` y hacer una venta sin stock desde el front publicado. Sacar las capturas.
12. Completar la URL pública en el README.
13. Revisar que no haya secretos en el historial del repositorio oficial (`git log -p | grep -i password`) y que `.env` y `.env.nube` no estén subidos.

## Criterios de aceptación

Estos criterios dependen del despliegue real, que hace el grupo con los pasos de arriba. Lo que dejamos preparado y probado para cada uno:

- [ ] Cualquier persona puede abrir la URL pública y usar el sistema. Pendiente de crear los servicios en Render (pasos 6 a 8). La configuración está en `render.yaml` y la API y el front ya funcionan en contenedores.
- [x] La conexión a la base está cifrada. Todos los scripts usan `sslmode=require` y la API `DB_SSLMODE=require`; en el ensayo la conexión fue TLS 1.3 y las conexiones sin cifrar fueron rechazadas (`docs/resultados/nube/migraciones.txt` y `conexion_sin_ssl.txt`).
- [ ] El puerto no está abierto a todo internet. Pendiente de configurar en el panel del proveedor (paso 9).
- [x] No hay secretos en el repositorio (incluido su historial). `.env` y `.env.nube` están en `.gitignore` desde el principio, las claves de los roles se toman del entorno y el ensayo genera claves al azar. Se verificó con `git log -p` en cada etapa.
- [x] El backup se restauró en una base nueva y los conteos coinciden. En el ensayo coinciden las 30 tablas (`docs/resultados/nube/backup_restauracion.txt`); falta repetirlo en la nube (paso 10).
- [x] Una regla de la base se comprobó funcionando con la API conectada por SSL a la base de ensayo (`docs/resultados/nube/regla_en_la_nube.txt`); falta repetirlo en la nube (paso 11).
