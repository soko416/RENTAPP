-- =====================================================================
-- Mi app de material: ESQUEMA V2 (se ejecuta UNA vez, encima del primero)
-- Supabase > SQL Editor > New query > pegar todo > Run
-- Añade: material por cantidad, kits/flight cases, tarifas y presupuesto
-- No borra ni modifica tus datos actuales.
-- =====================================================================

-- ---------- 1. Material por cantidad (cables, consumibles) y tarifas ----------

alter table equipment_models add column if not exists is_bulk boolean not null default false;
alter table equipment_models add column if not exists bulk_stock integer not null default 0 check (bulk_stock >= 0);
alter table equipment_models add column if not exists day_rate numeric(10,2) check (day_rate >= 0);

-- ---------- 2. Kits y flight cases ----------

create table if not exists kits (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text not null unique
    default ('K-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))),
  notes text,
  created_at timestamptz not null default now()
);

-- Contenido de un kit: o una unidad concreta, o una cantidad de un modelo "por cantidad"
create table if not exists kit_items (
  id uuid primary key default gen_random_uuid(),
  kit_id uuid not null references kits(id) on delete cascade,
  unit_id uuid references units(id) on delete cascade,
  model_id uuid references equipment_models(id) on delete cascade,
  qty integer not null default 1 check (qty > 0),
  check ((unit_id is not null) <> (model_id is not null))
);

-- Las reservas recuerdan de qué kit vienen (si vienen de uno)
alter table reservations add column if not exists kit_id uuid references kits(id) on delete set null;

-- ---------- 3. Reservas de material por cantidad ----------

create table if not exists bulk_reservations (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id) on delete cascade,
  model_id uuid not null references equipment_models(id) on delete cascade,
  qty integer not null check (qty > 0),
  state text not null default 'planned'
    check (state in ('planned', 'out', 'returned')),
  kit_id uuid references kits(id) on delete set null,
  created_at timestamptz not null default now()
);

-- Impide reservar mas cantidad de la que tienes en stock en fechas que se solapan
create or replace function check_bulk_stock() returns trigger as $$
declare
  v_stock integer; v_start timestamptz; v_end timestamptz; v_used integer;
begin
  if new.state = 'returned' then return new; end if;
  select bulk_stock into v_stock from equipment_models where id = new.model_id;
  select starts_at, ends_at into v_start, v_end from projects where id = new.project_id;
  select coalesce(sum(b.qty), 0) into v_used
    from bulk_reservations b
    join projects p on p.id = b.project_id
   where b.model_id = new.model_id
     and b.state <> 'returned'
     and b.id <> new.id
     and p.status <> 'cancelled'
     and tstzrange(p.starts_at, p.ends_at) && tstzrange(v_start, v_end);
  if v_used + new.qty > v_stock then
    raise exception 'No hay stock suficiente: quedan % de % unidades libres en esas fechas.',
      greatest(v_stock - v_used, 0), v_stock using errcode = '23514';
  end if;
  return new;
end $$ language plpgsql;

drop trigger if exists bulk_stock_check on bulk_reservations;
create trigger bulk_stock_check
  before insert or update of qty, state, project_id on bulk_reservations
  for each row execute function check_bulk_stock();

-- ---------- 4. Presupuesto en cada show ----------

alter table projects add column if not exists rental_days integer check (rental_days > 0);
alter table projects add column if not exists discount_pct numeric(5,2) not null default 0 check (discount_pct >= 0 and discount_pct <= 100);
alter table projects add column if not exists vat_pct numeric(5,2) not null default 21 check (vat_pct >= 0);

-- ---------- 5. Seguridad de las tablas nuevas ----------

do $$
declare t text;
begin
  foreach t in array array['kits', 'kit_items', 'bulk_reservations'] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists "solo usuarios autenticados" on %I', t);
    execute format(
      'create policy "solo usuarios autenticados" on %I
         for all to authenticated using (true) with check (true)', t);
  end loop;
end $$;
