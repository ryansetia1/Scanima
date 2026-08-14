-- Guest yang sudah memakai satu Scan harus ditolak sebelum Vision berbayar.
-- Guard final tetap hidup di record_cache_hit()/claim_genesis() agar request
-- pertama yang paralel tidak bisa membuat dua Anima; guard murah ini menutup
-- replay berulang setelah slot sudah terpakai.
create or replace function public.claim_scan_charge(p_owner uuid) returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_left int;
  v_guest_used timestamptz;
  v_is_anonymous boolean;
begin
  select p.scan_charges, p.guest_scan_used_at, coalesce(u.is_anonymous, false)
    into v_left, v_guest_used, v_is_anonymous
    from public.profiles p
    join auth.users u on u.id = p.id
   where p.id = p_owner
   for update of p;
  if not found then raise exception 'NO_PROFILE'; end if;
  if v_is_anonymous and v_guest_used is not null then
    raise exception 'GUEST_SCAN_USED';
  end if;
  if v_left <= 0 then raise exception 'NO_SCAN_CHARGE'; end if;

  update public.profiles set scan_charges = scan_charges - 1
   where id = p_owner
  returning scan_charges into v_left;

  insert into public.quota_ledger (owner_id, currency, delta, reason)
  values (p_owner, 'scan_charges', -1, 'scan');

  return v_left;
end $$;

revoke all on function public.claim_scan_charge(uuid)
  from public, anon, authenticated;
grant execute on function public.claim_scan_charge(uuid) to service_role;
