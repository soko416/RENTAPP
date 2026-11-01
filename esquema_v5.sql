-- =====================================================================
-- Mi app de material: ESQUEMA V5 (se ejecuta UNA vez, tras esquema_v4.sql)
-- Supabase > SQL Editor > New query > pegar todo > Run
-- Añade: estado al devolver (completo / reparación / incompleto), peso,
-- medidas y potencia de cada equipo, cobros y rider técnico de cada show.
-- No borra ni modifica tus datos actuales.
-- =====================================================================

-- ---------- 1. Estado al devolver ----------

-- Lo que falta en un equipo incompleto (vacío si está completo)
alter table units add column if not exists missing_note text;

-- Cada escaneo de entrada guarda en qué estado volvió el equipo
alter table scan_events add column if not exists condition text check (condition in ('ok', 'repair', 'incomplete'));
alter table scan_events add column if not exists note text;

-- El mantenimiento admite el tipo "incompleto"
alter table maintenance_logs drop constraint if exists maintenance_logs_kind_check;
alter table maintenance_logs add constraint maintenance_logs_kind_check
  check (kind in ('repair', 'service', 'lamp', 'note', 'missing'));

-- ---------- 2. Peso, medidas y potencia ----------

alter table equipment_models add column if not exists weight_kg numeric(8,2) check (weight_kg >= 0);
alter table equipment_models add column if not exists width_cm numeric(7,1) check (width_cm >= 0);
alter table equipment_models add column if not exists height_cm numeric(7,1) check (height_cm >= 0);
alter table equipment_models add column if not exists depth_cm numeric(7,1) check (depth_cm >= 0);
alter table equipment_models add column if not exists power_w integer check (power_w >= 0);

-- Peso y medidas del flight case (vacío) de cada kit
alter table kits add column if not exists weight_kg numeric(8,2) check (weight_kg >= 0);
alter table kits add column if not exists width_cm numeric(7,1) check (width_cm >= 0);
alter table kits add column if not exists height_cm numeric(7,1) check (height_cm >= 0);
alter table kits add column if not exists depth_cm numeric(7,1) check (depth_cm >= 0);

-- Capacidad de tu furgoneta (opcional)
alter table settings add column if not exists van_volume_m3 numeric(6,2) check (van_volume_m3 > 0);
alter table settings add column if not exists van_payload_kg integer check (van_payload_kg > 0);

-- ---------- 3. Cobros y rider de cada show ----------

alter table projects add column if not exists payment_status text not null default 'none'
  check (payment_status in ('none', 'quoted', 'accepted', 'invoiced', 'paid'));
alter table projects add column if not exists invoice_number text;
alter table projects add column if not exists due_date date;
alter table projects add column if not exists paid_date date;
alter table projects add column if not exists agreed_total numeric(10,2) check (agreed_total >= 0);
alter table projects add column if not exists rider_notes text;
