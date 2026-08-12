-- Fungsi kuota. Dibangun SEBELUM endpoint yang membelanjakan uang, karena
-- urutan sebaliknya berarti ada periode dengan endpoint tanpa pagar.
--
-- Keempatnya SECURITY DEFINER, sebab mereka menulis ke profiles dan quota_ledger
-- yang client tidak boleh sentuh. Konsekuensinya harus ditangani: Postgres
-- memberi EXECUTE ke PUBLIC secara default, jadi tanpa revoke di bawah,
-- refund_generation menjadi endpoint publik dan siapa pun bisa mengembalikan
-- Core-nya sendiri sementara gambarnya tetap kita bayar. Hanya service_role
-- (Edge Function) yang boleh memanggil.

-- Pagar murah sebelum memanggil Vision (~$0.003). Tetap harus atomik: tanpa
-- lock, satu client rusak bisa memanggil Vision beribu kali, dan seribu
-- panggilan liar itu $3, bukan $0,30.
create or replace function public.claim_scan_charge(p_owner uuid) returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_left int;
begin
  select scan_charges into v_left from public.profiles where id = p_owner for update;
  if not found then raise exception 'NO_PROFILE'; end if;
  if v_left <= 0 then raise exception 'NO_SCAN_CHARGE'; end if;

  update public.profiles set scan_charges = scan_charges - 1
   where id = p_owner
  returning scan_charges into v_left;

  insert into public.quota_ledger (owner_id, currency, delta, reason)
  values (p_owner, 'scan_charges', -1, 'scan');

  return v_left;
end $$;

-- Dipakai saat gate Vision menolak foto: pemain tidak boleh kehilangan charge
-- karena memfoto wajah atau dinding.
create or replace function public.refund_scan_charge(p_owner uuid, p_reason text default 'refund')
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_before int;
  v_after  int;
begin
  select scan_charges into v_before from public.profiles where id = p_owner for update;
  if not found then raise exception 'NO_PROFILE'; end if;

  update public.profiles set scan_charges = least(scan_charges + 1, scan_charge_max)
   where id = p_owner
  returning scan_charges into v_after;

  -- Kalau saldonya sudah penuh, tidak ada yang dikembalikan dan ledger tidak
  -- boleh mengarang baris kredit yang tidak terjadi.
  if v_after > v_before then
    insert into public.quota_ledger (owner_id, currency, delta, reason)
    values (p_owner, 'scan_charges', v_after - v_before, p_reason);
  end if;

  return v_after;
end $$;

-- Debit Core dan pencatatan generation dalam satu transaksi. Kalau dipisah, dua
-- request paralel bisa lolos bersamaan dengan sisa Core 1 dan satu sheet ~$0.07
-- keluar tanpa dibayar.
create or replace function public.claim_generation(
  p_owner          uuid,
  p_key            text,
  p_kind           text,
  p_prompt_version text,
  p_model          text,
  p_cost           numeric default 0
) returns public.generations
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gen   public.generations;
  v_cores int;
begin
  -- Idempotency lebih dulu: request yang sama dua kali mengembalikan row yang
  -- sama alih-alih mendebit dua kali. Inilah yang membuat retry jaringan tidak
  -- pernah berarti double charge.
  select * into v_gen from public.generations
   where owner_id = p_owner and idempotency_key = p_key;
  if found then return v_gen; end if;

  select genesis_cores into v_cores from public.profiles where id = p_owner for update;
  if not found then raise exception 'NO_PROFILE'; end if;
  if v_cores <= 0 then raise exception 'NO_CORE'; end if;

  update public.profiles set genesis_cores = genesis_cores - 1 where id = p_owner;

  insert into public.generations
    (owner_id, idempotency_key, kind, prompt_version, model, cost_usd_estimate, status)
  values
    (p_owner, p_key, p_kind, p_prompt_version, p_model, p_cost, 'pending')
  returning * into v_gen;

  -- Ledger ditulis setelah generation ada supaya ref_id bisa diisi. Itu yang
  -- memungkinkan refund_generation membuktikan debitnya memang pernah terjadi,
  -- bukan menebak dari status.
  insert into public.quota_ledger (owner_id, currency, delta, reason, ref_id)
  values (p_owner, 'genesis_cores', -1, 'genesis', v_gen.id);

  return v_gen;
exception
  when unique_violation then
    -- Dua transaksi paralel dengan idempotency_key sama: yang kalah dibatalkan
    -- seluruhnya oleh handler ini (termasuk debitnya) lalu membaca row pemenang.
    -- Hasil akhirnya satu Core untuk satu key, bukan dua.
    select * into v_gen from public.generations
     where owner_id = p_owner and idempotency_key = p_key;
    return v_gen;
end $$;

-- Kembar dari claim_generation. Dipanggil saat Replicate gagal atau dibatalkan,
-- dan saat timeout keras.
create or replace function public.refund_generation(p_gen_id uuid, p_reason text)
returns public.generations
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gen     public.generations;
  v_debited bool;
begin
  select * into v_gen from public.generations where id = p_gen_id for update;
  if not found then raise exception 'GEN_NOT_FOUND'; end if;

  -- Generation yang sudah berhasil berarti art-nya sudah diberikan. Mengembalikan
  -- Core untuknya sama dengan memberi sheet gratis, jadi ini bug pemanggil yang
  -- harus terlihat, bukan ditelan.
  if v_gen.status = 'succeeded' then raise exception 'ALREADY_SUCCEEDED'; end if;

  -- Cache hit tidak pernah mendebit Core (pengecekan pustaka terjadi sebelum
  -- claim_generation), jadi tidak ada yang bisa dikembalikan untuknya.
  select exists (
    select 1 from public.quota_ledger
     where ref_id = p_gen_id and currency = 'genesis_cores' and delta < 0
  ) into v_debited;

  -- Refund ganda dicegah dua kali: pemeriksaan di sini, dan indeks unik partial
  -- quota_ledger_refund_sekali_idx yang menjaganya walau ada race.
  if v_debited and not exists (
    select 1 from public.quota_ledger where ref_id = p_gen_id and reason = 'refund'
  ) then
    update public.profiles set genesis_cores = genesis_cores + 1 where id = v_gen.owner_id;
    insert into public.quota_ledger (owner_id, currency, delta, reason, ref_id)
    values (v_gen.owner_id, 'genesis_cores', 1, 'refund', p_gen_id);
  end if;

  update public.generations
     set status      = 'failed',
         error       = coalesce(p_reason, error),
         finished_at = coalesce(finished_at, now())
   where id = p_gen_id
  returning * into v_gen;

  return v_gen;
end $$;

revoke all on function public.claim_scan_charge(uuid) from public, anon, authenticated;
revoke all on function public.refund_scan_charge(uuid, text) from public, anon, authenticated;
revoke all on function public.claim_generation(uuid, text, text, text, text, numeric)
  from public, anon, authenticated;
revoke all on function public.refund_generation(uuid, text) from public, anon, authenticated;

grant execute on function public.claim_scan_charge(uuid) to service_role;
grant execute on function public.refund_scan_charge(uuid, text) to service_role;
grant execute on function public.claim_generation(uuid, text, text, text, text, numeric) to service_role;
grant execute on function public.refund_generation(uuid, text) to service_role;
