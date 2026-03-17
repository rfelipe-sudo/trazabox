// ═══════════════════════════════════════════════════════════════════
// APPSCRIPT DE PRUEBA: ANALIZAR DATOS DE CALIDAD DESDE KEPLER
// VERSIÓN CORREGIDA - Compatible con Apps Script antiguo
// ═══════════════════════════════════════════════════════════════════

function analizarDatosCalidad() {
  var tiempoInicio = new Date();
  Logger.log("═════════════════════════════════════════════════");
  Logger.log("🔍 ANÁLISIS: Datos de Calidad TRAZA");
  Logger.log("═════════════════════════════════════════════════");

  try {
    // ═══════════════════════════════════════════════════════════════
    // PASO 1: Obtener datos desde Kepler
    // ═══════════════════════════════════════════════════════════════
    var URL_API = "https://kepler.sbip.cl/api/v1/toa/get_reporte_calidad/centro";
    
    Logger.log("\n📡 Consultando API de Kepler...");
    Logger.log("URL: " + URL_API);

    var response = UrlFetchApp.fetch(URL_API, {
      method: "get",
      muteHttpExceptions: true,
    });

    var statusCode = response.getResponseCode();
    Logger.log("📊 Status Code: " + statusCode);

    if (statusCode !== 200) {
      throw new Error("Error en API Kepler: Status " + statusCode);
    }

    var jsonResponse = JSON.parse(response.getContentText());
    
    if (!jsonResponse.data || !jsonResponse.data.data) {
      throw new Error("Estructura de respuesta inválida");
    }

    var registros = jsonResponse.data.data;
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
      var primerRegistro = registros[0];
      Logger.log("\n📋 COLUMNAS DISPONIBLES:");
      Logger.log("─────────────────────────────────────────────────");
      
      var columnas = Object.keys(primerRegistro);
      for (var i = 0; i < columnas.length; i++) {
        var columna = columnas[i];
        var valor = primerRegistro[columna];
        var tipo = typeof valor;
        Logger.log((i + 1) + ". " + columna + " (" + tipo + "): " + valor);
      }
    }

    // ═══════════════════════════════════════════════════════════════
    // PASO 3: Buscar ejemplos de reiteraciones
    // ═══════════════════════════════════════════════════════════════
    Logger.log("\n\n🔍 BUSCANDO REITERACIONES:");
    Logger.log("═════════════════════════════════════════════════");

    var reiteraciones = registros.filter(function(r) {
      return r.es_reiterado === 'SI';
    });
    
    var porcentaje = (reiteraciones.length / registros.length * 100).toFixed(2);
    Logger.log("\n✅ Reiteraciones encontradas: " + reiteraciones.length + " de " + registros.length + " (" + porcentaje + "%)");

    if (reiteraciones.length > 0) {
      Logger.log("\n📊 EJEMPLOS DE REITERACIONES (primeras 5):");
      Logger.log("─────────────────────────────────────────────────");
      
      var limite = Math.min(5, reiteraciones.length);
      for (var i = 0; i < limite; i++) {
        var r = reiteraciones[i];
        Logger.log("\n🔸 REITERACIÓN " + (i + 1) + ":");
        Logger.log("   Orden actual: " + r.orden_de_trabajo);
        Logger.log("   Fecha actual: " + r.fecha);
        Logger.log("   Técnico actual: " + r.tecnico);
        Logger.log("   RUT actual: " + r.rut_o_bucket);
        Logger.log("   Cliente: " + r.cliente);
        Logger.log("   Tipo actividad: " + r.tipo_de_actividad);
        Logger.log("   ────────────────────────────────────────");
        Logger.log("   ⚠️ DATOS DE LA ORDEN ORIGINAL:");
        Logger.log("   Orden original: " + (r.reiterada_por_ot || 'N/A'));
        Logger.log("   Fecha original: " + (r.reiterada_por_fecha || 'N/A'));
        Logger.log("   Técnico original: " + (r.reiterada_por_tecnico || 'N/A'));
        Logger.log("   RUT original: " + (r.reiterada_por_rut_o_bucket || 'N/A'));
        Logger.log("   Tipo actividad original: " + (r.reiterada_por_tipo_actividad || 'N/A'));
        Logger.log("   Días de diferencia: " + (r.dias_diferencia || 'N/A'));
        Logger.log("   Hora reserva actual: " + (r.hora_de_reserva_de_actividad || 'N/A'));
        Logger.log("   Hora reserva original: " + (r.reiterada_por_hora_reserva || 'N/A'));
      }
    } else {
      Logger.log("⚠️ No se encontraron reiteraciones en este conjunto de datos");
    }

    // ═══════════════════════════════════════════════════════════════
    // PASO 4: Analizar distribución de días_diferencia
    // ═══════════════════════════════════════════════════════════════
    Logger.log("\n\n📊 DISTRIBUCIÓN DE DÍAS DE DIFERENCIA:");
    Logger.log("═════════════════════════════════════════════════");

    var diasDiferencia = [];
    for (var i = 0; i < reiteraciones.length; i++) {
      var r = reiteraciones[i];
      if (r.dias_diferencia !== null && r.dias_diferencia !== undefined) {
        diasDiferencia.push(parseInt(r.dias_diferencia));
      }
    }

    if (diasDiferencia.length > 0) {
      var min = Math.min.apply(null, diasDiferencia);
      var max = Math.max.apply(null, diasDiferencia);
      var suma = 0;
      for (var i = 0; i < diasDiferencia.length; i++) {
        suma += diasDiferencia[i];
      }
      var promedio = suma / diasDiferencia.length;
      
      Logger.log("Min: " + min + " días");
      Logger.log("Max: " + max + " días");
      Logger.log("Promedio: " + promedio.toFixed(2) + " días");
      
      // Contar cuántas están dentro de 30 días
      var dentro30dias = 0;
      var fuera30dias = 0;
      for (var i = 0; i < diasDiferencia.length; i++) {
        if (diasDiferencia[i] <= 30) {
          dentro30dias++;
        } else {
          fuera30dias++;
        }
      }
      
      var pctDentro = (dentro30dias / diasDiferencia.length * 100).toFixed(2);
      var pctFuera = (fuera30dias / diasDiferencia.length * 100).toFixed(2);
      
      Logger.log("\n✅ Dentro de 30 días: " + dentro30dias + " (" + pctDentro + "%)");
      Logger.log("❌ Fuera de 30 días: " + fuera30dias + " (" + pctFuera + "%)");
    }

    // ═══════════════════════════════════════════════════════════════
    // PASO 5: Analizar fechas para entender el desfase
    // ═══════════════════════════════════════════════════════════════
    Logger.log("\n\n📅 ANÁLISIS DE FECHAS (DESFASE DE MES):");
    Logger.log("═════════════════════════════════════════════════");

    if (reiteraciones.length > 0) {
      Logger.log("\n🔍 Analizando primeras 10 reiteraciones con datos de fecha:");
      
      var limite = Math.min(10, reiteraciones.length);
      for (var i = 0; i < limite; i++) {
        var r = reiteraciones[i];
        
        if (r.fecha && r.reiterada_por_fecha && r.dias_diferencia) {
          var fechaActual = r.fecha;
          var fechaOriginal = r.reiterada_por_fecha;
          var dias = r.dias_diferencia;
          
          // Parsear meses
          var partesActual = fechaActual.split('/');
          var partesOriginal = fechaOriginal.split('/');
          
          if (partesActual.length === 3 && partesOriginal.length === 3) {
            var mesActual = parseInt(partesActual[1]);
            var mesOriginal = parseInt(partesOriginal[1]);
            var desfaseMeses = mesActual - mesOriginal;
            
            var esValido = (dias <= 30 && desfaseMeses <= 1) ? '✅ SÍ' : '❌ NO';
            
            Logger.log("\n" + (i + 1) + ". Orden: " + r.orden_de_trabajo);
            Logger.log("   Original: " + fechaOriginal + " (mes " + mesOriginal + ")");
            Logger.log("   Reiteración: " + fechaActual + " (mes " + mesActual + ")");
            Logger.log("   Desfase: " + desfaseMeses + " mes(es), " + dias + " días");
            Logger.log("   ¿Válido? " + esValido);
          }
        }
      }
    }

    // ═══════════════════════════════════════════════════════════════
    // PASO 6: Resumen final
    // ═══════════════════════════════════════════════════════════════
    var tiempoFin = new Date();
    var duracion = (tiempoFin - tiempoInicio) / 1000;

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

