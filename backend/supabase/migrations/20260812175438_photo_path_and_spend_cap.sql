-- Foto mentah wajib dihapus setelah post-processing (aturan tidak bisa
-- dinegosiasikan #4), dan yang menghapusnya adalah webhook. Ia butuh tahu path-nya
-- tanpa menebak dari konvensi nama yang dipilih client.
alter table generations add column photo_path text;

-- Sakelar biaya harian dipindahkan KE DALAM claim_generation.
--
-- Membacanya di Edge Function lalu memutuskan di sana meninggalkan celah antara
-- pembacaan dan debit, dan yang lolos di celah itu bukan satu baris data
-- melainkan satu panggilan generation ~$0.07. Di sini, pemeriksaannya memakai
-- lock baris profil yang sudah dipegang, jadi keputusannya dan debitnya satu
-- transaksi. Cap-nya global, karena tagihannya milik kita, bukan milik pemain.
--
-- Cache hit tidak lewat sini (biaya gambarnya nol), jadi ia tidak pernah ikut
-- terkena cap.
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
  v_cap   numeric;
  v_spent numeric;
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

  select (value #>> '{}')::numeric into v_cap
    from public.app_config where key = 'daily_spend_cap_usd';
  if v_cap is not null then
    select coalesce(sum(cost_usd_estimate), 0) into v_spent
      from public.generations
     where created_at >= date_trunc('day', now()) and cost_usd_estimate > 0;
    -- Gagal keras, bukan diam-diam melanjutkan. Pemain melihat "coba lagi besok";
    -- yang tidak boleh terjadi adalah tagihan menembus batas tanpa ada yang tahu.
    if v_spent + p_cost > v_cap then raise exception 'SPEND_CAP'; end if;
  end if;

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
