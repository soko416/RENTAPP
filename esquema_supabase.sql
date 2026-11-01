-- =====================================================================
-- Mi app de material de alquiler: esquema para Supabase (Postgres)
-- Pega todo en Supabase > SQL Editor > New query > Run
-- =====================================================================

create extension if not exists btree_gist;

-- ---------- 1. INVENTARIO ----------

create table categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique
);

-- El "tipo" de equipo (ej. "Robe Robin 300")
create table equipment_models (
  id uuid primary key default gen_random_uuid(),
  category_id uuid references categories(id) on delete set null,
  brand text,
  name text not null,
  notes text,
  photo_url text,
  created_at timestamptz not null default now()
);

-- Cada aparato fisico, con su numero de serie y su codigo QR
create table units (
  id uuid primary key default gen_random_uuid(),
  model_id uuid not null references equipment_models(id) on delete cascade,
  serial_number text,
  code text not null unique
    default ('U-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))),
  status text not null default 'ok'
    check (status in ('ok', 'repair', 'lost', 'retired')),
  notes text,
  created_at timestamptz not null default now()
);
create index on units(model_id);

-- ---------- 2. SHOWS Y RESERVAS ----------

create table projects (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  client text,
  venue text,
  status text not null default 'confirmed'
    check (status in ('draft', 'confirmed', 'done', 'cancelled')),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  notes text,
  created_at timestamptz not null default now(),
  check (ends_at > starts_at)
);

create table reservations (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id) on delete cascade,
  unit_id uuid not null references units(id) on delete cascade,
  period tstzrange not null,
  state text not null default 'planned'
    check (state in ('planned', 'out', 'returned')),
  -- La misma unidad no puede estar en dos shows que se solapan
  constraint no_double_booking
    exclude using gist (unit_id with =, period with &&)
    where (state <> 'returned')
);

-- El periodo de la reserva se copia siempre de las fechas del show
create or replace function set_reservation_period() returns trigger as $$
begin
  select tstzrange(starts_at, ends_at) into new.period
  from projects where id = new.project_id;
  return new;
end $$ language plpgsql;

create trigger reservation_period_ins
  before insert on reservations
  for each row execute function set_reservation_period();

-- Si cambias las fechas del show, se actualizan sus reservas
-- (si choca con otro show, Postgres rechaza el cambio)
create or replace function sync_reservation_periods() returns trigger as $$
begin
  update reservations
     set period = tstzrange(new.starts_at, new.ends_at)
   where project_id = new.id and state <> 'returned';
  return new;
end $$ language plpgsql;

create trigger project_dates_changed
  after update of starts_at, ends_at on projects
  for each row execute function sync_reservation_periods();

-- ---------- 3. ESCANEO (salidas y devoluciones) ----------

create table scan_events (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references units(id) on delete cascade,
  project_id uuid references projects(id) on delete set null,
  action text not null check (action in ('out', 'in')),
  at timestamptz not null default now()
);

-- ---------- 4. TECNICOS Y CALENDARIO ----------

create table technicians (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  email text,
  phone text,
  -- enlace secreto para su calendario (.ics)
  calendar_token text not null unique
    default replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''),
  created_at timestamptz not null default now()
);

create table crew_assignments (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id) on delete cascade,
  technician_id uuid not null references technicians(id) on delete cascade,
  role text,
  call_time timestamptz,
  unique (project_id, technician_id)
);

-- ---------- 5. SEGURIDAD: solo tu usuario puede leer y escribir ----------

do $$
declare t text;
begin
  foreach t in array array[
    'categories', 'equipment_models', 'units', 'projects',
    'reservations', 'scan_events', 'technicians', 'crew_assignments'
  ] loop
    execute format('alter table %I enable row level security', t);
    execute format(
      'create policy "solo usuarios autenticados" on %I
         for all to authenticated using (true) with check (true)', t);
  end loop;
end $$;

-- IMPORTANTE: tras crear tu usuario (Authentication > Users > Add user),
-- desactiva los registros nuevos en Authentication > Sign In / Providers
-- ("Allow new users to sign up" = OFF). Asi nadie mas podra entrar.
