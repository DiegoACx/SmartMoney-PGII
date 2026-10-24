-- ============================================================================
-- SmartMoney · Migración del feedback del chat de IA
-- ----------------------------------------------------------------------------
-- 1) Columnas nuevas en public.mensajes_ia:
--      · util          boolean     → 👍 (true) / 👎 (false) sobre una respuesta;
--                                    null = todavía sin calificar.
--      · respondido_en timestamptz → momento en que el usuario calificó;
--                                    null = todavía sin calificar.
-- 2) Permisos: SELECT y DELETE de sus mensajes, y UPDATE solo de util /
--    respondido_en. Sin INSERT: la Edge Function guarda los mensajes.
-- 3) Políticas RLS para que el usuario actualice y borre ÚNICAMENTE sus filas
--    (botones 👍/👎 y "Borrar conversación" de la pantalla de chat).
--
-- Idempotente. Se aplica manualmente en el SQL Editor de Supabase.
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- 1) Columnas de feedback
-- ----------------------------------------------------------------------------
alter table public.mensajes_ia
  add column if not exists util boolean null;

alter table public.mensajes_ia
  add column if not exists respondido_en timestamptz null;

-- ----------------------------------------------------------------------------
-- 2) Permisos para el rol authenticated
-- ----------------------------------------------------------------------------
-- El usuario lee y borra sus mensajes; solo puede actualizar la calificación.
-- No necesita INSERT: los mensajes los guarda la Edge Function con service_role.
revoke insert, update on public.mensajes_ia from authenticated;
grant select, delete on public.mensajes_ia to authenticated;
grant update (util, respondido_en) on public.mensajes_ia to authenticated;

-- Mismo ajuste para recomendaciones (solo campos de interacción).
revoke update on public.recomendaciones from authenticated;
grant update (util, respondido_en, mostrada_en) on public.recomendaciones to authenticated;

-- ----------------------------------------------------------------------------
-- 3) Políticas RLS
-- ----------------------------------------------------------------------------
alter table public.mensajes_ia enable row level security;

-- UPDATE solo de filas propias (util / respondido_en).
drop policy if exists mensajes_ia_update_propias on public.mensajes_ia;
create policy mensajes_ia_update_propias
  on public.mensajes_ia for update to authenticated
  using (auth.uid() = usuario_id)
  with check (auth.uid() = usuario_id);

-- DELETE solo de filas propias ("Borrar conversación").
drop policy if exists mensajes_ia_delete_propias on public.mensajes_ia;
create policy mensajes_ia_delete_propias
  on public.mensajes_ia for delete to authenticated
  using (auth.uid() = usuario_id);

notify pgrst, 'reload schema';

commit;
