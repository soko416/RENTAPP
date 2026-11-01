-- =====================================================================
-- Mi app de material: ESQUEMA V3 (se ejecuta UNA vez, tras esquema_v2.sql)
-- Supabase > SQL Editor > New query > pegar todo > Run
-- Añade: datos del negocio, mantenimiento de equipos y almacén de fotos.
-- No borra ni modifica tus datos actuales.
-- =====================================================================

-- ---------- 1. Datos del negocio (para presupuestos y listas de carga) ----------

create table if not exists settings (
  id integer primary key default 1 check (id = 1),   -- una sola fila
  business_name text,
  tax_id text,
  address text,
  email text,
  phone text,
  logo_data text,                                     -- el logo, ya reducido
  payment_terms text,
  quote_notes text,
  quote_validity_days integer not null default 30 check (quote_validity_days > 0),
  updated_at timestamptz not null default now()
);
insert into settings (id) values (1) on conflict (id) do nothing;

-- ---------- 2. Mantenimiento ----------

alter table units add column if not exists purchase_date date;
alter table units add column if not exists next_service date;
alter table units add column if not exists lamp_hours numeric(10,1) not null default 0 check (lamp_hours >= 0);
alter table equipment_models add column if not exists lamp_life_hours integer check (lamp_life_hours > 0);

create table if not exists maintenance_logs (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references units(id) on delete cascade,
  kind text not null check (kind in ('repair', 'service', 'lamp', 'note')),
  done_on date not null default current_date,
  hours numeric(10,1),
  description text,
  cost numeric(10,2) check (cost >= 0),
  created_at timestamptz not null default now()
);
create index if not exists maintenance_logs_unit on maintenance_logs(unit_id);

-- ---------- 3. Seguridad de las tablas nuevas ----------

do $$
declare t text;
begin
  foreach t in array array['settings', 'maintenance_logs'] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists "solo usuarios autenticados" on %I', t);
    execute format(
      'create policy "solo usuarios autenticados" on %I
         for all to authenticated using (true) with check (true)', t);
  end loop;
end $$;

-- ---------- 4. Almacén de fotos de los equipos ----------
-- El bucket es publico para poder mostrar las fotos; los nombres de archivo
-- llevan un identificador largo, asi que nadie las encuentra sin el enlace.
-- Solo tu usuario puede subir o borrar fotos.

insert into storage.buckets (id, name, public)
values ('fotos', 'fotos', true)
on conflict (id) do nothing;

drop policy if exists "fotos solo usuarios autenticados" on storage.objects;
create policy "fotos solo usuarios autenticados" on storage.objects
  for all to authenticated
  using (bucket_id = 'fotos')
  with check (bucket_id = 'fotos');
