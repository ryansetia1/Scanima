create table public.battle_failures (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  session_id uuid references public.battle_sessions(id) on delete set null,
  operation text not null
    constraint battle_failures_operation_valid
      check (btrim(operation) <> '' and length(operation) <= 32),
  rules_version integer not null
    constraint battle_failures_rules_version_valid check (rules_version >= 0),
  error text not null
    constraint battle_failures_error_valid
      check (btrim(error) <> '' and length(error) <= 500),
  context jsonb not null default '{}'::jsonb
    constraint battle_failures_context_valid check (
      jsonb_typeof(context) = 'object'
      and context - array['turn_action', 'expected_turn', 'expected_version'] = '{}'::jsonb
      and length(context::text) <= 512
    ),
  created_at timestamptz not null default now()
);

create index battle_failures_created_at_idx
  on public.battle_failures (created_at desc);

alter table public.battle_failures enable row level security;

revoke all on public.battle_failures from public, anon, authenticated;
grant all on public.battle_failures to service_role;
