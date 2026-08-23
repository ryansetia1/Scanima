-- Atlas Moderation Admin v2 schema. Gated behind feature_atlas_moderation_v2
-- (inserted false below); see docs/designs/2026-08-23-atlas-moderation-admin.md.
-- Every new table follows the existing house pattern: RLS enabled, zero
-- player policies, grants only to service_role.

-- 1. Structured, versioned final outcome on the existing per-art-hash cache.
alter table public.gallery_moderations
  add column if not exists category text,
  add column if not exists confidence text,
  add column if not exists evidence jsonb not null default '{}'::jsonb,
  add column if not exists model text,
  add column if not exists policy_version text,
  add column if not exists pass_count smallint not null default 1;

alter table public.gallery_moderations
  add constraint gallery_moderations_category_valid
    check (category is null or category in ('sexual', 'gore', 'hate', 'ip_character')),
  add constraint gallery_moderations_confidence_valid
    check (confidence is null or confidence in ('high', 'low')),
  add constraint gallery_moderations_pass_count_valid
    check (pass_count in (1, 2)),
  add constraint gallery_moderations_evidence_valid
    check (jsonb_typeof(evidence) = 'object' and length(evidence::text) <= 2000);

-- 2. Append-only log of every automated pass (both pass 1 and pass 2).
create table public.gallery_moderation_runs (
  id            bigserial primary key,
  art_hash      text not null,
  pass          smallint not null
    constraint gallery_moderation_runs_pass_valid check (pass in (1, 2)),
  decision      text not null
    constraint gallery_moderation_runs_decision_valid
      check (decision in ('approve', 'reject', 'uncertain')),
  category      text
    constraint gallery_moderation_runs_category_valid
      check (category is null or category in ('sexual', 'gore', 'hate', 'ip_character')),
  confidence    text
    constraint gallery_moderation_runs_confidence_valid
      check (confidence is null or confidence in ('high', 'low')),
  reason_code   text not null
    constraint gallery_moderation_runs_reason_present
      check (btrim(reason_code) <> '' and length(reason_code) <= 64),
  evidence      jsonb not null default '{}'::jsonb
    constraint gallery_moderation_runs_evidence_valid
      check (jsonb_typeof(evidence) = 'object' and length(evidence::text) <= 2000),
  model         text not null
    constraint gallery_moderation_runs_model_present check (btrim(model) <> ''),
  policy_version text not null
    constraint gallery_moderation_runs_policy_present check (btrim(policy_version) <> ''),
  created_at    timestamptz not null default now()
);

create index gallery_moderation_runs_art_hash_idx
  on public.gallery_moderation_runs (art_hash, created_at desc);
create index gallery_moderation_runs_created_idx
  on public.gallery_moderation_runs (created_at desc);

-- 3. One active manual case per (entry, art hash). Entry-scoped by design so
-- one owner's appeal or one report thread never silently resolves a
-- different owner's identical art hash (see design doc decision log).
create table public.moderation_cases (
  id                 uuid primary key default gen_random_uuid(),
  entry_id           uuid not null references public.gallery_entries(id) on delete cascade,
  art_hash           text not null
    constraint moderation_cases_art_hash_present check (btrim(art_hash) <> ''),
  source             text not null
    constraint moderation_cases_source_valid
      check (source in ('publish', 'report', 'appeal', 'manual')),
  status             text not null default 'open'
    constraint moderation_cases_status_valid
      check (status in ('open', 'approved', 'rejected', 'hidden')),
  category           text
    constraint moderation_cases_category_valid
      check (category is null or category in ('sexual', 'gore', 'hate', 'ip_character')),
  confidence         text
    constraint moderation_cases_confidence_valid
      check (confidence is null or confidence in ('high', 'low')),
  assigned_staff_id  uuid references auth.users(id) on delete set null,
  opened_reason_code text not null
    constraint moderation_cases_reason_present
      check (btrim(opened_reason_code) <> '' and length(opened_reason_code) <= 200),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  resolved_at        timestamptz
);

create unique index moderation_cases_one_open_idx
  on public.moderation_cases (entry_id, art_hash)
  where status = 'open';

create index moderation_cases_status_idx on public.moderation_cases (status, created_at);
create index moderation_cases_entry_idx on public.moderation_cases (entry_id);
create index moderation_cases_resolved_idx
  on public.moderation_cases (resolved_at) where resolved_at is not null;

-- 4. Append-only decision trail. One row per staff action on a case.
create table public.moderation_decisions (
  id             uuid primary key default gen_random_uuid(),
  case_id        uuid not null references public.moderation_cases(id) on delete cascade,
  staff_id       uuid not null references auth.users(id),
  action         text not null
    constraint moderation_decisions_action_valid
      check (action in ('approve', 'reject', 'hide', 'restore', 'escalate', 'assign')),
  reason_code    text not null
    constraint moderation_decisions_reason_present
      check (btrim(reason_code) <> '' and length(reason_code) <= 64),
  note           text
    constraint moderation_decisions_note_len check (note is null or length(note) <= 500),
  idempotency_key text not null
    constraint moderation_decisions_idem_present check (btrim(idempotency_key) <> ''),
  created_at     timestamptz not null default now(),
  constraint moderation_decisions_idem_unique unique (case_id, staff_id, idempotency_key)
);

create index moderation_decisions_case_idx on public.moderation_decisions (case_id, created_at);

-- 5. Staff identity and role, keyed to the verified Supabase auth user id —
-- never to email or user_metadata.
create table public.staff_accounts (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  role       text not null
    constraint staff_accounts_role_valid check (role in ('viewer', 'moderator', 'admin')),
  granted_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 6. Scoped, timed-or-permanent restrictions on a player's Atlas access.
-- Never touches currency, ownership, or existing publications.
create table public.profile_sanctions (
  id          uuid primary key default gen_random_uuid(),
  profile_id  uuid not null references public.profiles(id) on delete cascade,
  scope       text not null
    constraint profile_sanctions_scope_valid check (scope in ('atlas_publish', 'atlas_report')),
  reason_code text not null
    constraint profile_sanctions_reason_present
      check (btrim(reason_code) <> '' and length(reason_code) <= 64),
  note        text
    constraint profile_sanctions_note_len check (note is null or length(note) <= 500),
  expires_at  timestamptz,
  created_by  uuid not null references auth.users(id),
  created_at  timestamptz not null default now(),
  revoked_by  uuid references auth.users(id),
  revoked_at  timestamptz
);

create unique index profile_sanctions_one_active_idx
  on public.profile_sanctions (profile_id, scope)
  where revoked_at is null;

create index profile_sanctions_profile_idx on public.profile_sanctions (profile_id);

-- 7. Immutable audit log. service_role only gets select+insert — no update or
-- delete grant at all, so even a buggy caller cannot rewrite history.
create table public.admin_audit_log (
  id             uuid primary key default gen_random_uuid(),
  actor_id       uuid not null references auth.users(id),
  action         text not null
    constraint admin_audit_log_action_valid check (btrim(action) <> '' and length(action) <= 64),
  target_type    text not null
    constraint admin_audit_log_target_type_valid
      check (btrim(target_type) <> '' and length(target_type) <= 64),
  target_id      text not null
    constraint admin_audit_log_target_id_valid check (btrim(target_id) <> ''),
  before         jsonb,
  after          jsonb,
  idempotency_key text not null
    constraint admin_audit_log_idem_present check (btrim(idempotency_key) <> ''),
  created_at     timestamptz not null default now(),
  constraint admin_audit_log_idem_unique unique (actor_id, action, idempotency_key)
);

create index admin_audit_log_created_idx on public.admin_audit_log (created_at desc);
create index admin_audit_log_target_idx on public.admin_audit_log (target_type, target_id);

-- 8. Extend gallery_reports: categorized, bounded note, versioned per art
-- hash so a re-report after evolve/re-synthesis is possible again, and a
-- resolution state staff sets when a linked case closes.
alter table public.gallery_reports
  add column if not exists art_hash text,
  add column if not exists category text not null default 'other',
  add column if not exists note text,
  add column if not exists resolution_state text not null default 'pending';

update public.gallery_reports gr
  set art_hash = ge.art_hash
  from public.gallery_entries ge
  where gr.entry_id = ge.id and gr.art_hash is null;

alter table public.gallery_reports
  alter column art_hash set not null;

alter table public.gallery_reports
  add constraint gallery_reports_art_hash_present check (btrim(art_hash) <> ''),
  add constraint gallery_reports_category_valid
    check (category in ('character', 'sexual', 'gore', 'hate', 'other')),
  add constraint gallery_reports_note_len check (note is null or length(note) <= 280),
  add constraint gallery_reports_resolution_valid
    check (resolution_state in ('pending', 'upheld', 'dismissed'));

alter table public.gallery_reports drop constraint gallery_reports_unique_reporter;
alter table public.gallery_reports
  add constraint gallery_reports_unique_reporter unique (entry_id, reporter_id, art_hash);

create index gallery_reports_created_idx on public.gallery_reports (created_at desc);
create index gallery_reports_resolution_idx on public.gallery_reports (resolution_state);

-- RLS: default-deny on every new table, matching every other table in this
-- schema (RLS enabled, zero policies, revoked public/anon/authenticated).
alter table public.gallery_moderation_runs enable row level security;
alter table public.moderation_cases enable row level security;
alter table public.moderation_decisions enable row level security;
alter table public.staff_accounts enable row level security;
alter table public.profile_sanctions enable row level security;
alter table public.admin_audit_log enable row level security;

revoke all on public.gallery_moderation_runs from public, anon, authenticated;
revoke all on public.moderation_cases from public, anon, authenticated;
revoke all on public.moderation_decisions from public, anon, authenticated;
revoke all on public.staff_accounts from public, anon, authenticated;
revoke all on public.profile_sanctions from public, anon, authenticated;
revoke all on public.admin_audit_log from public, anon, authenticated;
revoke all on sequence public.gallery_moderation_runs_id_seq from public, anon, authenticated;

grant all on public.gallery_moderation_runs to service_role;
grant all on public.moderation_cases to service_role;
grant all on public.moderation_decisions to service_role;
grant all on public.staff_accounts to service_role;
grant all on public.profile_sanctions to service_role;
grant select, insert on public.admin_audit_log to service_role;
grant usage, select on sequence public.gallery_moderation_runs_id_seq to service_role;

-- Rollout flag. gallery/index.ts keeps the existing one-pass path while false.
insert into public.app_config (key, value)
values ('feature_atlas_moderation_v2', 'false'::jsonb)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- RPCs. All revoked from public/anon/authenticated, granted to service_role
-- only — callable exclusively from admin_moderation / gallery Edge Functions.
-- ---------------------------------------------------------------------------

-- Defense-in-depth role check. admin_moderation already verifies the JWT
-- subject's role before calling any of these; this closes the TOCTOU window
-- where a role could be revoked between that check and this call.
create or replace function public.moderation_require_role(p_staff_id uuid, p_min_role text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_rank int;
  v_min_rank int;
begin
  select role into v_role from public.staff_accounts where user_id = p_staff_id;
  if not found then
    raise exception 'STAFF_NOT_FOUND' using errcode = '28000';
  end if;
  v_rank := case v_role when 'admin' then 3 when 'moderator' then 2 else 1 end;
  v_min_rank := case p_min_role when 'admin' then 3 when 'moderator' then 2 else 1 end;
  if v_rank < v_min_rank then
    raise exception 'STAFF_ROLE_INSUFFICIENT' using errcode = '28000';
  end if;
end;
$$;

-- Idempotent case-open: returns the existing open case for (entry, art_hash)
-- if one exists, otherwise opens one. Shared by publish (pass2 uncertain),
-- report (quarantine threshold), and appeal flows.
create or replace function public.moderation_open_case_for_entry(
  p_entry_id uuid,
  p_art_hash text,
  p_source text,
  p_category text,
  p_confidence text,
  p_reason_code text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_case_id uuid;
begin
  select id into v_case_id from public.moderation_cases
    where entry_id = p_entry_id and art_hash = p_art_hash and status = 'open';
  if found then
    return v_case_id;
  end if;

  insert into public.moderation_cases
    (entry_id, art_hash, source, category, confidence, opened_reason_code)
  values (p_entry_id, p_art_hash, p_source, p_category, p_confidence, p_reason_code)
  returning id into v_case_id;
  return v_case_id;
exception when unique_violation then
  select id into v_case_id from public.moderation_cases
    where entry_id = p_entry_id and art_hash = p_art_hash and status = 'open';
  return v_case_id;
end;
$$;

-- Records one report, recounts eligible reports for the entry's CURRENT art
-- hash, and opens a review case when the quarantine threshold is crossed.
-- report-triggered hide stays immediate (existing player-facing behavior),
-- but it is no longer a dead end: it always creates a case staff can review
-- and restore.
create or replace function public.moderation_report_and_maybe_case(
  p_entry_id uuid,
  p_reporter_id uuid,
  p_category text,
  p_note text,
  p_auto_hide_threshold int
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_art_hash text;
  v_eligible_count int;
  v_case_id uuid;
  v_newly_hidden boolean := false;
  -- gallery_reports.category is the player-facing report reason (five
  -- values, including "character" and the default "other") and is stored
  -- verbatim below. moderation_cases.category is the narrower automated
  -- Vision vocabulary (no "other", "ip_character" instead of "character") —
  -- a report's category is mapped into that vocabulary only when opening a
  -- case, never the other way around, so a generic "other" report correctly
  -- opens a case with no automated category hint instead of violating the
  -- case table's CHECK constraint.
  v_case_category text := case p_category
    when 'character' then 'ip_character'
    when 'sexual' then 'sexual'
    when 'gore' then 'gore'
    when 'hate' then 'hate'
    else null
  end;
begin
  select art_hash into v_art_hash from public.gallery_entries where id = p_entry_id;
  if not found then
    raise exception 'ENTRY_NOT_FOUND' using errcode = '28000';
  end if;

  insert into public.gallery_reports (entry_id, reporter_id, art_hash, category, note)
  values (p_entry_id, p_reporter_id, v_art_hash, p_category, p_note)
  on conflict (entry_id, reporter_id, art_hash) do nothing;

  select count(*) into v_eligible_count
    from public.gallery_reports
    where entry_id = p_entry_id and art_hash = v_art_hash;

  update public.gallery_entries
    set report_count = v_eligible_count
    where id = p_entry_id;

  if v_eligible_count >= p_auto_hide_threshold then
    update public.gallery_entries
      set auto_hidden = true
      where id = p_entry_id and auto_hidden = false;
    if found then
      v_newly_hidden := true;
    end if;

    v_case_id := public.moderation_open_case_for_entry(
      p_entry_id, v_art_hash, 'report', v_case_category, null, 'report_quarantine_threshold'
    );
  end if;

  return jsonb_build_object(
    'report_count', v_eligible_count,
    'newly_hidden', v_newly_hidden,
    'case_id', v_case_id
  );
end;
$$;

-- Files one owner appeal on a rejected entry. At most one appeal per
-- (entry, art_hash) — re-evolving/re-synthesizing produces a new art_hash
-- and therefore a fresh appeal allowance.
create or replace function public.moderation_file_appeal(
  p_entry_id uuid,
  p_owner_id uuid,
  p_note text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entry record;
  v_prior_appeal_count int;
begin
  select * into v_entry from public.gallery_entries
    where id = p_entry_id and owner_id = p_owner_id;
  if not found then
    raise exception 'ENTRY_NOT_FOUND' using errcode = '28000';
  end if;
  if v_entry.moderation_status <> 'rejected' then
    raise exception 'ENTRY_NOT_REJECTED' using errcode = '22023';
  end if;

  select count(*) into v_prior_appeal_count
    from public.moderation_cases
    where entry_id = p_entry_id and art_hash = v_entry.art_hash and source = 'appeal';
  if v_prior_appeal_count >= 1 then
    raise exception 'APPEAL_ALREADY_USED' using errcode = '22023';
  end if;

  update public.gallery_entries set moderation_status = 'pending' where id = p_entry_id;

  return public.moderation_open_case_for_entry(
    p_entry_id, v_entry.art_hash, 'appeal', null, null,
    coalesce(nullif(btrim(p_note), ''), 'owner_appeal')
  );
end;
$$;

-- The core staff decision RPC: approve/reject/hide/restore/escalate/assign,
-- decision row and audit row in the same transaction, idempotent by
-- (actor, action, idempotency_key).
create or replace function public.moderation_decide_case(
  p_case_id uuid,
  p_staff_id uuid,
  p_action text,
  p_reason_code text,
  p_note text,
  p_idempotency_key text,
  p_thumb_path text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_case public.moderation_cases;
  v_entry public.gallery_entries;
  v_before jsonb;
  v_after jsonb;
  v_new_status text;
begin
  if p_action not in ('approve', 'reject', 'hide', 'restore', 'escalate', 'assign') then
    raise exception 'ACTION_INVALID' using errcode = '22023';
  end if;

  perform public.moderation_require_role(p_staff_id, 'moderator');

  select * into v_case from public.moderation_cases where id = p_case_id for update;
  if not found then
    raise exception 'CASE_NOT_FOUND' using errcode = '28000';
  end if;

  select * into v_entry from public.gallery_entries where id = v_case.entry_id for update;
  if not found then
    raise exception 'ENTRY_NOT_FOUND' using errcode = '28000';
  end if;

  -- Idempotency is checked BEFORE the status guard below. A retry with the
  -- same idempotency_key almost always arrives after the first attempt
  -- already moved the case out of 'open' — checking status first would
  -- surface a confusing CASE_ALREADY_RESOLVED for a request that actually
  -- succeeded, defeating the point of the key.
  if exists (
    select 1 from public.admin_audit_log
     where actor_id = p_staff_id and action = 'moderation_' || p_action
       and idempotency_key = p_idempotency_key
  ) then
    return jsonb_build_object('idempotent_replay', true, 'case_id', p_case_id);
  end if;

  if p_action <> 'assign' and v_case.status <> 'open' then
    raise exception 'CASE_ALREADY_RESOLVED' using errcode = '22023';
  end if;

  v_before := jsonb_build_object(
    'case_status', v_case.status,
    'moderation_status', v_entry.moderation_status,
    'published', v_entry.published,
    'auto_hidden', v_entry.auto_hidden
  );

  begin
    insert into public.admin_audit_log
      (actor_id, action, target_type, target_id, before, idempotency_key)
    values
      (p_staff_id, 'moderation_' || p_action, 'moderation_case', p_case_id::text, v_before, p_idempotency_key);
    -- Race-safety net for two truly concurrent identical requests that both
    -- passed the exists-check above before either committed; the normal
    -- idempotent path returns via that check, not via this catch.
    insert into public.moderation_decisions
      (case_id, staff_id, action, reason_code, note, idempotency_key)
    values
      (p_case_id, p_staff_id, p_action, p_reason_code, p_note, p_idempotency_key);
  exception when unique_violation then
    return jsonb_build_object('idempotent_replay', true, 'case_id', p_case_id);
  end;

  if p_action = 'assign' then
    update public.moderation_cases set assigned_staff_id = p_staff_id, updated_at = now()
      where id = p_case_id;
    v_after := v_before;
  else
    v_new_status := case p_action
      when 'approve' then 'approved'
      when 'reject' then 'rejected'
      when 'hide' then 'hidden'
      when 'restore' then 'approved'
      when 'escalate' then 'open'
    end;

    update public.moderation_cases
      set status = v_new_status,
          updated_at = now(),
          resolved_at = case when v_new_status = 'open' then null else now() end
      where id = p_case_id;

    if p_action = 'approve' then
      -- A case opened from a pass-2-uncertain publish attempt never went
      -- through gallery/index.ts's thumb crop+upload (it returns early into
      -- 'pending' before that step), so p_thumb_path is required whenever
      -- the entry doesn't already have one — otherwise this would publish an
      -- entry with no thumbnail. A restore-sourced approve already has a
      -- thumb_path from when it was first published, so p_thumb_path stays
      -- null there and coalesce keeps the existing one.
      if v_entry.thumb_path is null and p_thumb_path is null then
        raise exception 'THUMB_REQUIRED' using errcode = '22023';
      end if;
      update public.gallery_entries
        set moderation_status = 'approved', published = true, auto_hidden = false,
            thumb_path = coalesce(p_thumb_path, thumb_path)
        where id = v_case.entry_id;
    elsif p_action = 'reject' then
      update public.gallery_entries
        set moderation_status = 'rejected', published = false
        where id = v_case.entry_id;
    elsif p_action = 'hide' then
      update public.gallery_entries set auto_hidden = true where id = v_case.entry_id;
    elsif p_action = 'restore' then
      -- Same gap as approve: a source='publish' case from a pass-2-uncertain
      -- attempt never had a thumbnail generated. Restore can land on such a
      -- case too (staff choosing Restore instead of Approve), so it needs
      -- the same guard.
      if v_entry.thumb_path is null and p_thumb_path is null then
        raise exception 'THUMB_REQUIRED' using errcode = '22023';
      end if;
      update public.gallery_entries
        set auto_hidden = false, moderation_status = 'approved', published = true,
            thumb_path = coalesce(p_thumb_path, thumb_path)
        where id = v_case.entry_id;
    end if;
    -- escalate leaves gallery_entries untouched and the case open.

    if p_action in ('approve', 'restore') then
      update public.gallery_reports
        set resolution_state = 'dismissed'
        where entry_id = v_case.entry_id and art_hash = v_case.art_hash
          and resolution_state = 'pending';
    elsif p_action in ('reject', 'hide') then
      update public.gallery_reports
        set resolution_state = 'upheld'
        where entry_id = v_case.entry_id and art_hash = v_case.art_hash
          and resolution_state = 'pending';
    end if;

    select jsonb_build_object(
      'case_status', v_new_status,
      'moderation_status', ge.moderation_status,
      'published', ge.published,
      'auto_hidden', ge.auto_hidden
    ) into v_after
    from public.gallery_entries ge where ge.id = v_case.entry_id;
  end if;

  update public.admin_audit_log
    set after = v_after
    where actor_id = p_staff_id and action = 'moderation_' || p_action
      and idempotency_key = p_idempotency_key;

  return jsonb_build_object('ok', true, 'case_status', coalesce(v_new_status, v_case.status), 'after', v_after);
end;
$$;

-- Sets one active sanction per (profile, scope), revoking any prior active
-- one first. Never touches currency, ownership, or existing publications.
create or replace function public.moderation_set_sanction(
  p_profile_id uuid,
  p_staff_id uuid,
  p_scope text,
  p_reason_code text,
  p_note text,
  p_expires_at timestamptz,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sanction_id uuid;
begin
  if p_scope not in ('atlas_publish', 'atlas_report') then
    raise exception 'SCOPE_INVALID' using errcode = '22023';
  end if;

  perform public.moderation_require_role(p_staff_id, 'moderator');

  begin
    insert into public.admin_audit_log
      (actor_id, action, target_type, target_id, before, idempotency_key)
    values
      (p_staff_id, 'sanction_set', 'profile', p_profile_id::text,
       jsonb_build_object('scope', p_scope), p_idempotency_key);
  exception when unique_violation then
    select id into v_sanction_id from public.profile_sanctions
      where profile_id = p_profile_id and scope = p_scope and revoked_at is null;
    return v_sanction_id;
  end;

  update public.profile_sanctions
    set revoked_at = now(), revoked_by = p_staff_id
    where profile_id = p_profile_id and scope = p_scope and revoked_at is null;

  insert into public.profile_sanctions
    (profile_id, scope, reason_code, note, expires_at, created_by)
  values
    (p_profile_id, p_scope, p_reason_code, p_note, p_expires_at, p_staff_id)
  returning id into v_sanction_id;

  update public.admin_audit_log
    set after = jsonb_build_object('sanction_id', v_sanction_id, 'expires_at', p_expires_at)
    where actor_id = p_staff_id and action = 'sanction_set' and idempotency_key = p_idempotency_key;

  return v_sanction_id;
end;
$$;

create or replace function public.moderation_revoke_sanction(
  p_sanction_id uuid,
  p_staff_id uuid,
  p_reason_code text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sanction public.profile_sanctions;
begin
  perform public.moderation_require_role(p_staff_id, 'moderator');

  select * into v_sanction from public.profile_sanctions where id = p_sanction_id for update;
  if not found then
    raise exception 'SANCTION_NOT_FOUND' using errcode = '28000';
  end if;

  -- Checked before the "already revoked" guard below: a retry with the same
  -- idempotency_key arrives after the first attempt already revoked it, so
  -- checking revoked_at first would surface a confusing
  -- SANCTION_ALREADY_REVOKED for a request that actually succeeded.
  if exists (
    select 1 from public.admin_audit_log
     where actor_id = p_staff_id and action = 'sanction_revoke'
       and idempotency_key = p_idempotency_key
  ) then
    return jsonb_build_object('idempotent_replay', true, 'sanction_id', p_sanction_id);
  end if;

  if v_sanction.revoked_at is not null then
    raise exception 'SANCTION_ALREADY_REVOKED' using errcode = '22023';
  end if;

  begin
    insert into public.admin_audit_log
      (actor_id, action, target_type, target_id, before, idempotency_key)
    values
      (p_staff_id, 'sanction_revoke', 'profile_sanction', p_sanction_id::text,
       jsonb_build_object('reason_code', v_sanction.reason_code), p_idempotency_key);
  exception when unique_violation then
    return jsonb_build_object('idempotent_replay', true, 'sanction_id', p_sanction_id);
  end;

  update public.profile_sanctions
    set revoked_at = now(), revoked_by = p_staff_id
    where id = p_sanction_id;

  update public.admin_audit_log
    set after = jsonb_build_object('revoked', true, 'revoke_reason_code', p_reason_code)
    where actor_id = p_staff_id and action = 'sanction_revoke' and idempotency_key = p_idempotency_key;

  return jsonb_build_object('ok', true);
end;
$$;

-- Admin-only staff management. p_role = 'revoked' deletes the staff row.
-- An admin can never revoke their own access through this path.
create or replace function public.admin_set_staff_role(
  p_target_user_id uuid,
  p_role text,
  p_staff_id uuid,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_before jsonb;
begin
  if p_role not in ('viewer', 'moderator', 'admin', 'revoked') then
    raise exception 'ROLE_INVALID' using errcode = '22023';
  end if;

  perform public.moderation_require_role(p_staff_id, 'admin');

  -- Blocks both full revocation and a self-demotion away from admin — either
  -- one can strand the account with no remaining admin able to restore it,
  -- since staff_set_role and staff_list both require role = admin.
  if p_target_user_id = p_staff_id and p_role <> 'admin' then
    raise exception 'CANNOT_REVOKE_SELF' using errcode = '22023';
  end if;

  select jsonb_build_object('role', role) into v_before
    from public.staff_accounts where user_id = p_target_user_id;

  begin
    insert into public.admin_audit_log
      (actor_id, action, target_type, target_id, before, idempotency_key)
    values
      (p_staff_id, 'staff_role_set', 'staff_account', p_target_user_id::text,
       coalesce(v_before, 'null'::jsonb), p_idempotency_key);
  exception when unique_violation then
    return jsonb_build_object('idempotent_replay', true);
  end;

  if p_role = 'revoked' then
    delete from public.staff_accounts where user_id = p_target_user_id;
  else
    insert into public.staff_accounts (user_id, role, granted_by)
    values (p_target_user_id, p_role, p_staff_id)
    on conflict (user_id) do update
      set role = excluded.role, granted_by = excluded.granted_by, updated_at = now();
  end if;

  update public.admin_audit_log
    set after = jsonb_build_object('role', p_role)
    where actor_id = p_staff_id and action = 'staff_role_set' and idempotency_key = p_idempotency_key;

  return jsonb_build_object('ok', true, 'role', p_role);
end;
$$;

revoke all on function public.moderation_require_role(uuid, text) from public, anon, authenticated;
revoke all on function public.moderation_open_case_for_entry(uuid, text, text, text, text, text) from public, anon, authenticated;
revoke all on function public.moderation_report_and_maybe_case(uuid, uuid, text, text, int) from public, anon, authenticated;
revoke all on function public.moderation_file_appeal(uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.moderation_decide_case(uuid, uuid, text, text, text, text, text) from public, anon, authenticated;
revoke all on function public.moderation_set_sanction(uuid, uuid, text, text, text, timestamptz, text) from public, anon, authenticated;
revoke all on function public.moderation_revoke_sanction(uuid, uuid, text, text) from public, anon, authenticated;
-- Read-only aggregate for the admin analytics page. STABLE (no writes), one
-- query instead of many chained round trips from the edge function.
create or replace function public.moderation_analytics_summary(p_since timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_open_cases int;
  v_oldest_open_age_seconds numeric;
  v_decisions_by_action jsonb;
  v_pass_outcomes jsonb;
  v_manual_outcomes jsonb;
  v_appeal_total int;
  v_appeal_approved int;
  v_report_states jsonb;
  v_active_sanctions int;
  v_avg_decision_seconds numeric;
begin
  select count(*) into v_open_cases from public.moderation_cases where status = 'open';

  select extract(epoch from (now() - min(created_at))) into v_oldest_open_age_seconds
    from public.moderation_cases where status = 'open';

  select coalesce(jsonb_object_agg(action, cnt), '{}'::jsonb) into v_decisions_by_action
    from (
      select action, count(*) as cnt from public.moderation_decisions
        where created_at >= p_since group by action
    ) t;

  select coalesce(jsonb_object_agg(key, cnt), '{}'::jsonb) into v_pass_outcomes
    from (
      select pass::text || '_' || decision as key, count(*) as cnt
        from public.gallery_moderation_runs
        where created_at >= p_since
        group by pass, decision
    ) t;

  select coalesce(jsonb_object_agg(status, cnt), '{}'::jsonb) into v_manual_outcomes
    from (
      select status, count(*) as cnt from public.moderation_cases
        where resolved_at >= p_since group by status
    ) t;

  select count(*) into v_appeal_total
    from public.moderation_cases where source = 'appeal' and resolved_at >= p_since;
  select count(*) into v_appeal_approved
    from public.moderation_cases
    where source = 'appeal' and status = 'approved' and resolved_at >= p_since;

  select coalesce(jsonb_object_agg(resolution_state, cnt), '{}'::jsonb) into v_report_states
    from (
      select resolution_state, count(*) as cnt from public.gallery_reports
        where created_at >= p_since group by resolution_state
    ) t;

  select count(*) into v_active_sanctions
    from public.profile_sanctions
    where revoked_at is null and (expires_at is null or expires_at > now());

  select avg(extract(epoch from (resolved_at - created_at))) into v_avg_decision_seconds
    from public.moderation_cases
    where resolved_at is not null and resolved_at >= p_since;

  return jsonb_build_object(
    'since', p_since,
    'open_cases', v_open_cases,
    'oldest_open_case_age_seconds', coalesce(v_oldest_open_age_seconds, 0),
    'decisions_by_action', v_decisions_by_action,
    'pass_outcomes', v_pass_outcomes,
    'manual_outcomes', v_manual_outcomes,
    'appeal_total', v_appeal_total,
    'appeal_approved', v_appeal_approved,
    'report_states', v_report_states,
    'active_sanctions', v_active_sanctions,
    'avg_time_to_decision_seconds', coalesce(v_avg_decision_seconds, 0)
  );
end;
$$;

revoke all on function public.admin_set_staff_role(uuid, text, uuid, text) from public, anon, authenticated;
revoke all on function public.moderation_analytics_summary(timestamptz) from public, anon, authenticated;

grant execute on function public.moderation_require_role(uuid, text) to service_role;
grant execute on function public.moderation_open_case_for_entry(uuid, text, text, text, text, text) to service_role;
grant execute on function public.moderation_report_and_maybe_case(uuid, uuid, text, text, int) to service_role;
grant execute on function public.moderation_file_appeal(uuid, uuid, text) to service_role;
grant execute on function public.moderation_decide_case(uuid, uuid, text, text, text, text, text) to service_role;
grant execute on function public.moderation_set_sanction(uuid, uuid, text, text, text, timestamptz, text) to service_role;
grant execute on function public.moderation_revoke_sanction(uuid, uuid, text, text) to service_role;
grant execute on function public.admin_set_staff_role(uuid, text, uuid, text) to service_role;
grant execute on function public.moderation_analytics_summary(timestamptz) to service_role;
