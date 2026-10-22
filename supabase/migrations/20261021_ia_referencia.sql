begin;
alter table public.grupos_referencia
  add column if not exists proporcion_dane numeric,
  add column if not exists proporcion_encuesta numeric;

update public.grupos_referencia g set
  proporcion_dane = v.dane, proporcion_encuesta = v.enc, proporcion_referencia = v.ref
from (values
  (1,15.05,11.36,13.20),(2,1.70,3.03,2.36),(3,3.98,7.58,5.78),(4,33.12,11.49,22.31),
  (5,4.19,7.38,5.79),(6,1.71,6.26,3.98),(7,12.93,10.40,11.66),(8,4.33,9.17,6.75),
  (9,3.79,9.02,6.41),(10,4.41,6.29,5.35),(11,9.43,9.96,9.70),(12,5.36,8.05,6.70)
) as v(id,dane,enc,ref)
where g.id = v.id;
commit;

select id, nombre, proporcion_referencia from public.grupos_referencia order by id;