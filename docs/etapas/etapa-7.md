# Etapa 7: front

## Qué hicimos

El front está en `front/` y es HTML, CSS y JavaScript sin frameworks ni compilación. Es una sola página: cada pantalla es una `section` que se muestra u oculta desde el menú, y los datos se piden a la API con `fetch`, sin recargar. Chart.js se carga desde el CDN de jsDelivr (versión 4.4.1) y se usa solo para el gráfico del tablero.

```
front/
  index.html        las cinco pantallas
  css/estilos.css
  js/config.js      url base de la api
  js/api.js         todas las llamadas a la api
  js/app.js         logica de cada pantalla
  Dockerfile        nginx
  config-api.sh     genera js/config.js con la variable API_URL al arrancar
```

Se sirve con nginx en el mismo `docker-compose.yml`, así que `docker compose up` levanta base, API y front. Queda en `http://localhost:8080`. La URL de la API se configura con la variable `API_URL` (por defecto `http://localhost:8000`): al arrancar, el contenedor escribe `js/config.js` con ese valor. Fuera de Docker se puede editar `js/config.js` a mano.

`api.js` concentra todas las llamadas. Si la API responde con error, lanza una excepción con el campo `error` de la respuesta tal cual (y el `detalle` si viene), y cada pantalla lo muestra en un recuadro rojo. No hay mensajes genéricos que reemplacen a los de la base.

## Pantallas

| Pantalla | Qué permite |
|---|---|
| Catálogo | Listado paginado (15 por página) con filtros por nombre, tipo, cepa, bodega y añada. "Ver" muestra la ficha con la composición, los maridajes y el stock; "Editar" abre el formulario. |
| Alta de vino | Formulario con los datos del vino, filas de composición (cepa y porcentaje) que se agregan y quitan, y maridajes. Sirve también para editar. Si los porcentajes no suman 100 se muestra el error del constraint trigger: `Los porcentajes de corte del vino 410 suman 90.00 y tienen que sumar 100 (RN-05)`. |
| Nueva venta | Se elige cliente (con búsqueda por nombre) y sala, se agregan vinos con su cantidad y se registra. El comprobante que se muestra después (precios, descuento, subtotales y total) es el que devuelve la API. Si no hay stock se ve el mensaje de la regla, por ejemplo `Stock insuficiente del vino 250 en la sala 1: hay 0 y se piden 9999 (RN-09)`. |
| Transferencias | Crear una transferencia para una sala, abrir una existente, cargar renglones y pasarla de estado. La carga de renglones y "Terminar" solo están habilitados en confección, y "Procesar" solo cuando está terminada. Abajo se listan las últimas transferencias. |
| Tablero | Los 10 vinos más vendidos, un gráfico de barras con el monto vendido por sala en el último trimestre y los vinos sin stock en la sala que se elija (con stock en el depósito). |

## El front no calcula

El front no calcula importes, descuentos ni stock. En la venta solo arma la lista de vinos y cantidades que manda a `POST /comprobantes`; el total lo muestra a partir de la respuesta. El stock que aparece en la ficha y en las transferencias también viene de la API. Lo único que hace con los números es darles formato de moneda.

## Prueba contra la API real

Recorrimos las cinco pantallas con un navegador sin interfaz (Playwright) contra los contenedores levantados con la base recién cargada. La salida está en `docs/resultados/front/recorrido_pantallas.txt`:

- Catálogo: 409 vinos en 28 páginas; filtrando blancos quedan 98 y la página 2 trae otros vinos; la ficha muestra composición y stock.
- Alta de vino: con 60 + 30 aparece el error RN-05; con 60 + 40 se guarda, y después se edita el precio.
- Nueva venta: con 9.999 botellas aparece el error de stock y no queda ningún comprobante (el número que se había reservado no existe en la base); con 2 botellas se registra el comprobante con subtotal, 20 % de descuento del distribuidor y total calculados por la base.
- Transferencias: al crearla "Procesar" está deshabilitado; terminarla vacía muestra el error RN-11; con un renglón se termina, se deshabilitan la carga y "Terminar", y al procesar queda en `procesado`.
- Tablero: 10 vinos en el ranking, 30 barras en el gráfico y la lista de vinos sin stock cambia al elegir otra sala.

Los únicos errores que registró la consola del navegador son las respuestas 409 que provocamos a propósito.

## Criterios de aceptación

- [x] Las cinco pantallas funcionan contra la API real. Recorrido en `docs/resultados/front/recorrido_pantallas.txt`.
- [x] Una venta sin stock muestra el mensaje de la regla y no deja datos a medias. El mensaje es el del trigger (RN-09) y la venta se hace en una sola transacción en la API (`crear_comprobante`), así que no queda la cabecera.
- [x] El front no contiene lógica de cálculo de importes ni de stock. `front/js/app.js` solo muestra lo que devuelve la API; la venta envía solo vino y cantidad.
