// ═══════════════════════════════════════════════════════════════════
// APPSCRIPT DE PRUEBA: ANALIZAR DATOS DE CALIDAD DESDE KEPLER
// Este script descarga datos pero NO los inserta en Supabase
// Solo para analizar la estructura
// ═══════════════════════════════════════════════════════════════════

function analizarDatosCalidad() {
  const tiempoInicio = new Date();
  Logger.log("═════════════════════════════════════════════════");
  Logger.log("🔍 ANÁLISIS: Datos de Calidad TRAZA");
  Logger.log("═════════════════════════════════════════════════");

  try {
    // ═══════════════════════════════════════════════════════════════
    // PASO 1: Obtener datos desde Kepler
    // ═══════════════════════════════════════════════════════════════
    const URL_API = "https://kepler.sbip.cl/api/v1/toa/get_reporte_calidad/centro";
    
    Logger.log("\n📡 Consultando API de Kepler...");
    Logger.log("URL: " + URL_API);

    const response = UrlFetchApp.fetch(URL_API, {
      method: "get",
      muteHttpExceptions: true,
    });

    const statusCode = response.getResponseCode();
    Logger.log("📊 Status Code: " + statusCode);

    if (statusCode !== 200) {
      throw new Error("Error en API Kepler: Status " + statusCode);
    }

    const jsonResponse = JSON.parse(response.getContentText());
    
    if (!jsonResponse.data || !jsonResponse.data.data) {
      throw new Error("Estructura de respuesta inválida");
    }

    const registros = jsonResponse.data.data;
    Logger.log("✅ Registros obtenidos: " + registros.length);
    Logger.log("📅 Fecha de ejecución: " + jsonResponse.data.fecha_ejecucion);
    Logger.log("🌍 Zona: " + jsonResponse.data.zona);
    Logger.log("📊 Total registros: " + jsonResponse.data.total_registros);

    // ═══════════════════════════════════════════════════════════════
    // PASO 2: Analizar estructura de datos
    // ═══════════════════════════════════════════════════════════════
    Logger.log("\n🔍 ANÁLISIS DE ESTRUCTURA:");
    Logger.log("═════════════════════════════════════════════════");

    // Mostrar todas las columnas del primer registro
    if (registros.length > 0) {
      const primerRegistro = registros[0];
      Logger.log("\n📋 COLUMNAS DISPONIBLES:");
      Logger.log("─────────────────────────────────────────────────");
      
      const columnas = Object.keys(primerRegistro);
      columnas.forEach((columna, index) => {
        const valor = primerRegistro[columna];
        const tipo = typeof valor;
        Logger.log(`${index + 1}. ${columna} (${tipo}): ${valor}`);
      });
    }

    // ═══════════════════════════════════════════════════════════════
    // PASO 3: Buscar ejemplos de reiteraciones
    // ═══════════════════════════════════════════════════════════════
    Logger.log("\n\n🔍 BUSCANDO REITERACIONES:");
    Logger.log("═════════════════════════════════════════════════");

    const reiteraciones = registros.filter(r => r.es_reiterado === 'SI');
    Logger.log(`\n✅ Reiteraciones encontradas: ${reiteraciones.length} de ${registros.length} (${(reiteraciones.length/registros.length*100).toFixed(2)}%)`);

    if (reiteraciones.length > 0) {
      Logger.log("\n📊 EJEMPLOS DE REITERACIONES (primeras 5):");
      Logger.log("─────────────────────────────────────────────────");
      
      for (let i = 0; i < Math.min(5, reiteraciones.length); i++) {
        const r = reiteraciones[i];
        Logger.log(`\n🔸 REITERACIÓN ${i + 1}:`);
        Logger.log(`   Orden actual: ${r.orden_de_trabajo}`);
        Logger.log(`   Fecha actual: ${r.fecha}`);
        Logger.log(`   Técnico actual: ${r.tecnico}`);
        Logger.log(`   RUT actual: ${r.rut_o_bucket}`);
        Logger.log(`   Cliente: ${r.cliente}`);
        Logger.log(`   Tipo actividad: ${r.tipo_de_actividad}`);
        Logger.log(`   ────────────────────────────────────────`);
        Logger.log(`   ⚠️ DATOS DE LA ORDEN ORIGINAL:`);
        Logger.log(`   Orden original: ${r.reiterada_por_ot || 'N/A'}`);
        Logger.log(`   Fecha original: ${r.reiterada_por_fecha || 'N/A'}`);
        Logger.log(`   Técnico original: ${r.reiterada_por_tecnico || 'N/A'}`);
        Logger.log(`   RUT original: ${r.reiterada_por_rut_o_bucket || 'N/A'}`);
        Logger.log(`   Tipo actividad original: ${r.reiterada_por_tipo_actividad || 'N/A'}`);
        Logger.log(`   Días de diferencia: ${r.dias_diferencia || 'N/A'}`);
        Logger.log(`   Hora reserva actual: ${r.hora_de_reserva_de_actividad || 'N/A'}`);
        Logger.log(`   Hora reserva original: ${r.reiterada_por_hora_reserva || 'N/A'}`);
      }
    } else {
      Logger.log("⚠️ No se encontraron reiteraciones en este conjunto de datos");
    }

    // ═══════════════════════════════════════════════════════════════
    // PASO 4: Analizar distribución de días_diferencia
    // ═══════════════════════════════════════════════════════════════
    Logger.log("\n\n📊 DISTRIBUCIÓN DE DÍAS DE DIFERENCIA:");
    Logger.log("═════════════════════════════════════════════════");

    const diasDiferencia = reiteraciones
      .filter(r => r.dias_diferencia !== null && r.dias_diferencia !== undefined)
      .map(r => parseInt(r.dias_diferencia));

    if (diasDiferencia.length > 0) {
      const min = Math.min(...diasDiferencia);
      const max = Math.max(...diasDiferencia);
      const promedio = diasDiferencia.reduce((a, b) => a + b, 0) / diasDiferencia.length;
      
      Logger.log(`Min: ${min} días`);
      Logger.log(`Max: ${max} días`);
      Logger.log(`Promedio: ${promedio.toFixed(2)} días`);
      
      // Contar cuántas están dentro de 30 días
      const dentro30dias = diasDiferencia.filter(d => d <= 30).length;
      const fuera30dias = diasDiferencia.filter(d => d > 30).length;
      
      Logger.log(`\n✅ Dentro de 30 días: ${dentro30dias} (${(dentro30dias/diasDiferencia.length*100).toFixed(2)}%)`);
      Logger.log(`❌ Fuera de 30 días: ${fuera30dias} (${(fuera30dias/diasDiferencia.length*100).toFixed(2)}%)`);
    }

    // ═══════════════════════════════════════════════════════════════
    // PASO 5: Analizar fechas para entender el desfase
    // ═══════════════════════════════════════════════════════════════
    Logger.log("\n\n📅 ANÁLISIS DE FECHAS (DESFASE DE MES):");
    Logger.log("═════════════════════════════════════════════════");

    if (reiteraciones.length > 0) {
      Logger.log("\n🔍 Analizando primeras 10 reiteraciones con datos de fecha:");
      
      for (let i = 0; i < Math.min(10, reiteraciones.length); i++) {
        const r = reiteraciones[i];
        
        if (r.fecha && r.reiterada_por_fecha && r.dias_diferencia) {
          const fechaActual = r.fecha;
          const fechaOriginal = r.reiterada_por_fecha;
          const dias = r.dias_diferencia;
          
          // Parsear meses
          const partesActual = fechaActual.split('/');
          const partesOriginal = fechaOriginal.split('/');
          
          if (partesActual.length === 3 && partesOriginal.length === 3) {
            const mesActual = parseInt(partesActual[1]);
            const mesOriginal = parseInt(partesOriginal[1]);
            const desfaseMeses = mesActual - mesOriginal;
            
            Logger.log(`\n${i + 1}. Orden: ${r.orden_de_trabajo}`);
            Logger.log(`   Original: ${fechaOriginal} (mes ${mesOriginal})`);
            Logger.log(`   Reiteración: ${fechaActual} (mes ${mesActual})`);
            Logger.log(`   Desfase: ${desfaseMeses} mes(es), ${dias} días`);
            Logger.log(`   ¿Válido? ${dias <= 30 && desfaseMeses <= 1 ? '✅ SÍ' : '❌ NO'}`);
          }
        }
      }
    }

    // ═══════════════════════════════════════════════════════════════
    // PASO 6: Resumen final
    // ═══════════════════════════════════════════════════════════════
    const tiempoFin = new Date();
    const duracion = (tiempoFin - tiempoInicio) / 1000;

    Logger.log("\n\n═════════════════════════════════════════════════");
    Logger.log("✅ ANÁLISIS COMPLETADO");
    Logger.log("═════════════════════════════════════════════════");
    Logger.log("📊 Total registros: " + registros.length);
    Logger.log("⚠️ Reiteraciones: " + reiteraciones.length);
    Logger.log("⏱️ Duración: " + duracion.toFixed(2) + " segundos");
    Logger.log("═════════════════════════════════════════════════");

    return {
      totalRegistros: registros.length,
      totalReiteraciones: reiteraciones.length,
      columnasDisponibles: Object.keys(registros[0] || {}),
      duracion: duracion
    };

  } catch (error) {
    Logger.log("\n❌❌❌ ERROR CRÍTICO ❌❌❌");
    Logger.log("Error: " + error.toString());
    Logger.log("Stack: " + error.stack);
    throw error;
  }
}

