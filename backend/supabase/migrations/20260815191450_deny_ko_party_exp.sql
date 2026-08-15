-- KO members get 0 EXP. Active living +N, living bench +M.
create or replace function public.party_member_reward_exp(
  p_member jsonb,
  p_active integer,
  p_bench integer
) returns integer
language sql
immutable
set search_path = ''
as $$
  select case
    when coalesce((p_member->>'hp')::integer, 0) <= 0 then 0
    when coalesce((p_member->>'participated')::boolean, false) then greatest(0, p_active)
    else greatest(0, p_bench)
  end;
$$;

revoke all on function public.party_member_reward_exp(jsonb, integer, integer)
  from public, anon, authenticated;
grant execute on function public.party_member_reward_exp(jsonb, integer, integer)
  to service_role;

