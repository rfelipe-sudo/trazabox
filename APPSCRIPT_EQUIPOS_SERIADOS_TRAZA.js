/**
 * SYNC EQUIPOS SERIADOS TRAZA
 * ═══════════════════════════
 * Lee la sábana TOA filtrada de Kepler (metro + centro, empresa TRAZ),
 * extrae las series del campo "Instalados al Final de la actividad" de las
 * actividades COMPLETADAS, deduce el tipo de equipo (ONT/DECO/EXTENSOR)
 * cruzando cada serie contra el inventario de traza materiales, y hace
 * upsert en la tabla `equipos_seriados_traza` de Supabase.
 *
 * ¿Por qué? La sábana se extingue a diario. Esta tabla es el histórico
 * permanente que consulta TrazaBox (orden_trabajo - rut - tipo - serie).
 *
 * INSTALACIÓN:
 * 1. script.google.com → Nuevo proyecto → pegar este archivo.
 * 2. Configuración del proyecto → zona horaria: America/Santiago.
 * 3. Reemplazar SUPABASE_SERVICE_KEY (¡service_role, NO la anon!).
 * 4. Activadores (⏰): función `syncEquiposSeriados`, "según tiempo":
 *    - uno diario entre 21:00-22:00  (cierre del día, el importante)
 *    - opcional: otro entre 14:00-15:00 (adelanta lo de la mañana)
 *    El upsert es idempotente: correr varias veces no duplica.
 * 5. Probar a mano: ejecutar `syncEquiposSeriados` y revisar el log.
 */

// ── Configuración ────────────────────────────────────────────────────────────
const KEPLER_BASE = 'https://kepler.sbip.cl/api/v1/toa/get_sabana_filtrada';
const KEPLER_TOKEN = 'F2ZFFWfwpVKVmT9XaJiFYigZInFYoeEBZfDPTKjyu3IZJcTG1vIUb3ccu7rQUOGT';
const ZONAS = ['metro', 'centro'];
const EMPRESA = 'TRAZ';

const PROXY_TRAZA = 'https://proxy-traza.sbip.cl';
const PROXY_API_KEY = '6db9d17817d6d97047312b9d43bcc5bd43dcfab6e33ba459796f1bf6cec48a68';

const SUPABASE_URL = 'https://szoywhtkilgvfrczuyqn.supabase.co';
const SUPABASE_SERVICE_KEY = 'PEGAR_AQUI_SERVICE_ROLE_KEY';

// ── Configurar triggers (correr UNA VEZ, igual que tus otros scripts) ───────
function configurarTriggers() {
  // Elimina triggers previos de esta función para no duplicar
  ScriptApp.getProjectTriggers().forEach(function (t) {
    if (t.getHandlerFunction() === 'syncEquiposSeriados') {
      ScriptApp.deleteTrigger(t);
    }
  });

  // Diario: 11:00, 14:00, 16:00, 18:00 y 20:00
  [11, 14, 16, 18, 20].forEach(function (hora) {
    ScriptApp.newTrigger('syncEquiposSeriados')
        .timeBased().everyDays(1).atHour(hora).create();
  });

  Logger.log('✅ Triggers creados: 11:00, 14:00, 16:00, 18:00 y 20:00 (diario)');
}

// ── Entrada principal (el trigger apunta aquí) ───────────────────────────────
function syncEquiposSeriados() {
  const registros = [];

  for (const zona of ZONAS) {
    const data = leerSabana_(zona);
    if (!data) continue;

    for (const r of data) {
      const raw = String(r['Instalados al Final de la actividad'] || '');
      if (!raw || raw === 'Sin Datos') continue;

      const ot = String(r['Orden de Trabajo'] || '').trim();
      const rut = String(r['Rut o Bucket'] || '').trim();
      if (!ot || !rut) continue;

      const series = raw
        .split(',')
        .map(function (s) { return s.trim(); })
        .filter(function (s) { return s.length >= 5; });

      for (const serie of series) {
        registros.push({
          orden_trabajo: ot,
          rut_tecnico: rut,
          serie: serie,
          fecha_trabajo: formatearFecha_(String(r['Fecha'] || '')),
          zona: zona,
        });
      }
    }
  }

  Logger.log('Series encontradas en sábana: ' + registros.length);
  if (!registros.length) return;

  clasificarPorInventario_(registros);
  upsertSupabase_(registros);
}

// ── Lectura de sábana ────────────────────────────────────────────────────────
function leerSabana_(zona) {
  try {
    const resp = UrlFetchApp.fetch(KEPLER_BASE + '/' + zona + '/' + EMPRESA, {
      headers: { Authorization: 'Bearer ' + KEPLER_TOKEN },
      muteHttpExceptions: true,
    });
    if (resp.getResponseCode() !== 200) {
      Logger.log('Sábana ' + zona + ' HTTP ' + resp.getResponseCode());
      return null;
    }
    return JSON.parse(resp.getContentText()).data || [];
  } catch (e) {
    Logger.log('Error sábana ' + zona + ': ' + e);
    return null;
  }
}

// "25/08/26" (dd/MM/yy) → "2026-08-25"
function formatearFecha_(f) {
  const m = f.match(/^(\d{2})\/(\d{2})\/(\d{2})$/);
  if (!m) return null;
  return '20' + m[3] + '-' + m[2] + '-' + m[1];
}

// ── Clasificación: serie → tipo, cruzando con traza materiales ──────────────
function clasificarPorInventario_(registros) {
  // Un fetch de inventario por RUT (cache dentro de la corrida)
  const porRut = {};
  registros.forEach(function (r) {
    (porRut[r.rut_tecnico] = porRut[r.rut_tecnico] || []).push(r);
  });

  Object.keys(porRut).forEach(function (rut) {
    let inventario = [];
    try {
      const resp = UrlFetchApp.fetch(
        PROXY_TRAZA + '/stocks/inventario/por-rut/' + encodeURIComponent(rut),
        { headers: { 'X-API-Key': PROXY_API_KEY }, muteHttpExceptions: true }
      );
      if (resp.getResponseCode() === 200) {
        inventario = JSON.parse(resp.getContentText());
      }
    } catch (e) {
      Logger.log('Error inventario ' + rut + ': ' + e);
    }

    // serie → nombre de material
    const mapa = {};
    inventario.forEach(function (mat) {
      (mat.series || []).forEach(function (s) {
        mapa[String(s).trim()] = mat.nombreMaterial || '';
      });
    });

    porRut[rut].forEach(function (r) {
      const nombre = mapa[r.serie] || '';
      r.descripcion = nombre || null;
      r.tipo_equipo = nombre
          ? tipoDesdeNombre_(nombre)
          : tipoDesdePrefijo_(r.serie);
      // Si el nombre no clasificó, intentar por prefijo igual
      if (r.tipo_equipo === 'OTRO') {
        r.tipo_equipo = tipoDesdePrefijo_(r.serie);
      }
    });
  });
}

// Fallback cuando la serie no cruza con el inventario: clasificar por
// PREFIJO de la serie (mapeo derivado de ~9.800 series ya clasificadas;
// sin esto, equipos entregados directo de bodega central quedaban 'OTRO'
// y bloqueaban la validación "Alta exige 1 ONT" en la app).
function tipoDesdePrefijo_(serie) {
  const p4 = (serie || '').toUpperCase().substring(0, 4);
  const mapa = {
    'HWTC': 'ONT', 'ZTEG': 'ONT',
    '4857': 'EXTENSOR', 'ZTE0': 'EXTENSOR',
    'E77B': 'DECO', 'E457': 'DECO', '1835': 'DECO', '400D': 'DECO',
    '48D3': 'DECO', 'ACF8': 'DECO', 'C005': 'DECO',
  };
  if (mapa[p4]) return mapa[p4];
  const p3 = p4.substring(0, 3);
  if (p3 === 'M91' || p3 === 'M92') return 'DECO';
  // Extensores Sercomm nuevos: serie tipo "2201DFC001737"
  if ((serie || '').toUpperCase().indexOf('DFC') === 4) return 'EXTENSOR';
  return 'OTRO';
}

function tipoDesdeNombre_(nombre) {
  const n = (nombre || '').toUpperCase();
  if (!n) return 'OTRO';
  if (n.indexOf('ONT') >= 0 || n.indexOf('GPON') >= 0) return 'ONT';
  if (n.indexOf('EXTENSOR') >= 0 || n.indexOf('EXTENDER') >= 0 ||
      n.indexOf('RP362') >= 0 || n.indexOf('K562') >= 0 ||
      n.indexOf('H3601') >= 0 || n.indexOf('AP ') >= 0) return 'EXTENSOR';
  if (n.indexOf('GATEWAY') >= 0) return 'GATEWAY';
  if (n.indexOf('MTA') >= 0 || n.indexOf('EMTA') >= 0) return 'MTA';
  if (n.indexOf('TOP BOX') >= 0 || n.indexOf('STB') >= 0 ||
      n.indexOf('DECO') >= 0 || n.indexOf('CPE') >= 0 ||
      n.indexOf('FUSE') >= 0 || n.indexOf('DBOX') >= 0 ||
      n.indexOf('D-BOX') >= 0 || n.indexOf('ARRIS') >= 0 ||
      n.indexOf('IPTV') >= 0) return 'DECO';
  return 'OTRO';
}

// ── Upsert a Supabase ────────────────────────────────────────────────────────
function upsertSupabase_(registros) {
  const url = SUPABASE_URL +
      '/rest/v1/equipos_seriados_traza?on_conflict=orden_trabajo,serie';
  const resp = UrlFetchApp.fetch(url, {
    method: 'post',
    contentType: 'application/json',
    headers: {
      apikey: SUPABASE_SERVICE_KEY,
      Authorization: 'Bearer ' + SUPABASE_SERVICE_KEY,
      // ignore-duplicates: si la OT+serie ya existe, se conserva el registro
      // original (con su fecha de instalación) en vez de sobrescribirlo
      Prefer: 'resolution=ignore-duplicates,return=minimal',
    },
    payload: JSON.stringify(registros),
    muteHttpExceptions: true,
  });
  Logger.log('Upsert Supabase HTTP ' + resp.getResponseCode() + ' — ' +
      registros.length + ' registros');
  if (resp.getResponseCode() >= 300) Logger.log(resp.getContentText());
}
