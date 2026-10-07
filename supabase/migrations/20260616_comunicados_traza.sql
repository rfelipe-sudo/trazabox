-- Comunicados masivos/personalizados para TRAZABOX
-- Ejecutar en Supabase SQL Editor del proyecto szoywhtkilgvfrczuyqn

create table if not exists public.comunicados_traza (
  id            uuid        primary key default gen_random_uuid(),
  titulo        text        not null,
  mensaje       text        not null,
  tipo          text        not null default 'masivo', -- masivo | personalizado | por_roles
  rut_destino   text,                                  -- personalizado: un RUT
  ruts_destino  text[],                                -- personalizado: varios RUTs
  roles_destino text[],                                -- por_roles: ['tecnico','supervisor']
  activo        boolean     not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

alter table public.comunicados_traza enable row level security;

create policy "Lectura autenticada comunicados"
  on public.comunicados_traza for select
  using (auth.role() = 'authenticated');

-- Lecturas y firmas de cada técnico
create table if not exists public.comunicados_lecturas (
  id             uuid        primary key default gen_random_uuid(),
  comunicado_id  uuid        not null references public.comunicados_traza(id) on delete cascade,
  rut_tecnico    text        not null,
  nombre_tecnico text        not null default '',
  estado         text        not null default 'pendiente', -- pendiente | leido
  leido_at       timestamptz,
  firma_base64   text,
  firma_at       timestamptz,
  created_at     timestamptz not null default now()
);

alter table public.comunicados_lecturas enable row level security;

create policy "Lectura autenticada lecturas"
  on public.comunicados_lecturas for select
  using (auth.role() = 'authenticated');

create policy "Insertar lecturas autenticado"
  on public.comunicados_lecturas for insert
  with check (auth.role() = 'authenticated');

create policy "Actualizar lecturas autenticado"
  on public.comunicados_lecturas for update
  using (auth.role() = 'authenticated');

-- Habilitar Realtime en comunicados_traza para recibir inserts en tiempo real
alter publication supabase_realtime add table public.comunicados_traza;
