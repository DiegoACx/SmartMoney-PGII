-- ============================================================================
-- SmartMoney · Migración del motivo del chat de IA
-- ----------------------------------------------------------------------------
-- Agrega a public.mensajes_ia la columna:
--   · motivo text → cómo se decidió la respuesta. 'regla:<patrón>' cuando la
--     intención la decidió una regla híbrida del manejador (no el modelo);
--     en los demás casos, el motivo del resultado (ej. 'simulacion:meta_plazo'
--     o 'simulacion:meta_plazo:validacion:falta_cifra').
--
-- Permite separar en la evaluación lo que decide la regla de lo que decide el
-- modelo. Nunca contiene el texto del mensaje del usuario.
--
-- Idempotente. Se aplica manualmente en el SQL Editor de Supabase.
-- ============================================================================

alter table public.mensajes_ia
  add column if not exists motivo text null;
