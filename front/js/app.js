// pantallas del front. los importes y el stock se muestran tal como los devuelve la api

const estado = {
  pagina: 1,
  tamanio: 15,
  filtros: {},
  cepas: [],
  vinoEditado: null,
  renglonesVenta: [],
  transferencia: null,
  grafico: null,
};

function $(id) {
  return document.getElementById(id);
}

function mostrarMensaje(id, texto, tipo) {
  const caja = $(id);
  caja.textContent = texto;
  caja.className = 'mensaje ' + (tipo || 'error');
}

function limpiarMensaje(id) {
  $(id).textContent = '';
}

function moneda(valor) {
  return '$ ' + Number(valor).toLocaleString('es-AR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function celda(fila, texto, clase) {
  const td = document.createElement('td');
  td.textContent = texto;
  if (clase) {
    td.className = clase;
  }
  fila.appendChild(td);
  return td;
}

function boton(texto, accion, clase) {
  const b = document.createElement('button');
  b.type = 'button';
  b.textContent = texto;
  if (clase) {
    b.className = clase;
  }
  b.addEventListener('click', accion);
  return b;
}

function llenarSelect(select, items, valor, texto, primera) {
  select.innerHTML = '';
  if (primera) {
    select.appendChild(new Option(primera, ''));
  }
  for (const item of items) {
    select.appendChild(new Option(texto(item), item[valor]));
  }
}

function nombreVino(v) {
  return v.cod_vino + ' - ' + v.nombre + ' ' + v.anada + ' ' + v.volumen_ml + ' ml';
}

// navegacion entre pantallas sin recargar
function irA(pantalla) {
  document.querySelectorAll('.pantalla').forEach((s) => s.classList.add('oculto'));
  $(pantalla).classList.remove('oculto');
  document.querySelectorAll('nav button').forEach((b) => {
    b.classList.toggle('activo', b.dataset.pantalla === pantalla);
  });
  if (pantalla === 'tablero') {
    cargarTablero();
  }
  if (pantalla === 'transferencias') {
    cargarListaTransferencias();
  }
}

// catalogo
async function cargarCatalogo() {
  limpiarMensaje('catalogo-mensaje');
  try {
    const resultado = await api.vinos({ ...estado.filtros, pagina: estado.pagina, tamanio: estado.tamanio });
    const cuerpo = $('tabla-vinos');
    cuerpo.innerHTML = '';
    for (const v of resultado.datos) {
      const fila = document.createElement('tr');
      celda(fila, v.cod_vino);
      celda(fila, v.nombre);
      celda(fila, v.tipo);
      celda(fila, v.anada);
      celda(fila, v.volumen_ml + ' ml');
      celda(fila, v.graduacion + '°');
      celda(fila, moneda(v.precio), 'numero');
      celda(fila, v.bodega);
      const acciones = celda(fila, '');
      acciones.appendChild(boton('Ver', () => verDetalle(v.cod_vino), 'secundario'));
      acciones.appendChild(boton('Editar', () => editarVino(v.cod_vino), 'secundario'));
      cuerpo.appendChild(fila);
    }
    const paginas = Math.max(1, Math.ceil(resultado.total / estado.tamanio));
    $('pagina-actual').textContent = 'Página ' + estado.pagina + ' de ' + paginas + ' (' + resultado.total + ' vinos)';
    $('pagina-anterior').disabled = estado.pagina <= 1;
    $('pagina-siguiente').disabled = estado.pagina >= paginas;
  } catch (e) {
    mostrarMensaje('catalogo-mensaje', e.message);
  }
}

async function verDetalle(cod) {
  const caja = $('detalle-vino');
  try {
    const v = await api.vino(cod);
    caja.innerHTML = '';
    const titulo = document.createElement('h3');
    titulo.textContent = nombreVino(v);
    caja.appendChild(titulo);
    const datos = document.createElement('p');
    datos.textContent = v.bodega + ' | ' + v.tipo + ' | ' + v.graduacion + '° | ' + moneda(v.precio)
      + ' | Stock: ' + v.stock_deposito + ' en depósito, ' + v.stock_salas + ' en salas, ' + v.stock_total + ' en total';
    caja.appendChild(datos);
    const tabla = document.createElement('table');
    tabla.innerHTML = '<thead><tr><th>Cepa</th><th>Tipo</th><th>Porcentaje</th></tr></thead>';
    const cuerpo = document.createElement('tbody');
    for (const c of v.composicion) {
      const fila = document.createElement('tr');
      celda(fila, c.cepa);
      celda(fila, c.tipo);
      celda(fila, c.porcentaje + ' %', 'numero');
      cuerpo.appendChild(fila);
    }
    tabla.appendChild(cuerpo);
    caja.appendChild(tabla);
    const maridajes = document.createElement('p');
    maridajes.textContent = 'Maridajes: ' + (v.maridajes.map((m) => m.nombre + ' (' + m.temperatura_servicio + ' °C)').join(', ') || 'sin maridajes');
    caja.appendChild(maridajes);
    caja.classList.remove('oculto');
    caja.scrollIntoView();
  } catch (e) {
    mostrarMensaje('catalogo-mensaje', e.message);
  }
}

// alta y edicion de vino
function agregarFilaCorte(idCepa, porcentaje) {
  const fila = document.createElement('tr');
  const tdCepa = document.createElement('td');
  const select = document.createElement('select');
  llenarSelect(select, estado.cepas, 'id_cepa', (c) => c.nombre + ' (' + c.tipo + ')');
  if (idCepa) {
    select.value = idCepa;
  }
  tdCepa.appendChild(select);
  fila.appendChild(tdCepa);
  const tdPorc = document.createElement('td');
  const input = document.createElement('input');
  input.type = 'number';
  input.step = '0.01';
  input.value = porcentaje || '';
  tdPorc.appendChild(input);
  fila.appendChild(tdPorc);
  const tdQuitar = document.createElement('td');
  tdQuitar.appendChild(boton('Quitar', () => fila.remove(), 'secundario'));
  fila.appendChild(tdQuitar);
  $('filas-corte').appendChild(fila);
}

function prepararFormularioVino(vino) {
  const form = $('form-vino');
  form.reset();
  limpiarMensaje('vino-mensaje');
  $('filas-corte').innerHTML = '';
  estado.vinoEditado = vino ? vino.cod_vino : null;
  $('vino-titulo').textContent = vino ? 'Editar vino ' + vino.cod_vino : 'Alta de vino';
  document.querySelectorAll('#lista-maridajes input').forEach((c) => { c.checked = false; });
  if (vino) {
    for (const campo of ['nombre', 'tipo', 'anada', 'volumen_ml', 'graduacion', 'precio', 'cuit_bodega']) {
      form.elements[campo].value = vino[campo];
    }
    for (const c of vino.composicion) {
      agregarFilaCorte(c.id_cepa, c.porcentaje);
    }
    for (const m of vino.maridajes) {
      const casilla = document.querySelector('#lista-maridajes input[value="' + m.id_maridaje + '"]');
      if (casilla) {
        casilla.checked = true;
      }
    }
  } else {
    agregarFilaCorte();
  }
}

async function editarVino(cod) {
  try {
    const vino = await api.vino(cod);
    prepararFormularioVino(vino);
    irA('vino');
  } catch (e) {
    mostrarMensaje('catalogo-mensaje', e.message);
  }
}

async function guardarVino(evento) {
  evento.preventDefault();
  const form = evento.target;
  const vino = {
    nombre: form.elements.nombre.value,
    tipo: form.elements.tipo.value,
    anada: form.elements.anada.value,
    volumen_ml: form.elements.volumen_ml.value,
    graduacion: form.elements.graduacion.value,
    precio: form.elements.precio.value,
    cuit_bodega: form.elements.cuit_bodega.value,
    composicion: [],
    maridajes: [],
  };
  document.querySelectorAll('#filas-corte tr').forEach((fila) => {
    vino.composicion.push({
      id_cepa: fila.querySelector('select').value,
      porcentaje: fila.querySelector('input').value,
    });
  });
  document.querySelectorAll('#lista-maridajes input:checked').forEach((c) => vino.maridajes.push(c.value));
  try {
    const guardado = estado.vinoEditado
      ? await api.modificarVino(estado.vinoEditado, vino)
      : await api.crearVino(vino);
    prepararFormularioVino(guardado);
    mostrarMensaje('vino-mensaje', 'Vino ' + guardado.cod_vino + ' guardado', 'ok');
    cargarCatalogo();
  } catch (e) {
    mostrarMensaje('vino-mensaje', e.message);
  }
}

// nueva venta
async function buscarClientes() {
  try {
    const resultado = await api.clientes({ nombre: $('buscar-cliente').value, tamanio: 50 });
    llenarSelect($('venta-cliente'), resultado.datos, 'id_cliente', (c) => c.id_cliente + ' - ' + c.nombre + ' (' + c.tipo + ')');
  } catch (e) {
    mostrarMensaje('venta-mensaje', e.message);
  }
}

async function buscarVinos(texto, select, mensaje) {
  try {
    const resultado = await api.vinos({ nombre: texto, tamanio: 50 });
    llenarSelect(select, resultado.datos, 'cod_vino', (v) => nombreVino(v) + ' - ' + moneda(v.precio));
  } catch (e) {
    mostrarMensaje(mensaje, e.message);
  }
}

function dibujarRenglonesVenta() {
  const cuerpo = $('renglones-venta');
  cuerpo.innerHTML = '';
  estado.renglonesVenta.forEach((r, i) => {
    const fila = document.createElement('tr');
    celda(fila, r.cod_vino);
    celda(fila, r.texto);
    celda(fila, r.cantidad, 'numero');
    const td = celda(fila, '');
    td.appendChild(boton('Quitar', () => {
      estado.renglonesVenta.splice(i, 1);
      dibujarRenglonesVenta();
    }, 'secundario'));
    cuerpo.appendChild(fila);
  });
}

function agregarRenglonVenta() {
  const select = $('venta-vino');
  if (!select.value) {
    return;
  }
  estado.renglonesVenta.push({
    cod_vino: select.value,
    cantidad: $('venta-cantidad').value,
    texto: select.options[select.selectedIndex].text,
  });
  dibujarRenglonesVenta();
}

function mostrarComprobante(c) {
  const caja = $('comprobante');
  caja.innerHTML = '';
  const titulo = document.createElement('h3');
  titulo.textContent = 'Comprobante ' + c.nro_comprobante + ' del ' + c.fecha;
  caja.appendChild(titulo);
  const datos = document.createElement('p');
  datos.textContent = c.cliente + ' (' + c.tipo_cliente + ') | Sala ' + c.id_sala + ' - ' + c.localidad;
  caja.appendChild(datos);
  const tabla = document.createElement('table');
  tabla.innerHTML = '<thead><tr><th>Vino</th><th>Cantidad</th><th>Precio unitario</th><th>Descuento</th><th>Subtotal</th></tr></thead>';
  const cuerpo = document.createElement('tbody');
  for (const r of c.renglones) {
    const fila = document.createElement('tr');
    celda(fila, nombreVino(r));
    celda(fila, r.cantidad, 'numero');
    celda(fila, moneda(r.precio_unitario), 'numero');
    celda(fila, r.porc_descuento + ' %', 'numero');
    celda(fila, moneda(r.subtotal), 'numero');
    cuerpo.appendChild(fila);
  }
  tabla.appendChild(cuerpo);
  caja.appendChild(tabla);
  const totales = document.createElement('p');
  totales.textContent = 'Subtotal: ' + moneda(c.subtotal) + ' | Descuento: ' + moneda(c.descuento) + ' | Total: ' + moneda(c.total);
  caja.appendChild(totales);
  caja.classList.remove('oculto');
}

async function registrarVenta() {
  limpiarMensaje('venta-mensaje');
  $('comprobante').classList.add('oculto');
  const comprobante = {
    id_cliente: $('venta-cliente').value,
    id_sala: $('venta-sala').value,
    renglones: estado.renglonesVenta.map((r) => ({ cod_vino: r.cod_vino, cantidad: r.cantidad })),
  };
  try {
    const c = await api.crearComprobante(comprobante);
    mostrarComprobante(c);
    mostrarMensaje('venta-mensaje', 'Venta registrada', 'ok');
    estado.renglonesVenta = [];
    dibujarRenglonesVenta();
  } catch (e) {
    mostrarMensaje('venta-mensaje', e.message);
  }
}

// transferencias
function mostrarTransferencia(t) {
  estado.transferencia = t;
  $('transferencia-actual').classList.remove('oculto');
  $('transferencia-titulo').textContent = 'Transferencia ' + t.nro_transferencia;
  $('transferencia-datos').textContent = 'Sala ' + t.id_sala + ' - ' + t.localidad + ' | Fecha: ' + t.fecha_confeccion + ' | Estado: ' + t.estado;
  const cuerpo = $('renglones-transferencia');
  cuerpo.innerHTML = '';
  for (const r of t.renglones) {
    const fila = document.createElement('tr');
    celda(fila, r.cod_vino);
    celda(fila, nombreVino(r));
    celda(fila, r.cantidad, 'numero');
    celda(fila, r.stock_deposito, 'numero');
    cuerpo.appendChild(fila);
  }
  // los botones se habilitan segun el estado actual
  const enConfeccion = t.estado === 'en_confeccion';
  $('carga-renglon').querySelectorAll('button, input, select').forEach((e) => { e.disabled = !enConfeccion; });
  $('terminar-transferencia').disabled = !enConfeccion;
  $('procesar-transferencia').disabled = t.estado !== 'terminado';
}

async function accionTransferencia(accion) {
  limpiarMensaje('transferencia-mensaje');
  try {
    const t = await accion();
    mostrarTransferencia(t);
    cargarListaTransferencias();
  } catch (e) {
    mostrarMensaje('transferencia-mensaje', e.message);
  }
}

async function cargarListaTransferencias() {
  try {
    const resultado = await api.transferencias({ tamanio: 10 });
    const cuerpo = $('lista-transferencias');
    cuerpo.innerHTML = '';
    for (const t of resultado.datos) {
      const fila = document.createElement('tr');
      celda(fila, t.nro_transferencia);
      celda(fila, t.id_sala + ' - ' + t.localidad);
      celda(fila, t.fecha_confeccion);
      celda(fila, t.estado);
      celda(fila, t.renglones, 'numero');
      celda(fila, '').appendChild(boton('Abrir', () => accionTransferencia(() => api.transferencia(t.nro_transferencia)), 'secundario'));
      cuerpo.appendChild(fila);
    }
  } catch (e) {
    mostrarMensaje('transferencia-mensaje', e.message);
  }
}

// tablero
async function cargarTablero() {
  limpiarMensaje('tablero-mensaje');
  try {
    const top = await api.topVinos(10);
    const cuerpo = $('tabla-top');
    cuerpo.innerHTML = '';
    top.forEach((v, i) => {
      const fila = document.createElement('tr');
      celda(fila, i + 1);
      celda(fila, v.cod_vino + ' - ' + v.nombre);
      celda(fila, v.anada);
      celda(fila, v.volumen_ml + ' ml');
      celda(fila, v.botellas, 'numero');
      cuerpo.appendChild(fila);
    });

    const ventas = await api.ventasPorSala(3);
    if (estado.grafico) {
      estado.grafico.destroy();
    }
    estado.grafico = new Chart($('grafico-ventas'), {
      type: 'bar',
      data: {
        labels: ventas.map((v) => 'Sala ' + v.id_sala + ' ' + v.localidad),
        datasets: [{ label: 'Monto vendido', data: ventas.map((v) => v.monto), backgroundColor: '#8c3b4b' }],
      },
      options: { indexAxis: 'y', plugins: { legend: { display: false } } },
    });
    await cargarSinStock();
  } catch (e) {
    mostrarMensaje('tablero-mensaje', e.message);
  }
}

async function cargarSinStock() {
  try {
    const vinos = await api.vinosSinStock($('tablero-sala').value);
    const cuerpo = $('tabla-sin-stock');
    cuerpo.innerHTML = '';
    for (const v of vinos) {
      const fila = document.createElement('tr');
      celda(fila, v.cod_vino);
      celda(fila, v.nombre);
      celda(fila, v.anada);
      celda(fila, v.volumen_ml + ' ml');
      celda(fila, v.stock_deposito, 'numero');
      cuerpo.appendChild(fila);
    }
  } catch (e) {
    mostrarMensaje('tablero-mensaje', e.message);
  }
}

// carga inicial de las listas y de los eventos
async function iniciar() {
  document.querySelectorAll('nav button').forEach((b) => b.addEventListener('click', () => {
    if (b.dataset.pantalla === 'vino') {
      prepararFormularioVino(null);
    }
    irA(b.dataset.pantalla);
  }));

  try {
    const [cepas, bodegas, maridajes, salas] = await Promise.all([api.cepas(), api.bodegas(), api.maridajes(), api.salas()]);
    estado.cepas = cepas;
    document.querySelectorAll('.lista-cepas').forEach((s) => llenarSelect(s, cepas, 'id_cepa', (c) => c.nombre, 'Todas'));
    $('filtros').elements.bodega.innerHTML = '';
    llenarSelect($('filtros').elements.bodega, bodegas, 'cuit', (b) => b.razon_social, 'Todas');
    llenarSelect($('form-vino').elements.cuit_bodega, bodegas, 'cuit', (b) => b.razon_social);
    document.querySelectorAll('.lista-salas').forEach((s) => llenarSelect(s, salas, 'id_sala', (x) => x.id_sala + ' - ' + x.localidad));
    const lista = $('lista-maridajes');
    for (const m of maridajes) {
      const etiqueta = document.createElement('label');
      const casilla = document.createElement('input');
      casilla.type = 'checkbox';
      casilla.value = m.id_maridaje;
      etiqueta.appendChild(casilla);
      etiqueta.appendChild(document.createTextNode(m.nombre));
      lista.appendChild(etiqueta);
    }
  } catch (e) {
    mostrarMensaje('catalogo-mensaje', e.message);
  }

  $('filtros').addEventListener('submit', (e) => {
    e.preventDefault();
    estado.filtros = Object.fromEntries(new FormData(e.target));
    estado.pagina = 1;
    cargarCatalogo();
  });
  $('pagina-anterior').addEventListener('click', () => { estado.pagina -= 1; cargarCatalogo(); });
  $('pagina-siguiente').addEventListener('click', () => { estado.pagina += 1; cargarCatalogo(); });

  $('form-vino').addEventListener('submit', guardarVino);
  $('agregar-corte').addEventListener('click', () => agregarFilaCorte());
  $('vino-cancelar').addEventListener('click', () => irA('catalogo'));

  $('boton-buscar-cliente').addEventListener('click', buscarClientes);
  $('boton-buscar-vino').addEventListener('click', () => buscarVinos($('buscar-vino').value, $('venta-vino'), 'venta-mensaje'));
  $('agregar-renglon').addEventListener('click', agregarRenglonVenta);
  $('registrar-venta').addEventListener('click', registrarVenta);

  $('nueva-transferencia').addEventListener('click', () => accionTransferencia(() => api.crearTransferencia($('transferencia-sala').value)));
  $('boton-abrir').addEventListener('click', () => accionTransferencia(() => api.transferencia($('abrir-numero').value)));
  $('transferencia-boton-buscar').addEventListener('click', () => buscarVinos($('transferencia-buscar-vino').value, $('transferencia-vino'), 'transferencia-mensaje'));
  $('agregar-renglon-transferencia').addEventListener('click', () => accionTransferencia(() => api.agregarRenglonTransferencia(
    estado.transferencia.nro_transferencia,
    { cod_vino: $('transferencia-vino').value, cantidad: $('transferencia-cantidad').value },
  )));
  $('terminar-transferencia').addEventListener('click', () => accionTransferencia(() => api.terminarTransferencia(estado.transferencia.nro_transferencia)));
  $('procesar-transferencia').addEventListener('click', () => accionTransferencia(() => api.procesarTransferencia(estado.transferencia.nro_transferencia)));

  $('tablero-sala').addEventListener('change', cargarSinStock);

  cargarCatalogo();
  buscarClientes();
  buscarVinos('', $('venta-vino'), 'venta-mensaje');
  buscarVinos('', $('transferencia-vino'), 'transferencia-mensaje');
}

iniciar();
