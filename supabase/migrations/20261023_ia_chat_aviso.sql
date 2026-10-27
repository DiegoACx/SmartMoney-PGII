-- ============================================================================
-- SmartMoney · Migración del aviso del chat de IA
-- ----------------------------------------------------------------------------
-- Agrega a public.mensajes_ia la columna:
--   · aviso text → nota legal/orientativa que acompaña la respuesta del
--     asistente y que la app muestra en texto pequeño bajo la burbuja.
--     Ejemplos: 'Es una estimación con tus registros; no es asesoría financiera
--     profesional.' (simular_escenario) o 'Es una orientación general; no es
--     asesoría financiera profesional.' (pedir_consejo).
--
-- Queda null cuando la respuesta no trae aviso. Se guarda junto con la
-- respuesta del asistente para poder pintarlo también al recargar el historial.
--
-- Idempotente. Se aplica manualmente en el SQL Editor de Supabase.
-- ============================================================================

alter table public.mensajes_ia
  add column if not exists aviso text null;
