// ============================================================
// SYNC ORDEN DE TRABAJO — Kepler → Supabase
// Solo actualiza la columna orden_de_trabajo en la tabla
// access_id, buscando el registro por access_id.
// No toca ningún otro campo.
// ============================================================

const CONFIG_OT = {
  SUPABASE_URL : 'https://szoywhtkilgvfrczuyqn.supabase.co',
  SUPABASE_KEY : 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InN6b3l3aHRraWxndmZyY3p1eXFuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAyMjk3NTEsImV4cCI6MjA4NTgwNTc1MX0.sXoPmnZqRJXmaSfA0Mw9HlprVHI_okhTMKrSgONlAOk',

  KEPLER_URL   : 'https://kepler.sbip.cl/api/v1/toa/get_sabana_filtrada/centro/TRAZ',
  KEPLER_TOKEN : 'TU_TOKEN_KEPLER',

  FECHA_INICIO : '',   // vacío = hoy
  FECHA_FIN    : '',   // vacío = hoy
};

// ─── PUNTO DE ENTRADA ─────────────────────────────────────────
function syncOrdenDeTrabajo() {
  Logger.log('=== INICIO sync_orden_de_trabajo ===');

  const actividades = fetchKepler();
  if (!actividades || actividades.length === 0) {
    Logger.log('Sin actividades.');
    return;
  }
  Logger.log(`Actividades recibidas: ${actividades.length}`);

  // Extraer solo access_id + orden_de_trabajo
  const pares = actividades
    .map(act => {
      const accessId = (act['Access ID'] || '').toString().trim();
      if (!accessId || accessId === 'Sin Datos') return null;

      // Buscar el campo OT con varios nombres posibles
      // → Ejecuta diagnosticarCampos() una vez para ver el nombre exacto
      const ot = (
        act['Orden de Trabajo']  ||
        act['Número OT']         ||
        act['OT']                ||
        act['Numero OT']         ||
        act['orden_de_trabajo']  ||
        act['Actividad']         ||
        ''
      ).toString().trim();

      if (!ot) return null;   // sin OT → no actualizar

      return { access_id: accessId, orden_de_trabajo: ot };
    })
    .filter(r => r !== null);

  Logger.log(`Pares access_id → OT encontrados: ${pares.length}`);

  if (pares.length === 0) {
    Logger.log('⚠️ Ningún registro tiene Orden de Trabajo. Revisa el nombre del campo con diagnosticarCampos().');
    return;
  }

  // Actualizar de a lotes de 50
  const BATCH = 50;
  let ok = 0, err = 0;

  for (let i = 0; i < pares.length; i += BATCH) {
    const lote = pares.slice(i, i + BATCH);
    lote.forEach(par => {
      if (patchOT(par.access_id, par.orden_de_trabajo)) ok++;
      else err++;
    });
  }

  Logger.log(`✅ Actualizados: ${ok} | ❌ Errores: ${err}`);
  Logger.log('=== FIN sync_orden_de_trabajo ===');
}

// ─── PATCH: actualiza solo orden_de_trabajo ───────────────────
function patchOT(accessId, ordenDeTrabajo) {
  try {
    const url = `${CONFIG_OT.SUPABASE_URL}/rest/v1/access_id?access_id=eq.${encodeURIComponent(accessId)}`;

    const resp = UrlFetchApp.fetch(url, {
      method : 'PATCH',
      headers: {
        'apikey'        : CONFIG_OT.SUPABASE_KEY,
        'Authorization' : `Bearer ${CONFIG_OT.SUPABASE_KEY}`,
        'Content-Type'  : 'application/json',
        'Prefer'        : 'return=minimal',
      },
      payload           : JSON.stringify({ orden_de_trabajo: ordenDeTrabajo }),
      muteHttpExceptions: true,
    });

    const code = resp.getResponseCode();
    if (code >= 200 && code < 300) {
      Logger.log(`✓ ${accessId} → OT: ${ordenDeTrabajo}`);
      return true;
    } else {
      Logger.log(`✗ ${accessId} HTTP ${code}: ${resp.getContentText()}`);
      return false;
    }
  } catch (e) {
    Logger.log(`✗ ${accessId} excepción: ${e.message}`);
    return false;
  }
}

// ─── FETCH KEPLER ─────────────────────────────────────────────
function fetchKepler() {
  const hoy   = Utilities.formatDate(new Date(), 'America/Santiago', 'yyyy-MM-dd');
  const desde = CONFIG_OT.FECHA_INICIO || hoy;
  const hasta = CONFIG_OT.FECHA_FIN    || hoy;

  try {
    const resp = UrlFetchApp.fetch(
      `${CONFIG_OT.KEPLER_URL}?fecha_inicio=${desde}&fecha_fin=${hasta}`,
      {
        method : 'GET',
        headers: { 'Authorization': `Bearer ${CONFIG_OT.KEPLER_TOKEN}` },
        muteHttpExceptions: true,
      }
    );
    if (resp.getResponseCode() !== 200) {
      Logger.log(`Error Kepler HTTP ${resp.getResponseCode()}: ${resp.getContentText()}`);
      return [];
    }
    return JSON.parse(resp.getContentText()).data || [];
  } catch (e) {
    Logger.log(`Excepción fetchKepler: ${e.message}`);
    return [];
  }
}

// ─── TRIGGER AUTOMÁTICO ───────────────────────────────────────
function crearTrigger() {
  ScriptApp.getProjectTriggers()
    .filter(t => t.getHandlerFunction() === 'syncOrdenDeTrabajo')
    .forEach(t => ScriptApp.deleteTrigger(t));

  ScriptApp.newTrigger('syncOrdenDeTrabajo')
    .timeBased()
    .everyHours(1)
    .create();

  Logger.log('Trigger creado: syncOrdenDeTrabajo cada 1 hora');
}

// ─── DIAGNÓSTICO: ver nombre exacto del campo OT ─────────────
// Ejecuta esto primero para confirmar cómo se llama el campo en Kepler
function diagnosticarCampos() {
  const actividades = fetchKepler();
  if (!actividades || actividades.length === 0) {
    Logger.log('Sin actividades');
    return;
  }
  const act = actividades[0];
  Logger.log('=== CAMPOS DE LA PRIMERA ACTIVIDAD ===');
  Object.entries(act).forEach(([k, v]) => Logger.log(`  "${k}" → "${v}"`));
}
