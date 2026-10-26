-- ============================================================================
-- SmartMoney · Columna categoria_sugerida_id en public.transacciones
--
-- Guarda QUÉ categoría sugirió el clasificador al registrar un egreso, para
-- poder medir después cuántas veces el usuario aceptó la sugerencia
-- (aceptada = confianza_sugerencia no es null y categoria_corregida = false).
--
-- Requisitos:
--   · Idempotente (se puede correr varias veces sin error).
--   · Columna nullable: no afecta los movimientos existentes.
--   · NO modifica políticas RLS ni grants existentes.
--
-- IMPORTANTE · Sin foreign key (a propósito):
--   No se crea la FK de categoria_sugerida_id hacia public.categorias. Tener una
--   segunda relación entre "transacciones" y "categorias" hace AMBIGUOS los
--   embeds de PostgREST y rompe las consultas con el error
--   PGRST201 ("Could not embed because more than one relationship was found
--   for 'transacciones' and 'categorias'"). Por eso se deja la columna sin FK y
--   se asegura de eliminar la restricción si quedó creada de una corrida previa.
--   Las consultas que embeben categorías ahora declaran la relación explícita
--   (categorias!fk_transacciones_categoria(...)).
--
-- Nota: confianza_sugerencia ya existe (migración 20261021_ia_modulo_esquema).
-- Se aplica manualmente en el SQL Editor de Supabase.
-- ============================================================================

begin;

alter table public.transacciones
  add column if not exists categoria_sugerida_id uuid null;

-- La FK se omite a propósito para evitar el PGRST201 (ver nota de arriba).
-- Si una corrida anterior la creó, se elimina aquí (idempotente).
alter table public.transacciones
  drop constraint if exists transacciones_categoria_sugerida_id_fkey;

commit;
