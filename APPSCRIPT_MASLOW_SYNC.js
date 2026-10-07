// ═══════════════════════════════════════════════════════════════
// MASLOW → SUPABASE SYNC
// Sincroniza trabajadores activos desde Maslow API a:
//   · tecnicos_traza_zc          (app Flutter)
//   · supervisor_tecnicos_traza  (asignaciones Flutter)
//   · plantel_tecnicos           (panel web Traza)
//
// PASO 1 (UNA sola vez): ejecuta  configurarCredenciales()
// PASO 2 (UNA sola vez): ejecuta  crearTriggers()
// PASO 3 (prueba):       ejecuta  probarConexionMaslow()
// PASO 4 (sync manual):  ejecuta  sincronizarTrabajadoresMaslow()
// ═══════════════════════════════════════════════════════════════

// ─────────────────────────────────────────────────────────────
// CONSTANTES
// ─────────────────────────────────────────────────────────────

var MASLOW_URL = 'https://maslowtraza.sbip.cl/api/sync/trabajadores?include_manager=true';

function getSupabaseConfig() {
  var props = PropertiesService.getScriptProperties();
  return {
    url: props.getProperty('SUPABASE_URL'),
    key: props.getProperty('SUPABASE_KEY'),
  };
}

function getMaslowApiKey() {
  return PropertiesService.getScriptProperties().getProperty('MASLOW_API_KEY');
}

// ─────────────────────────────────────────────────────────────
// PASO 1: GUARDAR CREDENCIALES (ejecutar UNA sola vez)
//
// ⚠️  IMPORTANTE SOBRE LA SUPABASE KEY:
//     La anon key sirve solo si la tabla NO tiene RLS activo.
//     Si ves errores 401/403, ve a:
//       Supabase → Settings → API → service_role (secret)
//     y reemplaza la key aquí antes de ejecutar.
// ─────────────────────────────────────────────────────────────

function configurarCredenciales() {
  var props = PropertiesService.getScriptProperties();

  props.setProperty('MASLOW_API_KEY', 'ur75OfrLVbZ40iR3QqR23SDnR1oxxY73Hh9nj');
  props.setProperty('SUPABASE_URL',   'https://szoywhtkilgvfrczuyqn.supabase.co');

  // Si la tabla tecnicos_traza_zc tiene RLS activado, reemplaza por la service_role key.
  // La encontras en: Supabase → Settings → API → service_role
  props.setProperty('SUPABASE_KEY',   'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InN6b3l3aHRraWxndmZyY3p1eXFuIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3MDIyOTc1MSwiZXhwIjoyMDg1ODA1NzUxfQ.EzbUw-5LYLEiJDpME0mN-ejL88gv9EUxYVFi3qvrEMk');

  Logger.log('MASLOW_API_KEY : ' + (props.getProperty('MASLOW_API_KEY') ? '✅ OK' : '❌ FALTA'));
  Logger.log('SUPABASE_URL   : ' + (props.getProperty('SUPABASE_URL')   ? '✅ OK' : '❌ FALTA'));
  Logger.log('SUPABASE_KEY   : ' + (props.getProperty('SUPABASE_KEY')   ? '✅ OK' : '❌ FALTA'));
  Logger.log('');
  Logger.log('▶ Ahora ejecuta: crearTriggers()');
  Logger.log('▶ Luego prueba:  probarConexionMaslow()');
  Logger.log('▶ Primer sync:   sincronizarTrabajadoresMaslow()');
}

// ─────────────────────────────────────────────────────────────
// MAPEO centro_costo_code → zona ('RM' | 'Centro')
// 17 = Zona Metropolitana, 23 = Zona Centro
// ─────────────────────────────────────────────────────────────

function mapearZona(centroCostoCodigo) {
  if (!centroCostoCodigo) return null;
  var c = centroCostoCodigo.toString().trim();
  if (c === '17') return 'RM';
  if (c === '23') return 'Centro';
  return null;
}

// ─────────────────────────────────────────────────────────────
// MAPEO estado → 'vigente' | 'desvinculado' | 'licencia' | 'permiso'
// ─────────────────────────────────────────────────────────────

function mapearEstadoMaslow(t) {
  if (t.en_licencia === true || t.en_licencia === 1) return 'licencia';
  if (t.con_permiso === true || t.con_permiso === 1) return 'permiso';
  if (t.estado === 1) return 'vigente';
  return 'desvinculado';
}

// ─────────────────────────────────────────────────────────────
// Nombre del jefe directo desde campos Maslow
// Formato: "Jose Ignacio Maturana Saavedra"
// ─────────────────────────────────────────────────────────────

function nombreJefeDirecto(t) {
  if (!t.jefe_directo) return null;
  var j = t.jefe_directo;
  return [
    (j.nombres    || '').trim(),
    (j.apellido_1 || '').trim(),
    (j.apellido_2 || '').trim(),
  ].filter(Boolean).join(' ') || null;
}

// ─────────────────────────────────────────────────────────────
// MAPEO tipo_contrato_code → 'antiguo' | 'nuevo'
// ─────────────────────────────────────────────────────────────

function mapearTipoContrato(codigo) {
  if (!codigo) return 'nuevo';
  var valor = codigo.toString().toUpperCase().trim();
  if (valor === 'CA') return 'antiguo';
  if (valor === 'CN') return 'nuevo';
  var valorLower = valor.toLowerCase();
  if (valorLower === 'antiguo') return 'antiguo';
  return 'nuevo';
}

// ─────────────────────────────────────────────────────────────
// FUNCIÓN PRINCIPAL: Sincronizar trabajadores Maslow → Supabase
// ─────────────────────────────────────────────────────────────

function sincronizarTrabajadoresMaslow() {
  var inicio = new Date();
  Logger.log('═══════════════════════════════════════════════════');
  Logger.log('🔄 Inicio sincronización Maslow → Supabase');
  Logger.log('🕐 ' + inicio.toISOString());
  Logger.log('═══════════════════════════════════════════════════');

  var trabajadores = obtenerTrabajadoresMaslow();
  if (!trabajadores) {
    Logger.log('❌ No se pudieron obtener datos de Maslow. Abortando.');
    return;
  }

  Logger.log('📦 Trabajadores recibidos: ' + trabajadores.length);

  // Primero marcar como inactivos todos los que vinieron de Maslow antes
  // (quienes ya no estén en la lista de Maslow quedarán inactivos)
  desactivarTecnicosMaslow();

  var actualizados = 0;
  var errores = 0;

  trabajadores.forEach(function(t) {
    try {
      if (upsertTecnico(t)) {
        actualizados++;
      } else {
        errores++;
      }
    } catch (e) {
      Logger.log('❌ Error RUT ' + t.rut + ': ' + e.message);
      errores++;
    }
  });

  // Propagar asignaciones a supervisor_tecnicos_traza (compatibilidad app Flutter)
  sincronizarTablaSupervision(trabajadores);

  // Sincronizar plantel_tecnicos (panel web)
  sincronizarPlantelPanel(trabajadores);

  var fin = new Date();
  var duracion = ((fin - inicio) / 1000).toFixed(1);

  Logger.log('═══════════════════════════════════════════════════');
  Logger.log('✅ Completado en ' + duracion + 's');
  Logger.log('   Actualizados/creados : ' + actualizados);
  Logger.log('   Errores              : ' + errores);
  Logger.log('═══════════════════════════════════════════════════');
}

// ─────────────────────────────────────────────────────────────
// Sincroniza supervisor_tecnicos_traza desde los datos Maslow
// para que la app Flutter vea los mismos supervisores
// ─────────────────────────────────────────────────────────────

function sincronizarTablaSupervision(trabajadores) {
  var config = getSupabaseConfig();
  Logger.log('🔄 Sincronizando supervisor_tecnicos_traza…');

  var asignados = trabajadores.filter(function(t) {
    return t.estado === 1 && t.jefe_directo && t.jefe_directo.rut;
  });

  var errores = 0;
  asignados.forEach(function(t) {
    try {
      var url = config.url + '/rest/v1/supervisor_tecnicos_traza?on_conflict=rut_tecnico';
      var options = {
        method: 'POST',
        headers: {
          'apikey':        config.key,
          'Authorization': 'Bearer ' + config.key,
          'Content-Type':  'application/json',
          'Prefer':        'resolution=merge-duplicates,return=minimal',
        },
        payload: JSON.stringify({
          rut_tecnico:    t.rut,
          rut_supervisor: t.jefe_directo.rut,
        }),
        muteHttpExceptions: true,
      };
      var res = UrlFetchApp.fetch(url, options);
      if (res.getResponseCode() >= 400) errores++;
    } catch (e) {
      errores++;
    }
  });

  Logger.log('   supervision sync — ' + asignados.length + ' registros, ' + errores + ' errores');
}

// ─────────────────────────────────────────────────────────────
// Sincroniza plantel_tecnicos (panel web Traza)
// · nombre_completo, supervisor, zona → siempre desde Maslow
// · estado: 'Activo' si está en Maslow, 'DESVINCULADO' si ya no
// · nombre_toa e ito NO se tocan (los gestiona el panel)
// ─────────────────────────────────────────────────────────────

function sincronizarPlantelPanel(trabajadores) {
  var config = getSupabaseConfig();
  Logger.log('🔄 Sincronizando plantel_tecnicos (panel)…');

  var activos = trabajadores.filter(function(t) { return t.estado === 1; });
  var ok = 0, err = 0;

  activos.forEach(function(t) {
    var nombre = [
      (t.nombres    || '').trim(),
      (t.apellido_1 || '').trim(),
      (t.apellido_2 || '').trim(),
    ].filter(Boolean).join(' ');

    var payload = {
      rut:             t.rut,
      nombre_completo: nombre,
      supervisor:      nombreJefeDirecto(t),   // nombre completo del jefe_directo
      zona:            mapearZona(t.centro_costo_code),
      estado:          'Activo',
      updated_at:      new Date().toISOString(),
    };

    try {
      var url = config.url + '/rest/v1/plantel_tecnicos?on_conflict=rut';
      var res = UrlFetchApp.fetch(url, {
        method: 'POST',
        headers: {
          'apikey':        config.key,
          'Authorization': 'Bearer ' + config.key,
          'Content-Type':  'application/json',
          'Prefer':        'resolution=merge-duplicates,return=minimal',
        },
        payload: JSON.stringify(payload),
        muteHttpExceptions: true,
      });
      if (res.getResponseCode() < 400) ok++;
      else { Logger.log('  ❌ plantel ' + t.rut + ' HTTP ' + res.getResponseCode()); err++; }
    } catch (e) {
      Logger.log('  ❌ plantel ' + t.rut + ': ' + e.message);
      err++;
    }
  });

  // Desactivar en plantel los que ya no están en Maslow activo
  var activosRuts = activos.map(function(t) { return t.rut; });
  var desact = desactivarAusentesEnPlantel(activosRuts, config);

  Logger.log('   plantel sync — OK:' + ok + ' | ERR:' + err + ' | Desvinculados:' + desact);
}

function desactivarAusentesEnPlantel(activosRuts, config) {
  var resp = UrlFetchApp.fetch(
    config.url + '/rest/v1/plantel_tecnicos?select=rut&estado=eq.Activo&limit=1000',
    { method: 'GET', headers: { 'apikey': config.key, 'Authorization': 'Bearer ' + config.key }, muteHttpExceptions: true }
  );
  if (resp.getResponseCode() !== 200) return 0;

  var enPlantel = JSON.parse(resp.getContentText()).map(function(r) { return r.rut; });
  var activosSet = {};
  activosRuts.forEach(function(r) { activosSet[r] = true; });
  var ausentes = enPlantel.filter(function(rut) { return !activosSet[rut]; });
  if (!ausentes.length) return 0;

  var desact = 0;
  ausentes.forEach(function(rut) {
    var p = UrlFetchApp.fetch(
      config.url + '/rest/v1/plantel_tecnicos?rut=eq.' + encodeURIComponent(rut),
      {
        method: 'PATCH',
        headers: { 'apikey': config.key, 'Authorization': 'Bearer ' + config.key, 'Content-Type': 'application/json', 'Prefer': 'return=minimal' },
        payload: JSON.stringify({ estado: 'DESVINCULADO', updated_at: new Date().toISOString() }),
        muteHttpExceptions: true,
      }
    );
    if (p.getResponseCode() === 204) desact++;
  });
  return desact;
}

// ─────────────────────────────────────────────────────────────
// Obtener lista de trabajadores desde Maslow API
// ─────────────────────────────────────────────────────────────

function obtenerTrabajadoresMaslow() {
  var apiKey = getMaslowApiKey();
  if (!apiKey) {
    Logger.log('❌ MASLOW_API_KEY no está guardada. Ejecuta configurarCredenciales() primero.');
    return null;
  }

  try {
    var options = {
      method: 'GET',
      headers: {
        'X-Api-Key': apiKey,
        'Content-Type': 'application/json',
      },
      muteHttpExceptions: true,
    };

    var response = UrlFetchApp.fetch(MASLOW_URL, options);
    var status   = response.getResponseCode();

    if (status !== 200) {
      Logger.log('❌ Maslow HTTP ' + status + ': ' + response.getContentText().substring(0, 400));
      return null;
    }

    var data = JSON.parse(response.getContentText());
    Logger.log('✅ Maslow OK — total: ' + data.count);
    return data.trabajadores || [];

  } catch (e) {
    Logger.log('❌ Error llamando Maslow: ' + e.message);
    return null;
  }
}

// ─────────────────────────────────────────────────────────────
// Marcar como inactivos todos los técnicos que ya venían de Maslow
// (los que no aparezcan en el sync actual quedarán desactivados)
// ─────────────────────────────────────────────────────────────

function desactivarTecnicosMaslow() {
  var config = getSupabaseConfig();
  if (!config.url || !config.key) {
    Logger.log('❌ Supabase no configurado. Ejecuta configurarCredenciales().');
    return;
  }

  try {
    var url = config.url + '/rest/v1/tecnicos_traza_zc?maslow_id=not.is.null';
    var options = {
      method: 'PATCH',
      headers: {
        'apikey':          config.key,
        'Authorization':   'Bearer ' + config.key,
        'Content-Type':    'application/json',
        'Prefer':          'return=minimal',
      },
      payload: JSON.stringify({ activo: false }),
      muteHttpExceptions: true,
    };

    var response = UrlFetchApp.fetch(url, options);
    var status   = response.getResponseCode();
    Logger.log('⚪ Técnicos Maslow → inactivos (HTTP ' + status + ')');

    if (status === 401 || status === 403) {
      Logger.log('⚠️  PERMISO DENEGADO: necesitas la service_role key.');
    }
  } catch (e) {
    Logger.log('⚠️  Error desactivando técnicos: ' + e.message);
  }
}

// ─────────────────────────────────────────────────────────────
// Upsert de un técnico en tecnicos_traza_zc
// ─────────────────────────────────────────────────────────────

function upsertTecnico(t) {
  var config = getSupabaseConfig();

  var nombreCompleto = [
    (t.nombres    || '').trim(),
    (t.apellido_1 || '').trim(),
    (t.apellido_2 || '').trim(),
  ].filter(Boolean).join(' ');

  var tipoContrato = mapearTipoContrato(t.tipo_contrato_code || t.tipo_contrato_nombre);
  var activo       = (t.estado === 1);

  var payload = {
    rut:                 t.rut,
    nombre_completo:     nombreCompleto,
    activo:              activo,
    tipo_contrato:       tipoContrato,
    maslow_id:           t._maslow_id,
    email:               t.email || null,
    ultima_sync_maslow:  new Date().toISOString(),
    zona:                mapearZona(t.centro_costo_code),
    rut_supervisor:      (t.jefe_directo && t.jefe_directo.rut) || null,
    nombre_supervisor:   nombreJefeDirecto(t),
    estado_maslow:       mapearEstadoMaslow(t),
  };

  try {
    var url = config.url + '/rest/v1/tecnicos_traza_zc?on_conflict=rut';
    var options = {
      method: 'POST',
      headers: {
        'apikey':          config.key,
        'Authorization':   'Bearer ' + config.key,
        'Content-Type':    'application/json',
        'Prefer':          'resolution=merge-duplicates,return=minimal',
      },
      payload: JSON.stringify(payload),
      muteHttpExceptions: true,
    };

    var response = UrlFetchApp.fetch(url, options);
    var status   = response.getResponseCode();

    if (status === 200 || status === 201 || status === 204) {
      Logger.log('✅ ' + t.rut + ' | ' + nombreCompleto +
        ' | zona:' + (payload.zona || '?') +
        ' | sup:' + (payload.rut_supervisor || 'sin') +
        ' | ' + payload.estado_maslow);
      return true;
    }

    Logger.log('❌ ' + t.rut + ' HTTP ' + status + ': ' + response.getContentText().substring(0, 300));

    if (status === 401 || status === 403) {
      Logger.log('⚠️  PERMISO DENEGADO en upsert. Reemplaza SUPABASE_KEY por la service_role key.');
    }

    return false;

  } catch (e) {
    Logger.log('❌ Excepción upsert ' + t.rut + ': ' + e.message);
    return false;
  }
}

// ─────────────────────────────────────────────────────────────
// PASO 2: CREAR TRIGGERS — 08:00 y 20:00 todos los días
// Ejecutar UNA sola vez
// ─────────────────────────────────────────────────────────────

function crearTriggers() {
  ScriptApp.getProjectTriggers().forEach(function(trigger) {
    if (trigger.getHandlerFunction() === 'sincronizarTrabajadoresMaslow') {
      ScriptApp.deleteTrigger(trigger);
    }
  });

  ScriptApp.newTrigger('sincronizarTrabajadoresMaslow')
    .timeBased().everyDays(1).atHour(8).create();

  ScriptApp.newTrigger('sincronizarTrabajadoresMaslow')
    .timeBased().everyDays(1).atHour(20).create();

  Logger.log('✅ Triggers configurados: 08:00 y 20:00 (diario)');
  Logger.log('▶ Ejecuta probarConexionMaslow() para verificar datos');
}

// ─────────────────────────────────────────────────────────────
// PRUEBA: Ver respuesta de Maslow sin tocar Supabase
// ─────────────────────────────────────────────────────────────

function probarConexionMaslow() {
  Logger.log('── Probando conexión Maslow ──────────────────────');
  var trabajadores = obtenerTrabajadoresMaslow();
  if (!trabajadores) return;

  Logger.log('Total recibidos: ' + trabajadores.length);
  Logger.log('── Primeros 10 ───────────────────────────────────');

  trabajadores.slice(0, 10).forEach(function(t) {
    var nombre   = [t.nombres, t.apellido_1, t.apellido_2].filter(Boolean).join(' ');
    var contrato = t.tipo_contrato_code || t.tipo_contrato_nombre || 'null';
    Logger.log(
      t.rut +
      ' | ' + nombre +
      ' | estado:' + t.estado +
      ' | contrato_maslow:' + contrato +
      ' → ' + mapearTipoContrato(contrato)
    );
  });

  Logger.log('─────────────────────────────────────────────────');
  Logger.log('▶ Si todo se ve bien, ejecuta: sincronizarTrabajadoresMaslow()');
}

// ─────────────────────────────────────────────────────────────
// DIAGNÓSTICO: Muestra TODOS los campos del primer trabajador
// ─────────────────────────────────────────────────────────────

function diagnosticarCamposMaslow() {
  Logger.log('══ DIAGNÓSTICO CAMPOS MASLOW ══════════════════════');
  var trabajadores = obtenerTrabajadoresMaslow();
  if (!trabajadores || trabajadores.length === 0) return;

  var primero = trabajadores[0];
  Logger.log('── Todos los campos del 1er trabajador (' + primero.rut + ') ──');
  Object.keys(primero).forEach(function(campo) {
    Logger.log('  ' + campo + ' : ' + JSON.stringify(primero[campo]));
  });

  Logger.log('');
  Logger.log('── Campos de contrato en TODOS los trabajadores ──');
  trabajadores.forEach(function(t) {
    Logger.log(
      t.rut +
      ' | tipo_contrato_code: '   + JSON.stringify(t.tipo_contrato_code) +
      ' | tipo_contrato_nombre: ' + JSON.stringify(t.tipo_contrato_nombre)
    );
  });

  Logger.log('══════════════════════════════════════════════════');
  Logger.log('▶ Revisa cuál campo tiene los valores CA/CN y avisa para ajustar el mapeo.');
}
