-- History Source names must be the Anima the player already knows.
-- attempt_synthesis used to read generations.suggested_name and fall back to
-- the literal 'Anima' when that row was missing. Capture v41+ can mint a
-- nickname without leaving suggested_name, and some ready Anima have no
-- generation row at all (Playtron). Nickname is the player-facing label.

create or replace function public.synthesis_source_display_name(p_anima_id uuid)
returns text
language sql
stable
set search_path = ''
as $$
  select left(coalesce(
    nullif(btrim(a.nickname), ''),
    nullif(initcap(replace(a.species_key, '_', ' ')), ''),
    'Anima'
  ), 48)
  from public.animas a
  where a.id = p_anima_id;
$$;

revoke all on function public.synthesis_source_display_name(uuid)
  from public, anon, authenticated;
grant execute on function public.synthesis_source_display_name(uuid)
  to service_role;

create or replace function public.fill_synthesis_snapshot_names()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text;
begin
  if new.source_a_snapshot is not null
     and jsonb_typeof(new.source_a_snapshot) = 'object'
     and coalesce(new.source_a_snapshot->>'name', '') in ('', 'Anima')
     and coalesce(new.source_a_snapshot->>'id', '') <> '' then
    v_name := public.synthesis_source_display_name(
      (new.source_a_snapshot->>'id')::uuid
    );
    if v_name is not null then
      new.source_a_snapshot := new.source_a_snapshot
        || jsonb_build_object('name', v_name);
    end if;
  end if;
  if new.source_b_snapshot is not null
     and jsonb_typeof(new.source_b_snapshot) = 'object'
     and coalesce(new.source_b_snapshot->>'name', '') in ('', 'Anima')
     and coalesce(new.source_b_snapshot->>'id', '') <> '' then
    v_name := public.synthesis_source_display_name(
      (new.source_b_snapshot->>'id')::uuid
    );
    if v_name is not null then
      new.source_b_snapshot := new.source_b_snapshot
        || jsonb_build_object('name', v_name);
    end if;
  end if;
  return new;
end;
$$;

revoke all on function public.fill_synthesis_snapshot_names()
  from public, anon, authenticated;
grant execute on function public.fill_synthesis_snapshot_names()
  to service_role;

drop trigger if exists fill_synthesis_snapshot_names on public.anima_synthesis_slots;
create trigger fill_synthesis_snapshot_names
before insert or update of source_a_snapshot, source_b_snapshot
on public.anima_synthesis_slots
for each row
execute function public.fill_synthesis_snapshot_names();

update public.anima_synthesis_slots
   set source_a_snapshot = source_a_snapshot,
       source_b_snapshot = source_b_snapshot
 where coalesce(source_a_snapshot->>'name', '') in ('', 'Anima')
    or coalesce(source_b_snapshot->>'name', '') in ('', 'Anima');

do $backfill$
declare
  r record;
  v_history jsonb;
  v_name text;
begin
  for r in
    select id, synthesis_history
      from public.animas
     where synthesis_history is not null
       and jsonb_typeof(synthesis_history) = 'object'
       and (
         coalesce(synthesis_history #>> '{source_a,name}', '') in ('', 'Anima')
         or coalesce(synthesis_history #>> '{source_b,name}', '') in ('', 'Anima')
       )
  loop
    v_history := r.synthesis_history;
    if coalesce(v_history #>> '{source_a,name}', '') in ('', 'Anima')
       and coalesce(v_history #>> '{source_a,id}', '') <> '' then
      v_name := public.synthesis_source_display_name(
        (v_history #>> '{source_a,id}')::uuid
      );
      if v_name is not null then
        v_history := jsonb_set(v_history, '{source_a,name}', to_jsonb(v_name), true);
      end if;
    end if;
    if coalesce(v_history #>> '{source_b,name}', '') in ('', 'Anima')
       and coalesce(v_history #>> '{source_b,id}', '') <> '' then
      v_name := public.synthesis_source_display_name(
        (v_history #>> '{source_b,id}')::uuid
      );
      if v_name is not null then
        v_history := jsonb_set(v_history, '{source_b,name}', to_jsonb(v_name), true);
      end if;
    end if;
    update public.animas
       set synthesis_history = v_history
     where id = r.id;
  end loop;
end;
$backfill$;
