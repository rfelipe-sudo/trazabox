/**
 * EXTRACTOR PRODUCCIÓN TRAZA → SUPABASE
 * VERSIÓN SIN FILTRO - Incluye todas las órdenes (completadas, canceladas, etc.)
 */

const CONFIG_TRAZA = {
  // ✅ CAMBIO: Usar get_sabana en lugar de get_sabana_filtrada
  URL_API: "https://kepler.sbip.cl/api/v1/toa/get_sabana/metro/TRAZ",
  SUPABASE_URL: "https://szoywhtkilgvfrczuyqn.supabase.co",
  SUPABASE_KEY: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InN6b3l3aHRraWxndmZyY3p1eXFuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAyMjk3NTEsImV4cCI6MjA4NTgwNTc1MX0.sXoPmnZqRJXmaSfA0Mw9HlprVHI_okhTMKrSgONlAOk",
  TABLA: "produccion"
};

// NOTA: Si get_sabana no funciona, prueba con:
// URL_API: "https://kepler.sbip.cl/api/v1/toa/get_sabana_filtrada/metro/TRAZ?todos_estados=true"
// O contacta al equipo de IT para el endpoint correcto

// ... (resto del código igual)

