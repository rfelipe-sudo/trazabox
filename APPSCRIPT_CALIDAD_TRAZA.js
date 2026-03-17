// ═══════════════════════════════════════════════════════════════════
// APPSCRIPT: EXTRACCIÓN DE CALIDAD DESDE KEPLER A SUPABASE TRAZA
// ═══════════════════════════════════════════════════════════════════

// ─────────────────────────────────────────────────────────────────
// CONFIGURACIÓN
// ─────────────────────────────────────────────────────────────────

const CONFIG_CALIDAD = {
  URL_API: "https://kepler.sbip.cl/api/v1/toa/get_reporte_calidad/centro",
  SUPABASE_URL: "https://szoywhtkilgvfrczuyqn.supabase.co",
  SUPABASE_KEY: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InN6b3l3aHRraWxndmZyY3p1eXFuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAyMjk3NTEsImV4cCI6MjA4NTgwNTc1MX0.sXoPmnZqRJXmaSfA0Mw9HlprVHI_okhTMKrSgONlAOk",
  TABLA: "calidad_traza",
  TAMANO_LOTE: 100, // Registros por lote
};

// ─────────────────────────────────────────────────────────────────
// FUNCIÓN PRINCIPAL
// ─────────────────────────────────────────────────────────────────

function extraerCalidadTRAZA() {
  const tiempoInicio = new Date();
  Logger.log("═════════════════════════════════════════════════");
  Logger.log("🚀 INICIO: Extracción de Calidad TRAZA");
  Logger.log("🕐 Hora: " + tiempoInicio.toLocaleString());
  Logger.log("═════════════════════════════════════════════════");

  try {
    // ═══════════════════════════════════════════════════════════════
    // PASO 1: Obtener datos desde Kepler
    // ═══════════════════════════════════════════════════════════════
    Logger.log("\n📡 PASO 1: Consultando API de Kepler...");
    Logger.log("URL: " + CONFIG_CALIDAD.URL_API);

    const response = UrlFetchApp.fetch(CONFIG_CALIDAD.URL_API, {
      method: "get",
      muteHttpExceptions: true,
    });

    const statusCode = response.getResponseCode();
    Logger.log("📊 Status Code: " + statusCode);

    if (statusCode !== 200) {
      throw new Error("Error en API Kepler: Status " + statusCode);
    }

    const jsonResponse = JSON.parse(response.getContentText());
    
    // Validar estructura de respuesta
    if (!jsonResponse.data || !jsonResponse.data.data) {
      throw new Error("Estructura de respuesta inválida");
    }

    const registros = jsonResponse.data.data;
    Logger.log("✅ Registros obtenidos: " + registros.length);
    Logger.log("📅 Fecha de ejecución Kepler: " + jsonResponse.data.fecha_ejecucion);
    Logger.log("🌍 Zona: " + jsonResponse.data.zona);
    Logger.log("📊 Total registros Kepler: " + jsonResponse.data.total_registros);

    // ═══════════════════════════════════════════════════════════════
    // PASO 2: Transformar datos
    // ═══════════════════════════════════════════════════════════════
    Logger.log("\n🔄 PASO 2: Transformando datos...");

    const calidad = [];
    let registrosValidos = 0;
    let registrosInvalidos = 0;

    for (let i = 0; i < registros.length; i++) {
      const fila = registros[i];

      // Validar datos esenciales
      if (!fila.orden_de_trabajo || fila.orden_de_trabajo === "Sin Datos") {
        registrosInvalidos++;
        continue;
      }

      // Extraer RUT del técnico desde el campo "tecnico"
      let rutTecnicoExtraido = fila.rut_o_bucket || '';
      
      // Si rut_o_bucket está vacío o es "Sin Datos", intentar extraer del nombre del técnico
      if (!rutTecnicoExtraido || rutTecnicoExtraido === '' || rutTecnicoExtraido === 'Sin Datos') {
        const tecnicoCompleto = (fila.tecnico || "").toString();
        const matchRut = tecnicoCompleto.match(/TRAZ[_]?(\d{8}-[\dkK])/i);
        if (matchRut && matchRut[1]) {
          rutTecnicoExtraido = matchRut[1];
        }
      }

      // Limpiar nombre del técnico (quitar prefijos)
      let nombreTecnico = (fila.tecnico || "").toString();
      // Quitar prefijos como "FS_NFTT_TRAZ_", "MM_FTTH_TRAZ_", etc.
      nombreTecnico = nombreTecnico.replace(/^[A-Z_]+TRAZ[_]?/i, '').trim();
      if (!nombreTecnico) {
        nombreTecnico = fila.tecnico || '';
      }

      // Normalizar fecha (agregar año completo si es necesario)
      let fechaNormalizada = (fila.fecha || "").toString();
      // Si la fecha tiene formato DD/MM/YY con año de 2 dígitos, convertirlo a 4 dígitos
      const partesFecha = fechaNormalizada.split('/');
      if (partesFecha.length === 3 && partesFecha[2].length === 2) {
        const anno = parseInt(partesFecha[2]);
        const annoCompleto = anno >= 0 && anno <= 50 ? 2000 + anno : 1900 + anno;
        fechaNormalizada = `${partesFecha[0]}/${partesFecha[1]}/${annoCompleto}`;
      }

      calidad.push({
        access_id: fila.access_id || null,
        orden_de_trabajo: fila.orden_de_trabajo,
        numero_cliente: fila.numero_cliente || null,
        rut_o_bucket: rutTecnicoExtraido,
        tecnico: nombreTecnico,
        cliente: fila.cliente || null,
        fecha: fila.fecha || null,
        hora_de_reserva_de_actividad: fila.hora_de_reserva_de_actividad || null,
        estado: fila.estado || null,
        tipo_de_actividad: fila.tipo_de_actividad || null,
        area_derivacion: fila.area_derivacion || null,
        via_deteccion: fila.via_deteccion || null,
        es_reiterado: fila.es_reiterado || 'NO',
        dias_diferencia: fila.dias_diferencia || null,
        reiterada_por_fecha: fila.reiterada_por_fecha || null,
        reiterada_por_hora_reserva: fila.reiterada_por_hora_reserva || null,
        reiterada_por_ot: fila.reiterada_por_ot || null,
        reiterada_por_rut_o_bucket: fila.reiterada_por_rut_o_bucket || null,
        reiterada_por_tecnico: fila.reiterada_por_tecnico || null,
        reiterada_por_tipo_actividad: fila.reiterada_por_tipo_actividad || null,
      });

      registrosValidos++;
    }

    Logger.log("✅ Registros válidos: " + registrosValidos);
    Logger.log("⚠️ Registros inválidos: " + registrosInvalidos);

    if (calidad.length === 0) {
      Logger.log("⚠️ No hay datos para cargar");
      return;
    }

    // ═══════════════════════════════════════════════════════════════
    // PASO 3: Cargar datos a Supabase en lotes
    // ═══════════════════════════════════════════════════════════════
    Logger.log("\n📤 PASO 3: Cargando datos a Supabase...");
    Logger.log("🗄️ Tabla: " + CONFIG_CALIDAD.TABLA);
    Logger.log("📦 Tamaño de lote: " + CONFIG_CALIDAD.TAMANO_LOTE);

    const totalLotes = Math.ceil(calidad.length / CONFIG_CALIDAD.TAMANO_LOTE);
    let lotesExitosos = 0;
    let lotesFallidos = 0;
    let registrosInsertados = 0;

    for (let i = 0; i < calidad.length; i += CONFIG_CALIDAD.TAMANO_LOTE) {
      const lote = calidad.slice(i, i + CONFIG_CALIDAD.TAMANO_LOTE);
      const numLote = Math.floor(i / CONFIG_CALIDAD.TAMANO_LOTE) + 1;

      try {
        const responseSupabase = UrlFetchApp.fetch(
          `${CONFIG_CALIDAD.SUPABASE_URL}/rest/v1/${CONFIG_CALIDAD.TABLA}`,
          {
            method: "post",
            headers: {
              apikey: CONFIG_CALIDAD.SUPABASE_KEY,
              Authorization: `Bearer ${CONFIG_CALIDAD.SUPABASE_KEY}`,
              "Content-Type": "application/json",
              Prefer: "resolution=merge-duplicates",
            },
            payload: JSON.stringify(lote),
            muteHttpExceptions: true,
          }
        );

        const statusSupabase = responseSupabase.getResponseCode();

        if (statusSupabase === 201 || statusSupabase === 200) {
          lotesExitosos++;
          registrosInsertados += lote.length;
          Logger.log(
            `✅ Lote ${numLote}/${totalLotes}: ${lote.length} registros insertados`
          );
        } else {
          lotesFallidos++;
          const errorText = responseSupabase.getContentText();
          Logger.log(
            `❌ Error lote ${numLote} código ${statusSupabase}: ${errorText.substring(0, 200)}`
          );
        }
      } catch (error) {
        lotesFallidos++;
        Logger.log(`❌ Error lote ${numLote}: ${error.toString()}`);
      }

      // Pausa para evitar rate limiting
      if (numLote < totalLotes) {
        Utilities.sleep(500);
      }
    }

    // ═══════════════════════════════════════════════════════════════
    // PASO 4: Resumen final
    // ═══════════════════════════════════════════════════════════════
    const tiempoFin = new Date();
    const duracion = (tiempoFin - tiempoInicio) / 1000;

    Logger.log("\n═════════════════════════════════════════════════");
    Logger.log("✅ PROCESO COMPLETADO");
    Logger.log("═════════════════════════════════════════════════");
    Logger.log("📊 Registros procesados: " + registrosValidos);
    Logger.log("📤 Registros insertados: " + registrosInsertados);
    Logger.log("✅ Lotes exitosos: " + lotesExitosos + "/" + totalLotes);
    Logger.log("❌ Lotes fallidos: " + lotesFallidos + "/" + totalLotes);
    Logger.log("⏱️ Duración: " + duracion.toFixed(2) + " segundos");
    Logger.log("🕐 Hora fin: " + tiempoFin.toLocaleString());
    Logger.log("═════════════════════════════════════════════════");

    // Retornar resumen
    return {
      exito: lotesFallidos === 0,
      registrosProcesados: registrosValidos,
      registrosInsertados: registrosInsertados,
      lotesExitosos: lotesExitosos,
      lotesFallidos: lotesFallidos,
      duracion: duracion,
    };
  } catch (error) {
    Logger.log("\n❌❌❌ ERROR CRÍTICO ❌❌❌");
    Logger.log("Error: " + error.toString());
    Logger.log("Stack: " + error.stack);
    throw error;
  }
}

// ─────────────────────────────────────────────────────────────────
// FUNCIÓN DE PRUEBA (para ejecutar manualmente)
// ─────────────────────────────────────────────────────────────────

function probarExtraccionCalidad() {
  Logger.log("🧪 Ejecutando prueba de extracción de calidad...");
  const resultado = extraerCalidadTRAZA();
  Logger.log("\n📋 Resultado de la prueba:");
  Logger.log(JSON.stringify(resultado, null, 2));
}

