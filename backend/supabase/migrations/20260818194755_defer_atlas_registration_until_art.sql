-- Some service-only legacy paths create a ready Anima before it has private
-- Atlas-compatible art. Do not make those transactions fail; register the form
-- when both sheet_path and manifest are eventually present.

create or replace function public.atlas_register_anima_ready()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_entry public.gallery_entries;
begin
  if new.status <> 'ready' then return new; end if;
  if coalesce(new.sheet_path, '') = ''
     or new.manifest is null
     or jsonb_typeof(new.manifest) <> 'object' then
    return new;
  end if;
  if tg_op = 'UPDATE'
     and old.status is not distinct from new.status
     and old.stage is not distinct from new.stage
     and old.sheet_path is not distinct from new.sheet_path
     and old.manifest is not distinct from new.manifest then
    return new;
  end if;

  perform public.register_player_atlas_form(new.id, new.stage);

  if tg_op = 'UPDATE'
     and (old.stage is distinct from new.stage or old.sheet_path is distinct from new.sheet_path) then
    select * into v_entry
      from public.gallery_entries
     where anima_id = new.id;
    if found and v_entry.published then
      update public.atlas_forms
         set thumb_path = v_entry.thumb_path,
             moderation_status = v_entry.moderation_status,
             updated_at = now()
       where anima_id = new.id and stage = old.stage;
      update public.gallery_entries
         set stage = new.stage,
             moderation_status = 'pending',
             thumb_path = null,
             updated_at = now()
       where id = v_entry.id;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists anima_atlas_register_ready on public.animas;
create trigger anima_atlas_register_ready
after insert or update of status, stage, sheet_path, manifest on public.animas
for each row
execute function public.atlas_register_anima_ready();

revoke all on function public.atlas_register_anima_ready()
  from public, anon, authenticated;
grant execute on function public.atlas_register_anima_ready()
  to service_role;
