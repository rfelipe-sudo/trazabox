/**
 * EXTRACTOR PRODUCCIÓN TRAZA → SUPABASE
 * Fuente: API KEPLER (get_sabana_filtrada)
 * Destino: Supabase tabla produccion_traza
 * 
 * Incluye: Trabajo, Quiebres, RGU, Equipos, Detección de Tecnología
 * VERSIÓN COMPLETA CON TODAS LAS INTEGRACIONES
 */

const CONFIG_TRAZA = {
  // API KEPLER
  URL_API: "https://kepler.sbip.cl/api/v1/toa/get_sabana_filtrada/metro/TRAZ",
  
  // Supabase
  SUPABASE_URL: "https://qbryjrkzhvkxusjtwhra.supabase.co",
  SUPABASE_KEY: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFicnlqcmt6aHZreHVzanR3aHJhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg0MTM4NzYsImV4cCI6MjA4Mzk4OTg3Nn0.2KiJRuZSdPBUUGR9tphcaZ_-MTw6VwvdZh5NkvLjz74",
  TABLA: "produccion_traza"
};

// ═══════════════════════════════════════════════════════════════
// FUNCIÓN PRINCIPAL
// ═══════════════════════════════════════════════════════════════

function extraerProduccionTRAZA() {
  try {
    Logger.log("🚀 Iniciando extracción de producción TRAZA...");
    
    // Descargar datos del API
    const datos = descargarDesdeKEPLER();
    
    if (!datos || datos.length === 0) {
      Logger.log("❌ No se pudieron obtener datos del API");
      return;
    }
    
    Logger.log("📊 Registros descargados: " + datos.length);
    
    const produccion = [];
    const estadosValidos = ['completado', 'cancelado', 'no realizada', 'suspendido'];
    
    for (let i = 0; i < datos.length; i++) {
      const fila = datos[i];
      
      const tecnicoCompleto = (fila["Técnico"] || "").toString();
      const estado = (fila["Estado"] || "").toString().toLowerCase().trim();
      const tipo = (fila["Tipo de Actividad"] || "").toString();
      const subtipo = (fila["Subtipo"] || "").toString();
      const pasosXml = (fila["Pasos"] || "").toString();
      const itemsXml = (fila["Items Orden"] || "").toString();
      const orden = (fila["Orden de Trabajo"] || "").toString();
      const fecha = (fila["Fecha"] || "").toString();
      const rutBucket = (fila["Rut o Bucket"] || "").toString().trim();
      const accessId = (fila["Orden de Trabajo"] || "").toString().trim();
      const areaDerivacion = (fila["Area derivación"] || "").toString().trim().toUpperCase();
      const codigoCierre = (fila["Código de Cierre"] || "").toString().trim();
      
      // Coordenadas
      const coordX = parseFloat(fila["Coord X"]) || null;
      const coordY = parseFloat(fila["Coord Y"]) || null;
      
      // Horas
      const horaInicio = (fila["Inicio"] || "").toString();
      const horaFin = (fila["Fin"] || "").toString();
      
      // Calcular duración en minutos
      const duracionMin = calcularDuracionMinutos(horaInicio, horaFin);
      
      // Información adicional
      const tipoRed = (fila["Tipo Red"] || "").toString();
      const territorio = (fila["Territorio"] || "").toString();
      const zonaTrabajo = (fila["Zona de trabajo"] || "").toString();
      const franja = (fila["Franja"] || "").toString();
      const marca = (fila["Marca"] || "").toString();
      const cliente = (fila["Cliente"] || "").toString();
      const direccion = (fila["Dirección"] || "").toString();
      
      // Filtrar solo técnicos TRAZ
      if (!tecnicoCompleto.toUpperCase().includes("TRAZ")) continue;
      
      // Filtrar por estados válidos
      if (!estadosValidos.includes(estado)) continue;
      
      // Normalizar estado
      let estadoNormalizado = "Completado";
      if (estado === "cancelado") {
        estadoNormalizado = "Cancelado";
      } else if (estado === "no realizada") {
        estadoNormalizado = "No Realizada";
      } else if (estado === "suspendido") {
        estadoNormalizado = "Suspendido";
      }
      
      // Calcular RGU solo para completadas
      let resultado = { 
        rgu_base: 0, 
        rgu_adicional: 0, 
        rgu_total: 0, 
        tipo_orden: "", 
        equipos: { dbox: 0, extensores: 0, ont: false, telefonia: false } 
      };
      
      if (estadoNormalizado === "Completado") {
        resultado = calcularRGU(tipo, subtipo, pasosXml, itemsXml);
      } else {
        resultado.tipo_orden = determinarTipoOrden(tipo, subtipo);
      }

      // Calcular puntos HFC (solo aplica para tecnología HFC y estado Completado)
      const tecnologiaActual = detectarTecnologia(tipoRed);
      let puntosHfc = 0;
      let categoriaHfc = "";
      if (tecnologiaActual === "HFC" && estadoNormalizado === "Completado") {
        const resultadoHfc = calcularPuntosHFC(tipo, subtipo);
        puntosHfc = resultadoHfc.puntos;
        categoriaHfc = resultadoHfc.categoria;
      }
      
      // Extraer nombre corto del técnico
      const partes = tecnicoCompleto.split("_");
      const nombreTecnico = partes.length > 0 ? partes[partes.length - 1] : tecnicoCompleto;
      
      // Detectar si es PX0
      const horaReserva = (fila["Hora de reserva de actividad"] || "").toString();
      const esPX0 = detectarPX0(horaReserva, fecha);
      
      produccion.push({
        orden_trabajo: orden,
        fecha_trabajo: fecha,
        tecnico: nombreTecnico,
        codigo_tecnico: tecnicoCompleto,
        rut_tecnico: rutBucket,
        tipo_actividad: tipo,
        subtipo: subtipo,
        tipo_orden: resultado.tipo_orden,
        estado: estadoNormalizado,
        codigo_cierre: codigoCierre,
        area_derivacion: areaDerivacion,
        hora_inicio: horaInicio,
        hora_fin: horaFin,
        duracion_min: duracionMin,
        coord_x: coordX,
        coord_y: coordY,
        rgu_base: resultado.rgu_base,
        rgu_adicional: resultado.rgu_adicional,
        rgu_total: resultado.rgu_total,
        cant_dbox: resultado.equipos.dbox,
        cant_extensores: resultado.equipos.extensores,
        tiene_ont: resultado.equipos.ont,
        tiene_telefonia: resultado.equipos.telefonia,
        tipo_red: tipoRed,
        tecnologia: tecnologiaActual,
        puntos_hfc: puntosHfc,
        categoria_hfc: categoriaHfc,
        territorio: territorio,
        zona_trabajo: zonaTrabajo,
        franja: franja,
        marca: marca,
        cliente: cliente,
        direccion: direccion,
        es_px0: esPX0,
        access_id: accessId,
        notas_cierre: codigoCierre
      });
    }
    
    Logger.log("✅ Registros procesados: " + produccion.length);
    
    if (produccion.length === 0) {
      Logger.log("⚠️ No hay registros para guardar");
      return;
    }
    
    // Estadísticas
    const porEstado = {};
    const porTecnologia = {};
    produccion.forEach(p => {
      porEstado[p.estado] = (porEstado[p.estado] || 0) + 1;
      porTecnologia[p.tecnologia] = (porTecnologia[p.tecnologia] || 0) + 1;
    });
    Logger.log("📊 Por estado: " + JSON.stringify(porEstado));
    Logger.log("📊 Por tecnología: " + JSON.stringify(porTecnologia));
    
    // Cálculos de RGU y tiempos
    let totalRGU = 0;
    let minutosTrabajo = 0;
    let minutosQuiebres = 0;
    let px0Count = 0;
    
    produccion.forEach(p => {
      if (p.estado === "Completado") {
        totalRGU += p.rgu_total;
        minutosTrabajo += p.duracion_min || 0;
      } else {
        minutosQuiebres += p.duracion_min || 0;
      }
      if (p.es_px0) px0Count++;
    });
    
    Logger.log("📈 RGU Total: " + totalRGU.toFixed(2));
    Logger.log("⏱️ Minutos Trabajo: " + minutosTrabajo);
    Logger.log("💔 Minutos Quiebres: " + minutosQuiebres);
    Logger.log("🎯 Órdenes PX0: " + px0Count);
    
    // Guardar en Supabase
    const guardados = guardarProduccionEnSupabase(produccion);
    Logger.log("💾 Registros guardados en Supabase: " + guardados);
    
    return { 
      encontrados: produccion.length, 
      guardados: guardados, 
      rgu_total: totalRGU,
      minutos_trabajo: minutosTrabajo,
      minutos_quiebres: minutosQuiebres,
      px0: px0Count,
      por_estado: porEstado,
      por_tecnologia: porTecnologia
    };
    
  } catch (error) {
    Logger.log("❌ Error: " + error.message);
    throw error;
  }
}

// ═══════════════════════════════════════════════════════════════
// DESCARGAR DATOS DESDE API KEPLER
// ═══════════════════════════════════════════════════════════════

function descargarDesdeKEPLER() {
  Logger.log("📥 Descargando desde API KEPLER...");
  
  try {
    const response = UrlFetchApp.fetch(CONFIG_TRAZA.URL_API, {
      method: "GET",
      muteHttpExceptions: true
    });
    
    const code = response.getResponseCode();
    
    if (code !== 200) {
      Logger.log("❌ Error HTTP: " + code);
      Logger.log("Respuesta: " + response.getContentText().substring(0, 500));
      return [];
    }
    
    const json = JSON.parse(response.getContentText());
    const datos = json.data || [];
    
    Logger.log("✅ Datos recibidos: " + datos.length + " registros");
    
    return datos;
    
  } catch (error) {
    Logger.log("❌ Error descargando: " + error.message);
    return [];
  }
}

// ═══════════════════════════════════════════════════════════════
// CALCULAR DURACIÓN EN MINUTOS
// ═══════════════════════════════════════════════════════════════

function calcularDuracionMinutos(horaInicio, horaFin) {
  if (!horaInicio || !horaFin) return 0;
  
  try {
    const parseHora = (str) => {
      const match = str.match(/(\d{1,2}):(\d{2})/);
      if (match) {
        return parseInt(match[1]) * 60 + parseInt(match[2]);
      }
      return 0;
    };
    
    const minInicio = parseHora(horaInicio);
    const minFin = parseHora(horaFin);
    
    if (minFin >= minInicio) {
      return minFin - minInicio;
    }
    
    return 0;
  } catch (e) {
    return 0;
  }
}

// ═══════════════════════════════════════════════════════════════
// DETECTAR PX0 (MISMO DÍA)
// ═══════════════════════════════════════════════════════════════

function detectarPX0(horaReserva, fechaTrabajo) {
  if (!horaReserva || !fechaTrabajo) return false;
  
  try {
    const fechaReserva = horaReserva.split(' ')[0];
    return fechaReserva === fechaTrabajo;
  } catch (e) {
    return false;
  }
}

// ═══════════════════════════════════════════════════════════════
// CÁLCULO DE RGU
// ═══════════════════════════════════════════════════════════════

function calcularRGU(tipoActividad, subtipo, pasosXml, itemsXml) {
  const equipos = contarEquipos(pasosXml);
  let rgu_base = 0;
  let rgu_adicional = 0;
  let tipo_orden = "";
  
  const tipoLower = (tipoActividad || "").toLowerCase();
  const subtipoLower = (subtipo || "").toLowerCase();
  
  // ALTAS (sin traslado)
  if (tipoLower.includes("alta") && !tipoLower.includes("traslado")) {
    if (subtipoLower.includes("1 play")) {
      rgu_base = 1;
      tipo_orden = "Alta 1 Play";
    } else if (subtipoLower.includes("2 play")) {
      rgu_base = 2;
      tipo_orden = "Alta 2 Play";
    } else if (subtipoLower.includes("3 play")) {
      rgu_base = 3;
      tipo_orden = "Alta 3 Play";
    } else {
      rgu_base = 1;
      tipo_orden = "Alta";
    }
    
    if (equipos.dbox > 2) rgu_adicional += (equipos.dbox - 2) * 0.5;
    rgu_adicional += equipos.extensores * 0.5;
  }
  // ALTA TRASLADO
  else if (tipoLower.includes("alta") && tipoLower.includes("traslado")) {
    rgu_base = 1;
    tipo_orden = "Alta Traslado";
    rgu_adicional += equipos.extensores * 0.5;
    if (equipos.dbox > 2) rgu_adicional += (equipos.dbox - 2) * 0.5;
  }
  // MIGRACIONES
  else if (tipoLower.includes("migraci")) {
    const dboxActualizados = contarDboxActualizados(itemsXml);
    const totalDbox = equipos.dbox + dboxActualizados;
    
    const telefoniaItems = detectarTelefoniaActualizada(itemsXml);
    const tieneTelefonia = equipos.telefonia || telefoniaItems;
    
    let extensoresMigracion = equipos.extensores;
    if (equipos.extensoresInstalados === 1 && equipos.extensoresDesinstalados === 1) {
      extensoresMigracion = 1;
    }
    
    rgu_base = 1;
    tipo_orden = "Migración 1 Play";
    
    if (equipos.ont) {
      if (tieneTelefonia && totalDbox > 0) {
        rgu_base = 3;
        tipo_orden = "Migración 3 Play";
      } else if (totalDbox > 0) {
        rgu_base = 2;
        tipo_orden = "Migración 2 Play";
      } else if (tieneTelefonia) {
        rgu_base = 2;
        tipo_orden = "Migración 2 Play";
      }
    } else if (totalDbox > 0) {
      rgu_base = 2;
      tipo_orden = "Migración 2 Play";
      if (tieneTelefonia) {
        rgu_base = 3;
        tipo_orden = "Migración 3 Play";
      }
    } else if (tieneTelefonia) {
      rgu_base = 2;
      tipo_orden = "Migración 2 Play";
    }
    
    if (totalDbox > 2) rgu_adicional += (totalDbox - 2) * 0.5;
    rgu_adicional += extensoresMigracion * 0.5;
    
    equipos.dbox = totalDbox;
    equipos.extensores = extensoresMigracion;
    equipos.telefonia = tieneTelefonia;
  }
  // MODIFICACIONES
  else if (tipoLower.includes("modific")) {
    rgu_base = 0.75;
    tipo_orden = "Modificación";
    const totalEquipos = equipos.dbox + equipos.extensores;
    if (totalEquipos > 1) rgu_adicional = (totalEquipos - 1) * 0.5;
  }
  // REPARACIONES
  else if (tipoLower.includes("reparaci") || tipoLower.includes("averia") || 
           tipoLower.includes("soporte") || tipoLower.includes("averías")) {
    rgu_base = 1;
    tipo_orden = "Reparación";
  }
  
  return {
    tipo_orden: tipo_orden,
    rgu_base: rgu_base,
    rgu_adicional: rgu_adicional,
    rgu_total: rgu_base + rgu_adicional,
    equipos: equipos
  };
}

// ═══════════════════════════════════════════════════════════════
// CONTAR EQUIPOS DESDE PASOS XML
// ═══════════════════════════════════════════════════════════════

function contarEquipos(pasosXml) {
  if (!pasosXml) return { 
    dbox: 0, 
    extensores: 0, 
    extensoresInstalados: 0,
    extensoresDesinstalados: 0,
    ont: false, 
    telefonia: false 
  };
  
  const pasos = pasosXml.toString();
  
  let dbox = 0;
  let extensoresInstalados = 0;
  let extensoresDesinstalados = 0;
  let ont = false;
  let telefonia = false;
  
  const extensoresInstSet = new Set();
  const extensoresDesinstSet = new Set();
  
  const regex = /<descripcion[\s\S]*?>([^<]+)<\/descripcion/gi;
  let match;
  
  while ((match = regex.exec(pasos)) !== null) {
    const descripcion = match[1].trim();
    const descLower = descripcion.toLowerCase();
    
    // D-Box: solo instalar
    if (descLower.includes("instalar") && !descLower.includes("desinstalar")) {
      const matchDbox = descripcion.match(/Instalar\s*:\s*(\d+)\s*Equipo D-Box/i);
      if (matchDbox) dbox += parseInt(matchDbox[1]);
    }
    
    // Extensores instalados
    if (descLower.includes("instalar") && !descLower.includes("desinstalar") && descLower.includes("extensor")) {
      const matchExtInst = descripcion.match(/Instalar\s*:\s*(\d+)\s*Extensor/i);
      if (matchExtInst) {
        const key = descripcion.trim();
        if (!extensoresInstSet.has(key)) {
          extensoresInstSet.add(key);
          extensoresInstalados += parseInt(matchExtInst[1]);
        }
      }
    }
    
    // Extensores desinstalados
    if (descLower.includes("desinstalar") && descLower.includes("extensor")) {
      const matchExtDesinst = descripcion.match(/Desinstalar\s*:\s*(\d+)\s*Extensor/i);
      if (matchExtDesinst) {
        const key = descripcion.trim();
        if (!extensoresDesinstSet.has(key)) {
          extensoresDesinstSet.add(key);
          extensoresDesinstalados += parseInt(matchExtDesinst[1]);
        }
      }
    }
    
    // ONT y Telefonía
    if (!descLower.includes("desinstalar")) {
      if (/Instalar\s*:\s*\d+\s*(Equipo ONT|Gateway NextGen)/i.test(descripcion)) ont = true;
      if (/(Instalar|Actualizar)\s*:\s*\d+\s*Plan de telefonía/i.test(descripcion)) telefonia = true;
    }
  }
  
  const extensores = Math.max(0, extensoresInstalados - extensoresDesinstalados);
  
  return { 
    dbox, 
    extensores, 
    extensoresInstalados,
    extensoresDesinstalados,
    ont, 
    telefonia 
  };
}

// ═══════════════════════════════════════════════════════════════
// CONTAR D-BOX ACTUALIZADOS
// ═══════════════════════════════════════════════════════════════

function contarDboxActualizados(itemsXml) {
  if (!itemsXml) return 0;
  
  const items = itemsXml.toString();
  let count = 0;
  
  const regexItem = /<Item[\s\S]*?>([\s\S]*?)<\/Item/gi;
  let match;
  
  while ((match = regexItem.exec(items)) !== null) {
    const itemContent = match[1];
    
    const accionMatch = itemContent.match(/<accion[\s\S]*?>([^<]+)<\/accion/i);
    if (!accionMatch) continue;
    
    const accion = accionMatch[1].trim().toLowerCase();
    if (accion !== "actualizar") continue;
    
    const prodMatch = itemContent.match(/<prod[\s\S]*?>([^<]+)<\/prod/i);
    if (!prodMatch) continue;
    
    const producto = prodMatch[1].trim().toLowerCase();
    
    if (producto.includes("d-box") || 
        producto.includes("dbox") || 
        producto.includes("boxtv") ||
        producto.includes("box tv") ||
        producto === "box") {
      count++;
    }
  }
  
  return count;
}

// ═══════════════════════════════════════════════════════════════
// DETECTAR TELEFONÍA ACTUALIZADA
// ═══════════════════════════════════════════════════════════════

function detectarTelefoniaActualizada(itemsXml) {
  if (!itemsXml) return false;
  
  const items = itemsXml.toString();
  
  const regexItem = /<Item[\s\S]*?>([\s\S]*?)<\/Item/gi;
  let match;
  
  while ((match = regexItem.exec(items)) !== null) {
    const itemContent = match[1];
    
    const accionMatch = itemContent.match(/<accion[\s\S]*?>([^<]+)<\/accion/i);
    if (!accionMatch) continue;
    
    const accion = accionMatch[1].trim().toLowerCase();
    if (accion !== "actualizar") continue;
    
    const prodMatch = itemContent.match(/<prod[\s\S]*?>([^<]+)<\/prod/i);
    if (!prodMatch) continue;
    
    const producto = prodMatch[1].trim().toLowerCase();
    
    if (producto.includes("telefon") || producto.includes("fono")) {
      return true;
    }
  }
  
  return false;
}

// ═══════════════════════════════════════════════════════════════
// DETERMINAR TIPO DE ORDEN
// ═══════════════════════════════════════════════════════════════

function determinarTipoOrden(tipoActividad, subtipo) {
  const tipoLower = (tipoActividad || "").toLowerCase();
  const subtipoLower = (subtipo || "").toLowerCase();
  
  if (tipoLower.includes("alta") && !tipoLower.includes("traslado")) {
    if (subtipoLower.includes("1 play")) return "Alta 1 Play";
    if (subtipoLower.includes("2 play")) return "Alta 2 Play";
    if (subtipoLower.includes("3 play")) return "Alta 3 Play";
    return "Alta";
  }
  if (tipoLower.includes("alta") && tipoLower.includes("traslado")) return "Alta Traslado";
  if (tipoLower.includes("migraci")) return "Migración";
  if (tipoLower.includes("modific")) return "Modificación";
  if (tipoLower.includes("reparaci") || tipoLower.includes("averia") || tipoLower.includes("soporte")) return "Reparación";
  
  return tipoActividad;
}

// ═══════════════════════════════════════════════════════════════
// ✅ DETECTAR TECNOLOGÍA
// ═══════════════════════════════════════════════════════════════

function detectarTecnologia(tipoRed) {
  const tipo = (tipoRed || "").toUpperCase();
  
  if (tipo.includes("FTTH") || tipo.includes("GPON") || tipo.includes("FIBRA")) {
    return "FTTH";
  } else if (tipo.includes("NTT") || tipo.includes("NEUTRO") || tipo.includes("NEUTRAL") || tipo.includes("RED NEUTRA")) {
    return "RED_NEUTRA";
  } else if (tipo.includes("HFC") || tipo.includes("COAX") || tipo.includes("DOCSIS") || tipo.includes("CABLE")) {
    return "HFC";
  }
  
  return "FTTH";
}

// ═══════════════════════════════════════════════════════════════
// TABLA DE PUNTOS HFC (según tipo de actividad unificada)
// ═══════════════════════════════════════════════════════════════

const TABLA_PUNTOS_HFC = {
  "1 PLAY":         86,
  "2 PLAY":         115,
  "3 PLAY":         150,
  "PVAR COMPLEJA":  40,
  "PVAR NO COMPLEJA": 17,
  "SSTT":           72,
  "BAJAS":          21,
  "TRASPASO A RED": 17,
  "MODIFICACION":   60
};

/**
 * Calcula los puntos HFC según tipo de actividad.
 * Retorna objeto { puntos, categoria }
 */
function calcularPuntosHFC(tipoActividad, subtipo) {
  const tipo = (tipoActividad || "").toLowerCase();
  const sub  = (subtipo || "").toLowerCase();

  // ── ALTAS → según cantidad de servicios (1/2/3 PLAY) ──────────
  if (tipo.includes("alta") && !tipo.includes("traslado") && !tipo.includes("adicional") && !tipo.includes("premium adicional")) {
    // Intentar detectar PLAY desde el subtipo primero
    if (sub.includes("3 play") || tipo.includes("fono-premium-internet") || tipo.includes("cable-fono-internet") || tipo.includes("cable-fono-premium") || tipo.includes("instalacion de 2da")) {
      return { puntos: TABLA_PUNTOS_HFC["3 PLAY"], categoria: "3 PLAY" };
    }
    if (sub.includes("2 play") || tipo.includes("cable-premium-internet") || tipo.includes("fono-internet") || tipo.includes("fono-premium") || tipo.includes("premium-internet") || tipo.includes("cable internet")) {
      return { puntos: TABLA_PUNTOS_HFC["2 PLAY"], categoria: "2 PLAY" };
    }
    // Por defecto altas simples → 1 PLAY
    return { puntos: TABLA_PUNTOS_HFC["1 PLAY"], categoria: "1 PLAY" };
  }

  // ── BAJAS ──────────────────────────────────────────────────────
  if (tipo.includes("baja") || tipo.includes("retiro extensor")) {
    return { puntos: TABLA_PUNTOS_HFC["BAJAS"], categoria: "BAJAS" };
  }

  // ── SERVICIO TÉCNICO (SSTT) ────────────────────────────────────
  if (tipo.includes("servicio tecnico") || tipo.includes("averia") || tipo.includes("reparaci")) {
    return { puntos: TABLA_PUNTOS_HFC["SSTT"], categoria: "SSTT" };
  }

  // ── TRASPASO A RED ─────────────────────────────────────────────
  if (tipo.includes("traspaso a red") || tipo.includes("cierre traspaso") || tipo.includes("equipo telefonico venta")) {
    return { puntos: TABLA_PUNTOS_HFC["TRASPASO A RED"], categoria: "TRASPASO A RED" };
  }

  // ── MODIFICACIÓN ──────────────────────────────────────────────
  if (tipo.includes("modific") || tipo.includes("cambio a cpe") || tipo.includes("boca adicional") || tipo.includes("boca anexa") || tipo.includes("pc adicional") || tipo.includes("iptv adicional")) {
    return { puntos: TABLA_PUNTOS_HFC["MODIFICACION"], categoria: "MODIFICACION" };
  }

  // ── PVAR COMPLEJA ─────────────────────────────────────────────
  if (tipo.includes("access points adic") || tipo.includes("access points adicional") || tipo.includes("alta iptv adicional")) {
    return { puntos: TABLA_PUNTOS_HFC["PVAR COMPLEJA"], categoria: "PVAR COMPLEJA" };
  }

  // ── PVAR NO COMPLEJA ──────────────────────────────────────────
  if (tipo.includes("access points") || tipo.includes("extension telef") || tipo.includes("alta premium adicional") || tipo.includes("cambio de control") || tipo.includes("cambio equipo") || tipo.includes("confirmacion ok") || tipo.includes("reconexion") || tipo.includes("pc anexo") || tipo.includes("traspaso a red")) {
    return { puntos: TABLA_PUNTOS_HFC["PVAR NO COMPLEJA"], categoria: "PVAR NO COMPLEJA" };
  }

  return { puntos: 0, categoria: "SIN CATEGORIA" };
}

// ═══════════════════════════════════════════════════════════════
// GUARDAR EN SUPABASE
// ═══════════════════════════════════════════════════════════════

function guardarProduccionEnSupabase(datos) {
  Logger.log("📤 INICIO GUARDADO - Registros: " + (datos ? datos.length : "NULL"));
  
  if (!datos || datos.length === 0) {
    Logger.log("⚠️ Array vacío");
    return 0;
  }
  
  // Eliminar duplicados
  const mapa = new Map();
  datos.forEach(reg => {
    const clave = reg.orden_trabajo + "|" + reg.codigo_tecnico + "|" + reg.estado;
    mapa.set(clave, reg);
  });
  const datosUnicos = Array.from(mapa.values());
  
  Logger.log("📤 Registros únicos: " + datosUnicos.length);
  
  const url = CONFIG_TRAZA.SUPABASE_URL + "/rest/v1/" + CONFIG_TRAZA.TABLA + "?on_conflict=orden_trabajo,codigo_tecnico,estado";
  const BATCH_SIZE = 100;
  let totalGuardados = 0;
  
  for (let i = 0; i < datosUnicos.length; i += BATCH_SIZE) {
    const lote = datosUnicos.slice(i, i + BATCH_SIZE);
    const numLote = Math.floor(i / BATCH_SIZE) + 1;
    
    Logger.log("📤 Procesando lote " + numLote + " con " + lote.length + " registros");
    
    const options = {
      method: "POST",
      headers: {
        "apikey": CONFIG_TRAZA.SUPABASE_KEY,
        "Authorization": "Bearer " + CONFIG_TRAZA.SUPABASE_KEY,
        "Content-Type": "application/json",
        "Prefer": "resolution=merge-duplicates,return=minimal"
      },
      payload: JSON.stringify(lote),
      muteHttpExceptions: true
    };
    
    try {
      const response = UrlFetchApp.fetch(url, options);
      const code = response.getResponseCode();
      const body = response.getContentText();
      
      if (code >= 200 && code < 300) {
        totalGuardados += lote.length;
        Logger.log("✅ Lote " + numLote + " OK");
      } else {
        Logger.log("❌ Error lote " + numLote + " código " + code + ": " + body.substring(0, 300));
        break;
      }
    } catch (e) {
      Logger.log("❌ Excepción en lote " + numLote + ": " + e.message);
      break;
    }
  }
  
  Logger.log("📤 TOTAL GUARDADOS: " + totalGuardados);
  return totalGuardados;
}

// ═══════════════════════════════════════════════════════════════
// FUNCIONES DE PRUEBA Y CONFIGURACIÓN
// ═══════════════════════════════════════════════════════════════

function pruebaProduccionTRAZA() {
  Logger.log("🧪 Ejecutando prueba de producción TRAZA...");
  const resultado = extraerProduccionTRAZA();
  Logger.log("✅ Resultado: " + JSON.stringify(resultado));
}

function configurarTriggerTRAZA() {
  // Eliminar triggers existentes
  ScriptApp.getProjectTriggers().forEach(trigger => {
    if (trigger.getHandlerFunction() === "extraerProduccionTRAZA") {
      ScriptApp.deleteTrigger(trigger);
    }
  });
  
  // Crear trigger cada 15 minutos
  ScriptApp.newTrigger("extraerProduccionTRAZA")
    .timeBased()
    .everyMinutes(15)
    .create();
  
  Logger.log("✅ Trigger configurado: Cada 15 minutos");
}

function configurarTriggerHorarioLaboral() {
  ScriptApp.getProjectTriggers().forEach(trigger => {
    if (trigger.getHandlerFunction() === "extraerProduccionTRAZA") {
      ScriptApp.deleteTrigger(trigger);
    }
  });
  
  // Ejecutar cada hora de 7am a 8pm (cada 30 min)
  for (let hora = 7; hora <= 20; hora++) {
    ScriptApp.newTrigger("extraerProduccionTRAZA")
      .timeBased()
      .everyDays(1)
      .atHour(hora)
      .nearMinute(0)
      .inTimezone("America/Santiago")
      .create();
    
    ScriptApp.newTrigger("extraerProduccionTRAZA")
      .timeBased()
      .everyDays(1)
      .atHour(hora)
      .nearMinute(30)
      .inTimezone("America/Santiago")
      .create();
  }
  
  Logger.log("✅ Triggers configurados: Cada 30 min de 7am a 8pm");
}


