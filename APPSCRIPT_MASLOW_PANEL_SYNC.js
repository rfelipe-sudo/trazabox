// ═══════════════════════════════════════════════════════════════
// MASLOW → SUPABASE (plantel_tecnicos) SYNC — Panel Traza
//
// Sincroniza técnicos activos desde Maslow al plantel del panel.
// Si un técnico cambia de equipo en Maslow, se actualiza su
// supervisor y zona en plantel_tecnicos automáticamente.
//
// PASO 1 (UNA sola vez): ejecuta  configurarCredencialesPanel()
// PASO 2 (UNA sola vez): ejecuta  crearTriggersPanel()
// PASO 3 (prueba):       ejecuta  probarConexionPanel()
// PASO 4 (sync manual):  ejecuta  sincronizarPlantelPanel()
// ═══════════════════════════════════════════════════════════════

var MASLOW_URL_PANEL = 'https://maslowtraza.sbip.cl/api/sync/trabajadores?include_manager=true';

// Zona según centro_costo_code de Maslow
var ZONA_MAP = {
  '17': 'RM',
  '23': 'Centro',
};

// ─────────────────────────────────────────────────────────────
// PASO 1: GUARDAR CREDENCIALES (ejecutar UNA sola vez)
// ─────────────────────────────────────────────────────────────

function configurarCredencialesPanel() {
  var props = PropertiesService.getScriptProperties();
  props.setProperty('MASLOW_API_KEY',  'ur75OfrLVbZ40iR3QqR23SDnR1oxxY73Hh9nj');
  props.setProperty('SUPABASE_URL',    'https://szoywhtkilgvfrczuyqn.supabase.co');
  props.setProperty('SUPABASE_KEY',    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InN6b3l3aHRraWxndmZyY3p1eXFuIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3MDIyOTc1MSwiZXhwIjoyMDg1ODA1NzUxfQ.EzbUw-5LYLEiJDpME0mN-ejL88gv9EUxYVFi3qvrEMk');
  Logger.log('✅ Credenciales guardadas');
  Logger.log('▶ Ejecuta: crearTriggersPanel()');
}

// ─────────────────────────────────────────────────────────────
// PASO 2: CREAR TRIGGERS — 08:00 y 20:00 todos los días
// ─────────────────────────────────────────────────────────────

function crearTriggersPanel() {
  ScriptApp.getProjectTriggers().forEach(function(t) {
    if (t.getHandlerFunction() === 'sincronizarPlantelPanel') ScriptApp.deleteTrigger(t);
  });
  ScriptApp.newTrigger('sincronizarPlantelPanel').timeBased().everyDays(1).atHour(8).create();
  ScriptApp.newTrigger('sincronizarPlantelPanel').timeBased().everyDays(1).atHour(20).create();
  Logger.log('✅ Triggers: 08:00 y 20:00 (diario)');
}

// ─────────────────────────────────────────────────────────────
// FUNCIÓN PRINCIPAL
// ─────────────────────────────────────────────────────────────

function sincronizarPlantelPanel() {
  var inicio = new Date();
  Logger.log('═══════════════════════════════════════════════════');
  Logger.log('🔄 Sync Maslow → plantel_tecnicos (Panel Traza)');
  Logger.log('🕐 ' + inicio.toISOString());
  Logger.log('═══════════════════════════════════════════════════');

  var config = getConfigPanel();
  if (!config) return;

  var trabajadores = obtenerTrabajadoresMaslowPanel(config.apiKey);
  if (!trabajadores) { Logger.log('❌ Sin datos de Maslow. Abortando.'); return; }

  var activos   = trabajadores.filter(function(t){ return t.estado === 1; });
  var inactivos = trabajadores.filter(function(t){ return t.estado !== 1; });
  Logger.log('📦 Maslow → activos: ' + activos.length + ' | inactivos: ' + inactivos.length);

  // Construir mapa rut → nombre de supervisor (para lookup rápido)
  var supNombreMap = construirMapaSupervisores(activos);
  Logger.log('👥 Supervisores encontrados: ' + Object.keys(supNombreMap).length);
  Object.keys(supNombreMap).forEach(function(rut) {
    Logger.log('   ' + rut + ' → ' + supNombreMap[rut]);
  });
  Logger.log('');

  // Upsert técnicos activos
  var ok = 0, err = 0;
  activos.forEach(function(t) {
    try {
      if (upsertTecnicoPanel(t, supNombreMap, config)) ok++;
      else err++;
    } catch(e) {
      Logger.log('❌ ' + t.rut + ': ' + e.message);
      err++;
    }
  });

  // Desactivar en plantel los que ya no están en Maslow activo
  var activosRuts = activos.map(function(t){ return t.rut; });
  var desact = desactivarAusentesPanel(activosRuts, config);

  var fin = new Date();
  Logger.log('═══════════════════════════════════════════════════');
  Logger.log('✅ Completado en ' + ((fin - inicio)/1000).toFixed(1) + 's');
  Logger.log('   Upsert OK  : ' + ok);
  Logger.log('   Errores    : ' + err);
  Logger.log('   Desactivados: ' + desact);
  Logger.log('═══════════════════════════════════════════════════');
}

// ─────────────────────────────────────────────────────────────
// Construir mapa { rut_supervisor → "Nombre Completo" }
// Formato: "Jose Ignacio Maturana Saavedra"
// Debe coincidir con estado_supervisor.nombre_supervisor y
// mv_panel_tecnicos_dia.supervisor para que el panel haga match.
// ─────────────────────────────────────────────────────────────

function construirMapaSupervisores(activos) {
  var mapa = {};
  activos.forEach(function(t) {
    var jd = t.jefe_directo;
    if (!jd || !jd.rut) return;
    if (mapa[jd.rut]) return;
    // Formato: "Nombres Apellido1 Apellido2" (titlecase preservado tal como viene de Maslow)
    var partes = [
      (jd.nombres    || '').trim(),
      (jd.apellido_1 || '').trim(),
      (jd.apellido_2 || '').trim(),
    ].filter(Boolean);
    mapa[jd.rut] = partes.join(' ');
  });
  return mapa;
}

// ─────────────────────────────────────────────────────────────
// Upsert de un técnico en plantel_tecnicos
// Solo actualiza: nombre_completo, supervisor, zona, estado
// NO toca: nombre_toa, ito (datos que gestiona el panel)
// ─────────────────────────────────────────────────────────────

function upsertTecnicoPanel(t, supNombreMap, config) {
  var nombreCompleto = [
    (t.nombres    || '').trim(),
    (t.apellido_1 || '').trim(),
    (t.apellido_2 || '').trim(),
  ].filter(Boolean).join(' ');

  var jd          = t.jefe_directo;
  var supervisorNombre = (jd && jd.rut) ? (supNombreMap[jd.rut] || null) : null;
  var zona        = ZONA_MAP[t.centro_costo_code] || null;

  var payload = {
    rut:            t.rut,
    nombre_completo: nombreCompleto,
    supervisor:     supervisorNombre,
    zona:           zona,
    estado:         'Activo',
    updated_at:     new Date().toISOString(),
  };

  var url = config.sbUrl + '/rest/v1/plantel_tecnicos?on_conflict=rut';
  var options = {
    method: 'POST',
    headers: {
      'apikey':        config.sbKey,
      'Authorization': 'Bearer ' + config.sbKey,
      'Content-Type':  'application/json',
      'Prefer':        'resolution=merge-duplicates,return=minimal',
    },
    payload: JSON.stringify(payload),
    muteHttpExceptions: true,
  };

  var resp   = UrlFetchApp.fetch(url, options);
  var status = resp.getResponseCode();

  if (status === 200 || status === 201 || status === 204) {
    var supLog = supervisorNombre || '(sin equipo)';
    var zonaLog = zona || '?';
    Logger.log('✅ ' + t.rut + ' | ' + nombreCompleto + ' | sup: ' + supLog + ' | zona: ' + zonaLog);
    return true;
  }

  Logger.log('❌ ' + t.rut + ' HTTP ' + status + ': ' + resp.getContentText().substring(0, 200));
  if (status === 401 || status === 403) {
    Logger.log('⚠️  Permiso denegado. Revisa SUPABASE_KEY en configurarCredencialesPanel()');
  }
  return false;
}

// ─────────────────────────────────────────────────────────────
// Marcar como DESVINCULADO los técnicos del plantel
// que ya no aparecen en Maslow activo
// ─────────────────────────────────────────────────────────────

function desactivarAusentesPanel(activosRuts, config) {
  // Leer todos los que están en el plantel con estado Activo
  var url = config.sbUrl + '/rest/v1/plantel_tecnicos?select=rut&estado=eq.Activo&limit=1000';
  var resp = UrlFetchApp.fetch(url, {
    method: 'GET',
    headers: { 'apikey': config.sbKey, 'Authorization': 'Bearer ' + config.sbKey },
    muteHttpExceptions: true,
  });

  if (resp.getResponseCode() !== 200) {
    Logger.log('⚠️  No se pudo leer plantel para desactivar ausentes');
    return 0;
  }

  var enPlantel = JSON.parse(resp.getContentText()).map(function(r){ return r.rut; });
  var activosSet = {};
  activosRuts.forEach(function(r){ activosSet[r] = true; });

  var ausentes = enPlantel.filter(function(rut){ return !activosSet[rut]; });
  if (!ausentes.length) {
    Logger.log('✅ Ningún técnico para desactivar');
    return 0;
  }

  Logger.log('⚪ Desactivando ' + ausentes.length + ' ausentes en Maslow...');
  var desact = 0;
  ausentes.forEach(function(rut) {
    var patchUrl = config.sbUrl + '/rest/v1/plantel_tecnicos?rut=eq.' + encodeURIComponent(rut);
    var patchResp = UrlFetchApp.fetch(patchUrl, {
      method: 'PATCH',
      headers: {
        'apikey':        config.sbKey,
        'Authorization': 'Bearer ' + config.sbKey,
        'Content-Type':  'application/json',
        'Prefer':        'return=minimal',
      },
      payload: JSON.stringify({ estado: 'DESVINCULADO', updated_at: new Date().toISOString() }),
      muteHttpExceptions: true,
    });
    if (patchResp.getResponseCode() === 204) {
      Logger.log('⚪ Desvinculado: ' + rut);
      desact++;
    } else {
      Logger.log('❌ Error desvinculando ' + rut + ': HTTP ' + patchResp.getResponseCode());
    }
  });
  return desact;
}

// ─────────────────────────────────────────────────────────────
// PRUEBA: Ver datos sin modificar nada en Supabase
// ─────────────────────────────────────────────────────────────

function probarConexionPanel() {
  Logger.log('── Prueba conexión Maslow → plantel_tecnicos ──');
  var config = getConfigPanel();
  if (!config) return;

  var trabajadores = obtenerTrabajadoresMaslowPanel(config.apiKey);
  if (!trabajadores) return;

  var activos = trabajadores.filter(function(t){ return t.estado === 1; });
  var supNombreMap = construirMapaSupervisores(activos);

  Logger.log('Total activos Maslow: ' + activos.length);
  Logger.log('');
  Logger.log('Supervisores detectados:');
  Object.keys(supNombreMap).forEach(function(rut) {
    Logger.log('  ' + rut + ' → ' + supNombreMap[rut]);
  });
  Logger.log('');
  Logger.log('Primeros 10 técnicos a sincronizar:');
  activos.slice(0, 10).forEach(function(t) {
    var nombre = [t.nombres, t.apellido_1, t.apellido_2].filter(Boolean).join(' ');
    var jd = t.jefe_directo;
    var sup = (jd && jd.rut) ? (supNombreMap[jd.rut] || '?') : '(sin equipo)';
    var zona = ZONA_MAP[t.centro_costo_code] || '?';
    Logger.log('  ' + t.rut + ' | ' + nombre + ' | sup: ' + sup + ' | zona: ' + zona);
  });
  Logger.log('');
  Logger.log('▶ Si se ve correcto, ejecuta: sincronizarPlantelPanel()');
}

// ─────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────

function getConfigPanel() {
  var props = PropertiesService.getScriptProperties();
  var apiKey = props.getProperty('MASLOW_API_KEY');
  var sbUrl  = props.getProperty('SUPABASE_URL');
  var sbKey  = props.getProperty('SUPABASE_KEY');
  if (!apiKey || !sbUrl || !sbKey) {
    Logger.log('❌ Credenciales no configuradas. Ejecuta configurarCredencialesPanel() primero.');
    return null;
  }
  return { apiKey: apiKey, sbUrl: sbUrl, sbKey: sbKey };
}

function obtenerTrabajadoresMaslowPanel(apiKey) {
  try {
    var resp = UrlFetchApp.fetch(MASLOW_URL_PANEL, {
      method: 'GET',
      headers: { 'X-Api-Key': apiKey, 'Content-Type': 'application/json' },
      muteHttpExceptions: true,
    });
    if (resp.getResponseCode() !== 200) {
      Logger.log('❌ Maslow HTTP ' + resp.getResponseCode());
      return null;
    }
    var data = JSON.parse(resp.getContentText());
    Logger.log('✅ Maslow OK — total: ' + data.count);
    return data.trabajadores || [];
  } catch(e) {
    Logger.log('❌ Error Maslow: ' + e.message);
    return null;
  }
}
