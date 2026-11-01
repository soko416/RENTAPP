-- =====================================================================
-- Mi app de material: ESQUEMA V4 (se ejecuta UNA vez, tras esquema_v3.sql)
-- Supabase > SQL Editor > New query > pegar todo > Run
-- Añade: color de cada modelo y la leyenda de colores (para cables).
-- No borra ni modifica tus datos actuales.
-- =====================================================================

alter table equipment_models add column if not exists color text;
alter table settings add column if not exists color_legend jsonb not null default '[]'::jsonb;
