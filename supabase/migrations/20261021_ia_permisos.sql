-- Permisos para las tablas del módulo de IA (aplicado manualmente el 2026-10-21)
grant select on public.grupos_referencia to authenticated;
grant select on public.linea_base_usuario, public.hallazgos,
  public.preferencias_recomendacion to authenticated;
grant select, update on public.recomendaciones to authenticated;
grant select, insert on public.mensajes_ia to authenticated;
notify pgrst, 'reload schema';