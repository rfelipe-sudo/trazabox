// ============================================================
// SYNC ACCESS ID — Kepler → Supabase
// Sincroniza: nombre_tecnico, rut_o_bucket, tipo_red_producto,
// estado, id_actividad, fecha, orden_de_trabajo
//
// Reglas:
//  • access_id + mismo estado  → no toca el registro
//  • access_id + estado nuevo  → actualiza todos los campos
//  • access_id no existe       → inserta
// Frecuencia: cada 5 minutos (configurar con crearTrigger())
// ============================================================

const CONFIG_SYNC = {
  SUPABASE_URL : 'https://szoywhtkilgvfrczuyqn.supabase.co',
  SUPABASE_KEY : 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InN6b3l3aHRraWxndmZyY3p1eXFuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAyMjk3NTEsImV4cCI6MjA4NTgwNTc1MX0.sXoPmnZqRJXmaSfA0Mw9HlprVHI_okhTMKrSgONlAOk',

  KEPLER_URL   : 'https://kepler.sbip.cl/api/v1/toa/get_sabana_filtrada/centro/TRAZ',
  KEPLER_TOKEN : 'TU_TOKEN_KEPLER',

  FECHA_INICIO : '',   // vacío = hoy
  FECHA_FIN    : '',   // vacío = hoy
};

// ─── PUNTO DE ENTRADA ─────────────────────────────────────────
function syncAccessId() {
  Logger.log('=== INICIO sync_access_id ===');

  // 1. Traer actividades desde Kepler
  const actividades = fetchKepler();
  if (!actividades || actividades.length === 0) {
    Logger.log('Sin actividades para procesar.');
    return;
  }
  Logger.log(`Actividades recibidas: ${actividades.length}`);

  // 2. Parsear y filtrar los que tienen Access ID válido
  const registros = actividades.map(parseActividad).filter(r => r !== null);
  Logger.log(`Con Access ID válido: ${registros.length}`);

  if (registros.length === 0) return;

  // 3. Traer el estado actual de esos access_id desde Supabase
  const idsAConsultar = registros.map(r => r.access_id);
  const estadosActuales = fetchEstadosActuales(idsAConsultar);
  // estadosActuales = Map { access_id → estado_actual }

  // 4. Separar en: insertar (nuevos) vs actualizar (estado cambió)
  const aInsertar   = [];
  const aActualizar = [];

  registros.forEach(r => {
    const estadoGuardado = estadosActuales.get(r.access_id);

    if (estadoGuardado === undefined) {
      // No existe en Supabase → insertar completo
      aInsertar.push(r);
    } else if (estadoGuardado !== r.estado) {
      // Estado cambió → actualizar todos los campos incluido OT
      aActualizar.push(r);
    } else if (r.orden_de_trabajo) {
      // Mismo estado pero tiene OT → actualizar para guardar el OT
      aActualizar.push(r);
    }
    // Sin OT y mismo estado → ignorar
  });

  // 5. Deduplicar por access_id (puede venir duplicado desde Kepler)
  const deduplicar = arr => {
    const mapa = new Map();
    arr.forEach(r => mapa.set(r.access_id, r));
    return Array.from(mapa.values());
  };
  const insertar   = deduplicar(aInsertar);
  const actualizar = deduplicar(aActualizar);

  Logger.log(`A insertar: ${insertar.length} | A actualizar: ${actualizar.length} | Sin cambio: ${registros.length - aInsertar.length - aActualizar.length}`);

  if (insertar.length > 0)   insertarRegistros(insertar);
  if (actualizar.length > 0) actualizarRegistros(actualizar);

  Logger.log('=== FIN sync_access_id ===');
}

// ─── FETCH KEPLER ─────────────────────────────────────────────
function fetchKepler() {
  const hoy   = Utilities.formatDate(new Date(), 'America/Santiago', 'yyyy-MM-dd');
  const desde = CONFIG_SYNC.FECHA_INICIO || hoy;
  const hasta = CONFIG_SYNC.FECHA_FIN    || hoy;

  try {
    const resp = UrlFetchApp.fetch(
      `${CONFIG_SYNC.KEPLER_URL}?fecha_inicio=${desde}&fecha_fin=${hasta}`,
      {
        method            : 'GET',
        headers           : { 'Authorization': `Bearer ${CONFIG_SYNC.KEPLER_TOKEN}` },
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

// ─── PARSEAR UNA ACTIVIDAD ────────────────────────────────────
function parseActividad(act) {
  const accessId = (act['Access ID'] || '').toString().trim();
  if (!accessId || accessId === 'Sin Datos') return null;

  const rut_o_bucket    = (act['Rut o Bucket'] || '').trim() || null;
  const tipoBruto       = (act['Tipo red producto'] || '').trim();
  const tipo_red_producto = tipoBruto.toUpperCase().includes('NFTT') ? tipoBruto : null;
  const nombreTecnico   = (act['Técnico'] || act['Activity status change by'] || '').trim() || null;
  const fecha           = normalizarFecha(act['Fecha'] || act['Enrutado automático a fecha'] || '');
  const estado          = (act['Estado'] || '').trim() || null;

  // Orden de Trabajo — intentar varios nombres de campo posibles
  // Si no coincide ninguno, ejecutar diagnosticarCampos() para ver el nombre exacto
  const orden_de_trabajo = (
    act['Orden de Trabajo']  ||
    act['Número OT']         ||
    act['OT']                ||
    act['Numero OT']         ||
    act['orden_de_trabajo']  ||
    act['Actividad']         ||
    ''
  ).toString().trim() || null;

  return {
    access_id         : accessId,
    nombre_tecnico    : nombreTecnico,
    rut_o_bucket      : rut_o_bucket,
    tipo_red_producto : tipo_red_producto,
    estado            : estado,
    id_actividad      : act['ID de actividad'] ? Number(act['ID de actividad']) : null,
    fecha             : fecha,
    orden_de_trabajo  : orden_de_trabajo,
  };
}

// ─── NORMALIZAR FECHA ─────────────────────────────────────────
function normalizarFecha(raw) {
  if (!raw) return null;
  raw = raw.toString().trim();
  if (/^\d{4}-\d{2}-\d{2}$/.test(raw)) return raw;
  const m = raw.match(/^(\d{2})[\/\.](\d{2})[\/\.](\d{2})$/);
  if (m) return `20${m[3]}-${m[2]}-${m[1]}`;
  return null;
}

// ─── CONSULTAR ESTADO ACTUAL EN SUPABASE ─────────────────────
// Devuelve Map { access_id → estado }
function fetchEstadosActuales(ids) {
  const mapa = new Map();
  const BATCH = 100;

  for (let i = 0; i < ids.length; i += BATCH) {
    const lote = ids.slice(i, i + BATCH);
    // Filtro: access_id=in.(id1,id2,...)
    const filtro = lote.map(id => encodeURIComponent(id)).join(',');
    const url = `${CONFIG_SYNC.SUPABASE_URL}/rest/v1/access_id?select=access_id,estado&access_id=in.(${filtro})`;

    try {
      const resp = UrlFetchApp.fetch(url, {
        method            : 'GET',
        headers           : {
          'apikey'       : CONFIG_SYNC.SUPABASE_KEY,
          'Authorization': `Bearer ${CONFIG_SYNC.SUPABASE_KEY}`,
        },
        muteHttpExceptions: true,
      });

      if (resp.getResponseCode() === 200) {
        const rows = JSON.parse(resp.getContentText());
        rows.forEach(row => mapa.set(row.access_id, row.estado || ''));
      } else {
        Logger.log(`fetchEstadosActuales HTTP ${resp.getResponseCode()}: ${resp.getContentText()}`);
      }
    } catch (e) {
      Logger.log(`fetchEstadosActuales excepción: ${e.message}`);
    }
  }

  return mapa;
}

// ─── INSERTAR REGISTROS NUEVOS ────────────────────────────────
function insertarRegistros(registros) {
  const url = `${CONFIG_SYNC.SUPABASE_URL}/rest/v1/access_id`;
  _enviarLotes(url, 'POST', registros, 'return=minimal');
}

// ─── ACTUALIZAR REGISTROS (estado cambió) ────────────────────
// Hace upsert por access_id → pisa todos los campos
function actualizarRegistros(registros) {
  const url = `${CONFIG_SYNC.SUPABASE_URL}/rest/v1/access_id?on_conflict=access_id`;
  _enviarLotes(url, 'POST', registros, 'resolution=merge-duplicates,return=minimal');
}

// ─── HELPER: envío en lotes ───────────────────────────────────
function _enviarLotes(url, method, registros, prefer) {
  const headers = {
    'apikey'       : CONFIG_SYNC.SUPABASE_KEY,
    'Authorization': `Bearer ${CONFIG_SYNC.SUPABASE_KEY}`,
    'Content-Type' : 'application/json',
    'Prefer'       : prefer,
  };
  const BATCH = 50;

  for (let i = 0; i < registros.length; i += BATCH) {
    const lote = registros.slice(i, i + BATCH);
    try {
      const resp = UrlFetchApp.fetch(url, {
        method,
        headers,
        payload           : JSON.stringify(lote),
        muteHttpExceptions: true,
      });
      const code = resp.getResponseCode();
      if (code >= 200 && code < 300) {
        Logger.log(`✓ Lote ${Math.floor(i/BATCH)+1}: ${lote.length} registros OK`);
      } else {
        Logger.log(`✗ Lote ${Math.floor(i/BATCH)+1} error HTTP ${code}: ${resp.getContentText()}`);
      }
    } catch (e) {
      Logger.log(`✗ Lote ${Math.floor(i/BATCH)+1} excepción: ${e.message}`);
    }
  }
}

// ─── TRIGGER CADA 5 MINUTOS ───────────────────────────────────
function crearTrigger() {
  // Elimina triggers anteriores de esta función
  ScriptApp.getProjectTriggers()
    .filter(t => t.getHandlerFunction() === 'syncAccessId')
    .forEach(t => ScriptApp.deleteTrigger(t));

  ScriptApp.newTrigger('syncAccessId')
    .timeBased()
    .everyMinutes(5)
    .create();

  Logger.log('✅ Trigger creado: syncAccessId cada 5 minutos');
}

// ─── DIAGNÓSTICO: ver campos exactos de Kepler ───────────────
// Ejecutar una vez para confirmar el nombre del campo OT
function diagnosticarCampos() {
  const actividades = fetchKepler();
  if (!actividades || actividades.length === 0) {
    Logger.log('Sin actividades');
    return;
  }
  Logger.log('=== CAMPOS DE LA PRIMERA ACTIVIDAD ===');
  Object.entries(actividades[0]).forEach(([k, v]) => Logger.log(`  "${k}" → "${v}"`));
}
