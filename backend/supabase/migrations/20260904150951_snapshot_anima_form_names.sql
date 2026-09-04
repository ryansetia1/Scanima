-- Evolution History is private and promises the name each form used at the
-- time it was archived. `generation_id` cannot provide that for legacy/manual
-- Animas (and a generated species name would lose player Rename history), so
-- snapshot the private nickname before the current form changes.
alter table public.anima_forms
  add column nickname_snapshot text;

alter table public.anima_forms
  add constraint anima_forms_nickname_snapshot_valid
  check (
    nickname_snapshot is null
    or char_length(nickname_snapshot) between 1 and 32
  );

create or replace function public.snapshot_anima_form_nickname()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if nullif(btrim(new.nickname_snapshot), '') is null then
    select nullif(btrim(anima.nickname), '')
      into new.nickname_snapshot
      from public.animas anima
     where anima.id = new.anima_id;
  else
    new.nickname_snapshot := btrim(new.nickname_snapshot);
  end if;
  return new;
end $$;

drop trigger if exists anima_form_snapshot_nickname on public.anima_forms;
create trigger anima_form_snapshot_nickname
before insert on public.anima_forms
for each row execute function public.snapshot_anima_form_nickname();

revoke all on function public.snapshot_anima_form_nickname()
  from public, anon, authenticated;
grant execute on function public.snapshot_anima_form_nickname() to service_role;

-- Recover generated names where the source generation still exists. Four
-- hand-authored repository fixtures predate create generations entirely; their
-- canonical Hatchling names are immutable and already documented in migrations.
with recovered(anima_id, stage, nickname_snapshot) as (
  select
    form.anima_id,
    form.stage,
    coalesce(
      nullif(btrim(generation.vision_result->>'suggested_name'), ''),
      case form.anima_id
        when 'a20bb2f0-e063-4b7c-8bab-bfaf261400b8'::uuid then 'Mugshots'
        when '99b04a1c-07be-4753-be04-ae68183817e6'::uuid then 'Playtron'
        when 'c80ddef5-533d-4f36-9f26-7f449981e996'::uuid then 'Veridian'
        when '2168d17e-440d-4ba3-9004-5104800c6722'::uuid then 'Sunhound'
        else null
      end
    )
  from public.anima_forms form
  left join public.generations generation on generation.id = form.generation_id
)
update public.anima_forms form
   set nickname_snapshot = recovered.nickname_snapshot
  from recovered
 where form.anima_id = recovered.anima_id
   and form.stage = recovered.stage
   and recovered.nickname_snapshot is not null;

-- Atlas names are public species names, never private nickname snapshots.
-- Repair only the four known legacy projections whose canonical names are
-- repository-authored; future Atlas registration keeps using generation data.
with canonical(anima_id, display_name) as (
  values
    ('a20bb2f0-e063-4b7c-8bab-bfaf261400b8'::uuid, 'Mugshots'::text),
    ('99b04a1c-07be-4753-be04-ae68183817e6'::uuid, 'Playtron'::text),
    ('c80ddef5-533d-4f36-9f26-7f449981e996'::uuid, 'Veridian'::text),
    ('2168d17e-440d-4ba3-9004-5104800c6722'::uuid, 'Sunhound'::text)
)
update public.atlas_forms form
   set display_name = canonical.display_name,
       updated_at = now()
  from canonical
 where form.anima_id = canonical.anima_id
   and form.stage = 1
   and form.display_name = 'Anima';
