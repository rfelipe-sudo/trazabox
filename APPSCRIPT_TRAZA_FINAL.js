/**
 * EXTRACTOR PRODUCCIÓN TRAZA → SUPABASE
 * VERSIÓN FINAL - Ajustado a la estructura real de la tabla
 */

const CONFIG_TRAZA = {
  URL_API: "https://kepler.sbip.cl/api/v1/toa/get_sabana_filtrada/metro/TRAZ",
  SUPABASE_URL: "https://szoywhtkilgvfrczuyqn.supabase.co",
  SUPABASE_KEY: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InN6b3l3aHRraWxndmZyY3p1eXFuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAyMjk3NTEsImV4cCI6MjA4NTgwNTc1MX0.sXoPmnZqRJXmaSfA0Mw9HlprVHI_okhTMKrSgONlAOk",
  TABLA: "produccion"
};

function extraerProduccionTRAZA() {
  try {
    Logger.log("🚀 Iniciando extracción de producción TRAZA...");
    
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
      const tipoRed = (fila["Tipo Red"] || "").toString();
      const cliente = (fila["Cliente"] || "").toString();
      const direccion = (fila["Dirección"] || "").toString();
      const comuna = (fila["Comuna"] || "").toString();
      const region = (fila["Región"] || "").toString();
      
      // Detectar tecnología
      const tecnologia = detectarTecnologia(tipoRed);
      
      // Filtrar solo técnicos TRAZ
      if (!tecnicoCompleto.toUpperCase().includes("TRAZ")) continue;
      
      // Filtrar por estados válidos
      if (!estadosValidos.includes(estado)) continue;
      
      // Normalizar estado
      let estadoNormalizado = "Completado";
      if (estado === "cancelado") estadoNormalizado = "Cancelado";
      else if (estado === "no realizada") estadoNormalizado = "No Realizada";
      else if (estado === "suspendido") estadoNormalizado = "Suspendido";
      
      // Calcular RGU solo para completadas
      let resultado = { rgu_total: 0, tipo_orden: "" };
      
      if (estadoNormalizado === "Completado") {
        resultado = calcularRGU(tipo, subtipo, pasosXml, itemsXml);
      } else {
        resultado.tipo_orden = determinarTipoOrden(tipo, subtipo);
      }
      
      // Extraer nombre corto del técnico
      const partes = tecnicoCompleto.split("_");
      const nombreTecnico = partes.length > 0 ? partes[partes.length - 1] : tecnicoCompleto;
      
      // ✅ OBJETO CON SOLO LAS COLUMNAS QUE EXISTEN EN LA TABLA
      produccion.push({
        rut_tecnico: rutBucket,
        tecnico: nombreTecnico,
        fecha_trabajo: fecha,
        orden_trabajo: orden,
        tipo_orden: resultado.tipo_orden,
        tecnologia: tecnologia,
        puntos_rgu: resultado.rgu_total,
        estado: estadoNormalizado,
        cliente: cliente,
        direccion: direccion,
        comuna: comuna,
        region: region
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
    let totalRGU = 0;
    
    produccion.forEach(p => {
      porEstado[p.estado] = (porEstado[p.estado] || 0) + 1;
      porTecnologia[p.tecnologia] = (porTecnologia[p.tecnologia] || 0) + 1;
      if (p.estado === "Completado") totalRGU += p.puntos_rgu;
    });
    
    Logger.log("📊 Por estado: " + JSON.stringify(porEstado));
    Logger.log("📊 Por tecnología: " + JSON.stringify(porTecnologia));
    Logger.log("📈 RGU Total: " + totalRGU.toFixed(2));
    
    // Guardar en Supabase
    const guardados = guardarProduccionEnSupabase(produccion);
    Logger.log("💾 Registros guardados en Supabase: " + guardados);
    
    return { 
      encontrados: produccion.length, 
      guardados: guardados, 
      rgu_total: totalRGU,
      por_estado: porEstado,
      por_tecnologia: porTecnologia
    };
    
  } catch (error) {
    Logger.log("❌ Error: " + error.message);
    throw error;
  }
}

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

function calcularRGU(tipoActividad, subtipo, pasosXml, itemsXml) {
  const equipos = contarEquipos(pasosXml);
  let rgu_base = 0;
  let rgu_adicional = 0;
  let tipo_orden = "";
  
  const tipoLower = (tipoActividad || "").toLowerCase();
  const subtipoLower = (subtipo || "").toLowerCase();
  
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
  else if (tipoLower.includes("alta") && tipoLower.includes("traslado")) {
    rgu_base = 1;
    tipo_orden = "Alta Traslado";
    rgu_adicional += equipos.extensores * 0.5;
    if (equipos.dbox > 2) rgu_adicional += (equipos.dbox - 2) * 0.5;
  }
  else if (tipoLower.includes("migraci")) {
    const dboxActualizados = contarDboxActualizados(itemsXml);
    const totalDbox = equipos.dbox + dboxActualizados;
    
    rgu_base = 1;
    tipo_orden = "Migración 1 Play";
    
    if (totalDbox > 0) {
      rgu_base = 2;
      tipo_orden = "Migración 2 Play";
    }
    
    if (totalDbox > 2) rgu_adicional += (totalDbox - 2) * 0.5;
    rgu_adicional += equipos.extensores * 0.5;
  }
  else if (tipoLower.includes("modific")) {
    rgu_base = 0.75;
    tipo_orden = "Modificación";
    const totalEquipos = equipos.dbox + equipos.extensores;
    if (totalEquipos > 1) rgu_adicional = (totalEquipos - 1) * 0.5;
  }
  else if (tipoLower.includes("reparaci") || tipoLower.includes("averia") || tipoLower.includes("soporte")) {
    rgu_base = 1;
    tipo_orden = "Reparación";
  }
  
  return {
    tipo_orden: tipo_orden,
    rgu_total: rgu_base + rgu_adicional
  };
}

function contarEquipos(pasosXml) {
  if (!pasosXml) return { dbox: 0, extensores: 0 };
  
  const pasos = pasosXml.toString();
  let dbox = 0;
  let extensores = 0;
  
  const regex = /<descripcion[\s\S]*?>([^<]+)<\/descripcion/gi;
  let match;
  
  while ((match = regex.exec(pasos)) !== null) {
    const descripcion = match[1].trim();
    const descLower = descripcion.toLowerCase();
    
    if (descLower.includes("instalar") && !descLower.includes("desinstalar")) {
      const matchDbox = descripcion.match(/Instalar\s*:\s*(\d+)\s*Equipo D-Box/i);
      if (matchDbox) dbox += parseInt(matchDbox[1]);
      
      const matchExt = descripcion.match(/Instalar\s*:\s*(\d+)\s*Extensor/i);
      if (matchExt) extensores += parseInt(matchExt[1]);
    }
  }
  
  return { dbox, extensores };
}

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
    
    if (producto.includes("d-box") || producto.includes("dbox") || producto.includes("boxtv") || producto.includes("box tv") || producto === "box") {
      count++;
    }
  }
  
  return count;
}

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
  if (tipoLower.includes("reparaci") || tipoLower.includes("averia")) return "Reparación";
  
  return tipoActividad;
}

function detectarTecnologia(tipoRed) {
  const tipo = (tipoRed || "").toUpperCase();
  
  if (tipo.includes("FTTH") || tipo.includes("GPON") || tipo.includes("FIBRA")) {
    return "FTTH";
  } else if (tipo.includes("NTT") || tipo.includes("NEUTRO") || tipo.includes("NEUTRAL")) {
    return "NTT";
  } else if (tipo.includes("HFC") || tipo.includes("COAX") || tipo.includes("DOCSIS") || tipo.includes("CABLE")) {
    return "HFC";
  }
  
  return "FTTH";
}

function guardarProduccionEnSupabase(datos) {
  Logger.log("📤 INICIO GUARDADO - Registros: " + datos.length);
  
  if (!datos || datos.length === 0) {
    return 0;
  }
  
  // Eliminar duplicados por orden_trabajo
  const mapa = new Map();
  datos.forEach(reg => {
    mapa.set(reg.orden_trabajo, reg);
  });
  const datosUnicos = Array.from(mapa.values());
  
  Logger.log("📤 Registros únicos: " + datosUnicos.length);
  
  const url = CONFIG_TRAZA.SUPABASE_URL + "/rest/v1/" + CONFIG_TRAZA.TABLA;
  const BATCH_SIZE = 50;
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
        Logger.log("❌ Error lote " + numLote + " código " + code + ": " + body.substring(0, 500));
        // Continuar con el siguiente lote
      }
    } catch (e) {
      Logger.log("❌ Excepción en lote " + numLote + ": " + e.message);
      // Continuar con el siguiente lote
    }
    
    // Pausa breve entre lotes para evitar rate limiting
    Utilities.sleep(500);
  }
  
  Logger.log("📤 TOTAL GUARDADOS: " + totalGuardados);
  return totalGuardados;
}

function pruebaProduccionTRAZA() {
  Logger.log("🧪 Ejecutando prueba de producción TRAZA...");
  const resultado = extraerProduccionTRAZA();
  Logger.log("✅ Resultado: " + JSON.stringify(resultado));
}

function configurarTriggerTRAZA() {
  ScriptApp.getProjectTriggers().forEach(trigger => {
    if (trigger.getHandlerFunction() === "extraerProduccionTRAZA") {
      ScriptApp.deleteTrigger(trigger);
    }
  });
  
  ScriptApp.newTrigger("extraerProduccionTRAZA")
    .timeBased()
    .everyMinutes(15)
    .create();
  
  Logger.log("✅ Trigger configurado: Cada 15 minutos");
}

