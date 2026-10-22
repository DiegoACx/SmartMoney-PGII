-- ============================================================================
-- SmartMoney · Migración del bandido Thompson Sampling
-- ----------------------------------------------------------------------------
-- 1. Trazabilidad en hallazgos: grupo del A/B y α/β del tipo.
-- 2. estadisticas_bandido(): conteos globales (útil / no útil) por tipo en una
--    sola consulta agregada, para el prior poblacional jerárquico.
--
-- Idempotente (IF NOT EXISTS / create or replace). Se aplica a mano en el SQL
-- Editor de Supabase. No usa DROP TABLE ni DELETE.
-- ============================================================================

begin;

-- ============================================================================
-- PASO 1 · Trazabilidad del bandido en hallazgos
-- ============================================================================
alter table public.hallazgos
  add column if not exists grupo_experimento text   null;
alter table public.hallazgos
  add column if not exists alfa             numeric null;
alter table public.hallazgos
  add column if not exists beta             numeric null;

-- grupo_experimento solo admite los dos brazos del A/B (riesgo_fin_de_mes
-- también lo guarda, pero no α/β).
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'hallazgos_grupo_experimento_check'
  ) then
    alter table public.hallazgos
      add constraint hallazgos_grupo_experimento_check
      check (grupo_experimento is null or grupo_experimento in ('bandido','control'));
  end if;
end $$;


-- ============================================================================
-- PASO 2 · Conteos globales para el prior poblacional
-- ----------------------------------------------------------------------------
-- Devuelve, por tipo del bandido, cuántas recomendaciones fueron marcadas como
-- útiles y cuántas como no útiles. Solo cuenta las respondidas (util no nulo).
-- security definer: es una agregación global, no expone filas ni datos propios.
-- ============================================================================
create or replace function public.estadisticas_bandido()
returns table (tipo text, utiles bigint, no_utiles bigint)
language sql
security definer
set search_path = public
as $$
  select r.tipo,
         count(*) filter (where r.util is true)  as utiles,
         count(*) filter (where r.util is false) as no_utiles
    from public.recomendaciones r
   where r.util is not null
     and r.tipo in ('sobregasto_categoria','gasto_anomalo','aporte_meta',
                    'leccion_sugerida','logro')
   group by r.tipo;
$$;

-- Solo el service_role (Edge Function) puede llamarla.
revoke all on function public.estadisticas_bandido() from public;
revoke all on function public.estadisticas_bandido() from anon;
revoke all on function public.estadisticas_bandido() from authenticated;
grant execute on function public.estadisticas_bandido() to service_role;

commit;


-- ============================================================================
-- PASO 3 · Consultas de verificación (ejecutar aparte, tras aplicar)
-- ============================================================================
-- select * from public.estadisticas_bandido();
-- select grupo_experimento, count(*) from public.hallazgos
--    group by grupo_experimento order by grupo_experimento;
-- select tipo, alfa, beta, alfa / nullif(alfa + beta, 0) as media
--    from public.preferencias_recomendacion order by usuario_id, tipo;
