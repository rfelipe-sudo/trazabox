import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const MASLOW_URL =
  'https://maslowtraza.sbip.cl/api/sync/trabajadores?include_manager=true'

const MASLOW_API_KEY =
  Deno.env.get('MASLOW_API_KEY') ?? 'ur75OfrLVbZ40iR3QqR23SDnR1oxxY73Hh9nj'

Deno.serve(async () => {
  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    // 1. Obtener trabajadores desde Maslow
    const resp = await fetch(MASLOW_URL, {
      headers: { 'X-Api-Key': MASLOW_API_KEY },
    })

    if (!resp.ok) {
      return json({ error: `Maslow API error: ${resp.status}` }, 500)
    }

    const data = await resp.json()
    const trabajadores: any[] = data.trabajadores ?? []

    // 2. Construir pares supervisor→técnico (solo activos con jefe asignado)
    const zonaMap: Record<string, string> = {
      '17': 'metropolitana',
      '23': 'centro',
    }

    const pares = trabajadores
      .filter((t) => t.estado === 1 && t.rut && t.jefe_directo?.rut)
      .map((t) => ({
        rut_supervisor: t.jefe_directo.rut as string,
        rut_tecnico: t.rut as string,
        zona: zonaMap[String(t.centro_costo_code)] ?? null,
      }))

    // Guardia: si Maslow devuelve menos de 50 pares algo raro pasó, no borrar
    if (pares.length < 50) {
      return json(
        { error: 'Pocos pares recibidos, sync abortado', recibidos: pares.length },
        200,
      )
    }

    // 3. Reemplazar tabla completa: borrar todo e insertar nuevos pares
    const { error: delErr } = await supabase
      .from('supervisor_tecnicos_traza')
      .delete()
      .neq('id', 0)

    if (delErr) throw delErr

    const { error: insErr } = await supabase
      .from('supervisor_tecnicos_traza')
      .insert(pares)

    if (insErr) throw insErr

    console.log(`[sync-supervisor] OK — ${pares.length} pares sincronizados`)
    return json({ ok: true, synced: pares.length, at: new Date().toISOString() })
  } catch (err) {
    console.error('[sync-supervisor] ERROR:', err)
    return json({ error: String(err) }, 500)
  }
})

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}
