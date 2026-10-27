-- ============================================================================
-- SmartMoney · Migración del chat de IA
-- ----------------------------------------------------------------------------
-- Agrega a public.mensajes_ia las columnas que guarda la Edge Function chat-ia:
--   · confianza numeric → nivel de confianza del clasificador de intención;
--   · origen   text     → 'plantilla' | 'llm' | 'faq' | 'calculo';
--   · accion   jsonb    → acción de navegación sugerida (o null).
--
-- Idempotente. Se aplica manualmente en el SQL Editor de Supabase.
-- ============================================================================

alter table public.mensajes_ia
  add column if not exists confianza numeric null;

alter table public.mensajes_ia
  add column if not exists origen text null;

alter table public.mensajes_ia
  add column if not exists accion jsonb null;
