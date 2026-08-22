create index battle_failures_owner_id_idx
  on public.battle_failures (owner_id);

create index battle_failures_session_id_idx
  on public.battle_failures (session_id)
  where session_id is not null;
