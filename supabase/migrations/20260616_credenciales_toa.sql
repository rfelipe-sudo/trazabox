create table if not exists public.credenciales_toa (
  rut         text primary key,
  usuario_toa text not null default '',
  email_sso   text not null default '',
  pass_toa    text not null default '',
  activo      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

alter table public.credenciales_toa enable row level security;

create policy "Solo lectura autenticada"
  on public.credenciales_toa for select
  using (auth.role() = 'authenticated');
