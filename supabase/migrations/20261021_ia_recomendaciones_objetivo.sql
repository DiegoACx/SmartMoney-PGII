-- ============================================================================
-- SmartMoney · Módulo de IA · Ajustes del motor tras pruebas con datos reales
-- ----------------------------------------------------------------------------
-- 1) recomendaciones.objetivo
--    Entidad señalada por la recomendación: 'grupo:1', 'categoria:<uuid>',
--    'meta:<uuid>', 'transaccion:<uuid>' o 'riesgo:mes'. Con esta columna el
--    motor bloquea duplicados pendientes sin tener que leer hallazgos.
--
-- 2) linea_base_usuario.n_movimientos
--    Cantidad de movimientos de la categoría usados para la mediana y la MAD
--    por movimiento (n_semanas se sigue llenando con las semanas con registros).
--
-- Idempotente (IF NOT EXISTS). Se aplica manualmente en el SQL Editor.
-- ============================================================================

begin;

-- ============================================================================
-- PASO 1 · recomendaciones: columna objetivo
-- ============================================================================
alter table public.recomendaciones
  add column if not exists objetivo text null;


-- ============================================================================
-- PASO 2 · linea_base_usuario: columna n_movimientos
-- ============================================================================
alter table public.linea_base_usuario
  add column if not exists n_movimientos int not null default 0;


-- ============================================================================
-- PASO 3 · Relleno de objetivo en las recomendaciones ya existentes
--          (se copia desde hallazgos.datos->>'objetivo')
-- ============================================================================
update public.recomendaciones r
   set objetivo = h.datos->>'objetivo'
  from public.hallazgos h
 where r.hallazgo_id = h.id
   and r.objetivo is null
   and h.datos ? 'objetivo';

commit;


-- ============================================================================
-- PASO 4 · Verificación (ejecutar aparte, tras aplicar la migración)
-- ============================================================================
-- select count(*) from public.recomendaciones where objetivo is null;   -- esperado 0
-- select n_movimientos, count(*) from public.linea_base_usuario group by 1 order by 1;
