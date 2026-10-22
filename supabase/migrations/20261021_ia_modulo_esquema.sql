-- ============================================================================
-- SmartMoney · Migración de base para el módulo de IA
-- Crea esquema, datos semilla y políticas RLS. NO incluye lógica de IA.
-- Idempotente donde es posible (IF NOT EXISTS / DO blocks / upserts).
-- Esta migración NO usa DROP TABLE ni DELETE sobre tablas existentes.
--
-- Tabla de movimientos real:  public.transacciones
-- Tabla de categorías real:   public.categorias
--   (id uuid, usuario_id uuid null, nombre text, tipo text, fecha_creacion
--    timestamptz null, es_predeterminada boolean null)
--
-- Se aplica manualmente en el SQL Editor de Supabase.
-- ============================================================================

begin;

-- ============================================================================
-- PASO 1 · Catálogo fijo de grupos de referencia
-- ============================================================================
create table if not exists public.grupos_referencia (
  id                    smallint primary key,
  nombre                text        not null,
  division_dane         text,
  proporcion_referencia numeric     null,
  incluir_en_referencia boolean     not null default true
);

alter table public.grupos_referencia enable row level security;

insert into public.grupos_referencia (id, nombre, division_dane, incluir_en_referencia)
values
  (1,  'Mercado',                           'Alimentos y bebidas no alcohólicas',   true),
  (2,  'Licor y cigarrillos',               'Bebidas alcohólicas y tabaco',         true),
  (3,  'Ropa y calzado',                    'Prendas de vestir y calzado',          true),
  (4,  'Vivienda y servicios',              'Alojamiento, agua, electricidad, gas', true),
  (5,  'Hogar',                             'Muebles y artículos para el hogar',    true),
  (6,  'Salud',                             'Salud',                                true),
  (7,  'Transporte',                        'Transporte',                           true),
  (8,  'Celular, internet y suscripciones', 'Información y comunicación',           true),
  (9,  'Entretenimiento',                   'Recreación y cultura',                 true),
  (10, 'Educación',                         'Educación',                            true),
  (11, 'Comidas fuera y domicilios',        'Restaurantes y hoteles',               true),
  (12, 'Otros gastos personales',           'Bienes y servicios diversos',          true),
  (13, 'Obligaciones y transferencias',      null,                                  false)
on conflict (id) do nothing;

-- RLS: solo lectura para usuarios autenticados; sin escritura desde la app.
drop policy if exists grupos_referencia_select_autenticados on public.grupos_referencia;
create policy grupos_referencia_select_autenticados
  on public.grupos_referencia
  for select
  to authenticated
  using (true);


-- ============================================================================
-- PASO 2 · Categorías: columna grupo_id + datos
-- ============================================================================
alter table public.categorias
  add column if not exists grupo_id smallint null
  references public.grupos_referencia(id);

-- 2.1 Renombrar "Alimentación" -> "Mercado" (UPDATE: conserva el id y sus movimientos)
update public.categorias
   set nombre   = 'Mercado',
       grupo_id = 1
 where usuario_id is null
   and tipo = 'egreso'
   and nombre = 'Alimentación';

-- 2.2 Asignar grupo a categorías por defecto existentes (UPDATE por nombre)
update public.categorias set grupo_id = 4  where usuario_id is null and tipo = 'egreso' and nombre = 'Vivienda';
update public.categorias set grupo_id = 4  where usuario_id is null and tipo = 'egreso' and nombre = 'Servicios públicos';
update public.categorias set grupo_id = 3  where usuario_id is null and tipo = 'egreso' and nombre = 'Ropa';
update public.categorias set grupo_id = 6  where usuario_id is null and tipo = 'egreso' and nombre = 'Salud';
update public.categorias set grupo_id = 7  where usuario_id is null and tipo = 'egreso' and nombre = 'Transporte';
update public.categorias set grupo_id = 9  where usuario_id is null and tipo = 'egreso' and nombre = 'Entretenimiento';
update public.categorias set grupo_id = 10 where usuario_id is null and tipo = 'egreso' and nombre = 'Educación';
update public.categorias set grupo_id = 12 where usuario_id is null and tipo = 'egreso' and nombre = 'Otros gastos';

-- 2.3 Crear categorías por defecto que falten
--     (usuario_id = NULL, es_predeterminada = true; solo si no existe ya una
--      con ese nombre y usuario_id NULL)
insert into public.categorias (nombre, tipo, usuario_id, es_predeterminada, grupo_id)
select v.nombre, 'egreso', null, true, v.grupo_id
  from (values
    ('Comidas fuera y domicilios',    11),
    ('Licor y cigarrillos',            2),
    ('Hogar',                          5),
    ('Celular e internet',             8),
    ('Obligaciones y transferencias', 13)
  ) as v(nombre, grupo_id)
 where not exists (
   select 1 from public.categorias c
    where c.usuario_id is null
      and c.nombre = v.nombre
 );

-- 2.4 Categorías de INGRESO por defecto (Salario, Trabajo independiente,
--     Otros ingresos) quedan con grupo_id NULL: no requiere acción, la columna
--     es NULL por defecto.

-- 2.5 Categorías creadas por usuarios: egresos sin grupo -> grupo 12
update public.categorias
   set grupo_id = 12
 where usuario_id is not null
   and tipo = 'egreso'
   and grupo_id is null;

-- 2.6 PRE-CHECK (ejecutar/comentar si el CHECK falla): lista los egresos sin grupo.
-- select id, usuario_id, nombre, tipo, es_predeterminada
--   from public.categorias
--  where tipo = 'egreso' and grupo_id is null
--  order by usuario_id nulls first, nombre;

-- 2.7 CHECK después de llenar los datos (idempotente vía pg_constraint)
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'categorias_grupo_requerido'
  ) then
    alter table public.categorias
      add constraint categorias_grupo_requerido
      check (tipo = 'ingreso' or grupo_id is not null);
  end if;
end $$;


-- ============================================================================
-- PASO 3 · Tabla de movimientos (public.transacciones)
-- ============================================================================
alter table public.transacciones
  add column if not exists descripcion         text     null;
alter table public.transacciones
  add column if not exists es_gasto_trabajo    boolean  not null default false;
alter table public.transacciones
  add column if not exists grupo_sugerido_id   smallint null
    references public.grupos_referencia(id);
alter table public.transacciones
  add column if not exists confianza_sugerencia numeric null;
alter table public.transacciones
  add column if not exists categoria_corregida  boolean  null;
alter table public.transacciones
  add column if not exists version_modelo       text     null;

-- NOTA: NO se agrega NOT NULL a descripcion (la obligatoriedad se valida en la app).
-- NOTA: NO se modifican las claves foráneas existentes de transacciones.

-- Rango 0..1 para confianza_sugerencia (idempotente)
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'transacciones_confianza_sugerencia_rango'
  ) then
    alter table public.transacciones
      add constraint transacciones_confianza_sugerencia_rango
      check (
        confianza_sugerencia is null
        or (confianza_sugerencia >= 0 and confianza_sugerencia <= 1)
      );
  end if;
end $$;


-- ============================================================================
-- PASO 4 · Tablas del motor
--   usuario_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE
--   id uuid PRIMARY KEY DEFAULT gen_random_uuid()  (excepto preferencias_recomendacion)
-- ============================================================================

-- a) linea_base_usuario
create table if not exists public.linea_base_usuario (
  id             uuid        primary key default gen_random_uuid(),
  usuario_id     uuid        not null references auth.users(id) on delete cascade,
  categoria_id   uuid        not null references public.categorias(id) on delete cascade,
  mediana        numeric,
  mad            numeric,
  n_semanas      int         not null default 0,
  actualizado_en timestamptz not null default now(),
  constraint linea_base_usuario_usuario_categoria_key unique (usuario_id, categoria_id)
);

-- b) hallazgos
create table if not exists public.hallazgos (
  id              uuid        primary key default gen_random_uuid(),
  usuario_id      uuid        not null references auth.users(id) on delete cascade,
  tipo            text        not null,
  datos           jsonb       not null,
  severidad       numeric,
  impacto         numeric,
  confianza       numeric,
  repeticion      numeric,
  peso_tipo_usado numeric,
  puntaje         numeric,
  creado_en       timestamptz not null default now(),
  constraint hallazgos_tipo_check check (
    tipo in ('sobregasto_categoria','gasto_anomalo','aporte_meta',
             'leccion_sugerida','logro','riesgo_fin_de_mes')
  )
);

-- c) recomendaciones
create table if not exists public.recomendaciones (
  id            uuid        primary key default gen_random_uuid(),
  usuario_id    uuid        not null references auth.users(id) on delete cascade,
  hallazgo_id   uuid        null references public.hallazgos(id) on delete set null,
  tipo          text        not null,
  texto         text        not null,
  origen_texto  text,
  prioridad     numeric,
  util          boolean     null,
  respondido_en timestamptz null,
  mostrada_en   timestamptz null,
  creado_en     timestamptz not null default now(),
  constraint recomendaciones_tipo_check check (
    tipo in ('sobregasto_categoria','gasto_anomalo','aporte_meta',
             'leccion_sugerida','logro','riesgo_fin_de_mes')
  ),
  constraint recomendaciones_origen_texto_check check (
    origen_texto in ('llm','plantilla')
  )
);

-- d) preferencias_recomendacion (bandido: excluye 'riesgo_fin_de_mes'; PK compuesta)
create table if not exists public.preferencias_recomendacion (
  usuario_id     uuid        not null references auth.users(id) on delete cascade,
  tipo           text        not null,
  alfa           numeric     not null default 1,
  beta           numeric     not null default 1,
  actualizado_en timestamptz not null default now(),
  primary key (usuario_id, tipo),
  constraint preferencias_recomendacion_tipo_check check (
    tipo in ('sobregasto_categoria','gasto_anomalo','aporte_meta',
             'leccion_sugerida','logro')
  )
);

-- e) mensajes_ia
create table if not exists public.mensajes_ia (
  id         uuid        primary key default gen_random_uuid(),
  usuario_id uuid        not null references auth.users(id) on delete cascade,
  rol        text        not null,
  contenido  text        not null,
  intencion  text        null,
  creado_en  timestamptz not null default now(),
  constraint mensajes_ia_rol_check check (rol in ('usuario','asistente'))
);

-- Índices
create index if not exists linea_base_usuario_usuario_idx
  on public.linea_base_usuario (usuario_id);
create index if not exists hallazgos_usuario_idx
  on public.hallazgos (usuario_id);
create index if not exists hallazgos_usuario_creado_idx
  on public.hallazgos (usuario_id, creado_en);
create index if not exists recomendaciones_usuario_idx
  on public.recomendaciones (usuario_id);
create index if not exists recomendaciones_usuario_creado_idx
  on public.recomendaciones (usuario_id, creado_en);
create index if not exists mensajes_ia_usuario_idx
  on public.mensajes_ia (usuario_id);
create index if not exists mensajes_ia_usuario_creado_idx
  on public.mensajes_ia (usuario_id, creado_en);


-- ============================================================================
-- PASO 5 · RLS en las tablas del motor
-- ============================================================================
alter table public.linea_base_usuario         enable row level security;
alter table public.hallazgos                  enable row level security;
alter table public.recomendaciones            enable row level security;
alter table public.preferencias_recomendacion enable row level security;
alter table public.mensajes_ia                enable row level security;

-- SELECT solo de filas propias (todas las tablas)
drop policy if exists linea_base_usuario_select_propias on public.linea_base_usuario;
create policy linea_base_usuario_select_propias
  on public.linea_base_usuario for select to authenticated
  using (auth.uid() = usuario_id);

drop policy if exists hallazgos_select_propias on public.hallazgos;
create policy hallazgos_select_propias
  on public.hallazgos for select to authenticated
  using (auth.uid() = usuario_id);

drop policy if exists recomendaciones_select_propias on public.recomendaciones;
create policy recomendaciones_select_propias
  on public.recomendaciones for select to authenticated
  using (auth.uid() = usuario_id);

drop policy if exists preferencias_recomendacion_select_propias on public.preferencias_recomendacion;
create policy preferencias_recomendacion_select_propias
  on public.preferencias_recomendacion for select to authenticated
  using (auth.uid() = usuario_id);

drop policy if exists mensajes_ia_select_propias on public.mensajes_ia;
create policy mensajes_ia_select_propias
  on public.mensajes_ia for select to authenticated
  using (auth.uid() = usuario_id);

-- mensajes_ia: INSERT de filas propias
drop policy if exists mensajes_ia_insert_propias on public.mensajes_ia;
create policy mensajes_ia_insert_propias
  on public.mensajes_ia for insert to authenticated
  with check (auth.uid() = usuario_id);

-- recomendaciones: UPDATE de filas propias (util, respondido_en, mostrada_en)
drop policy if exists recomendaciones_update_propias on public.recomendaciones;
create policy recomendaciones_update_propias
  on public.recomendaciones for update to authenticated
  using (auth.uid() = usuario_id)
  with check (auth.uid() = usuario_id);

-- linea_base_usuario, hallazgos, preferencias_recomendacion:
-- sin políticas de escritura => solo el service_role (Edge Function) puede escribir.

commit;


-- ============================================================================
-- PASO 6 · Consultas de verificación (ejecutar aparte, tras aplicar la migración)
-- ============================================================================
-- select count(*) from public.grupos_referencia;                                          -- esperado 13
-- select count(*) from public.categorias where usuario_id is null and tipo = 'egreso';    -- esperado 14
-- select count(*) from public.categorias where usuario_id is null and tipo = 'egreso'
--    and grupo_id is null;                                                                -- esperado 0
-- select count(*) from public.categorias where tipo = 'egreso' and grupo_id is null;      -- esperado 0
-- select id, nombre, grupo_id from public.categorias
--    where usuario_id is null and tipo = 'egreso' order by grupo_id;
