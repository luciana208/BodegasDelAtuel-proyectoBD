// todas las llamadas a la api pasan por aca
const api = (() => {
  const base = window.API_URL;

  /* hace el pedido y devuelve el json. si la api responde con error, lanza una
     excepcion con el mensaje que mando la api, sin cambiarlo */
  async function pedir(metodo, ruta, cuerpo) {
    const opciones = { method: metodo, headers: {} };
    if (cuerpo !== undefined) {
      opciones.headers['Content-Type'] = 'application/json';
      opciones.body = JSON.stringify(cuerpo);
    }
    let respuesta;
    try {
      respuesta = await fetch(base + ruta, opciones);
    } catch (e) {
      throw new Error('No se pudo conectar con la API en ' + base);
    }
    if (respuesta.status === 204) {
      return null;
    }
    const datos = await respuesta.json();
    if (!respuesta.ok) {
      let mensaje = datos.error || 'Error ' + respuesta.status;
      if (datos.detalle) {
        mensaje += ' (' + datos.detalle + ')';
      }
      throw new Error(mensaje);
    }
    return datos;
  }

  // arma la query string sin los filtros vacios
  function consulta(parametros) {
    const p = new URLSearchParams();
    for (const [clave, valor] of Object.entries(parametros)) {
      if (valor !== '' && valor !== null && valor !== undefined) {
        p.append(clave, valor);
      }
    }
    const texto = p.toString();
    return texto ? '?' + texto : '';
  }

  return {
    cepas: () => pedir('GET', '/cepas'),
    bodegas: () => pedir('GET', '/bodegas'),
    maridajes: () => pedir('GET', '/maridajes'),
    salas: () => pedir('GET', '/salas'),

    vinos: (filtros) => pedir('GET', '/vinos' + consulta(filtros)),
    vino: (cod) => pedir('GET', '/vinos/' + cod),
    crearVino: (vino) => pedir('POST', '/vinos', vino),
    modificarVino: (cod, vino) => pedir('PUT', '/vinos/' + cod, vino),

    clientes: (filtros) => pedir('GET', '/clientes' + consulta(filtros)),

    crearComprobante: (comprobante) => pedir('POST', '/comprobantes', comprobante),

    transferencias: (filtros) => pedir('GET', '/transferencias' + consulta(filtros)),
    transferencia: (nro) => pedir('GET', '/transferencias/' + nro),
    crearTransferencia: (idSala) => pedir('POST', '/transferencias', { id_sala: idSala }),
    agregarRenglonTransferencia: (nro, renglon) => pedir('POST', '/transferencias/' + nro + '/renglones', renglon),
    terminarTransferencia: (nro) => pedir('POST', '/transferencias/' + nro + '/terminar'),
    procesarTransferencia: (nro) => pedir('POST', '/transferencias/' + nro + '/procesar'),

    topVinos: (limite) => pedir('GET', '/reportes/top-vinos' + consulta({ limite })),
    ventasPorSala: (meses) => pedir('GET', '/reportes/ventas-por-sala' + consulta({ meses })),
    vinosSinStock: (sala) => pedir('GET', '/reportes/vinos-sin-stock' + consulta({ sala })),
  };
})();
