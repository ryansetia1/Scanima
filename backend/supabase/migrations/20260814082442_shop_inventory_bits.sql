-- Shop + inventory + Bits sebagai uang toko. Starter 50 hanya untuk akun baru.
-- Reward Battle: progression 3 kemenangan terpisah dari cap nominal 100 Bits.

insert into public.app_config (key, value)
values
  ('bits_starter', '50'::jsonb),
  ('battle_bits_per_day', '100'::jsonb)
on conflict (key) do update
set value = excluded.value,
    updated_at = now();

alter table public.profiles alter column bits set default 50;

create or replace function public.handle_new_user() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile uuid;
begin
  insert into public.profiles (id)
  values (new.id)
  on conflict (id) do nothing
  returning id into v_profile;

  if v_profile is not null then
    insert into public.quota_ledger (owner_id, currency, delta, reason)
    values (v_profile, 'bits', 50, 'care_starter');
  end if;
  return new;
end $$;

revoke all on function public.handle_new_user() from public, anon, authenticated;

create table public.catalog_items (
  id            text primary key,
  kind          text not null,
  use_type      text not null,
  name_key      text not null,
  price         integer not null,
  effect        text not null,
  effect_value  numeric not null,
  sprite_sheet  text not null,
  sprite_index  smallint not null,
  active        boolean not null default true,
  constraint catalog_items_kind_valid check (kind in ('food', 'item')),
  constraint catalog_items_use_valid check (use_type in ('food', 'energy', 'battle')),
  constraint catalog_items_price_valid check (price > 0),
  constraint catalog_items_effect_valid check (effect_value > 0),
  constraint catalog_items_sheet_valid check (sprite_sheet in ('food', 'item')),
  constraint catalog_items_index_valid check (sprite_index between 0 and 8)
);

insert into public.catalog_items
  (id, kind, use_type, name_key, price, effect, effect_value, sprite_sheet, sprite_index)
values
  ('byte_berry', 'food', 'food', 'CATALOG_BYTE_BERRY', 2, 'hunger', 10, 'food', 0),
  ('moon_biscuit', 'food', 'food', 'CATALOG_MOON_BISCUIT', 3, 'hunger', 15, 'food', 1),
  ('moss_wrap', 'food', 'food', 'CATALOG_MOSS_WRAP', 4, 'hunger', 20, 'food', 2),
  ('spark_skewer', 'food', 'food', 'CATALOG_SPARK_SKEWER', 5, 'hunger', 25, 'food', 3),
  ('prism_jelly', 'food', 'food', 'CATALOG_PRISM_JELLY', 7, 'hunger', 35, 'food', 4),
  ('ember_noodles', 'food', 'food', 'CATALOG_EMBER_NOODLES', 9, 'hunger', 45, 'food', 5),
  ('cloud_curry', 'food', 'food', 'CATALOG_CLOUD_CURRY', 12, 'hunger', 60, 'food', 6),
  ('star_bento', 'food', 'food', 'CATALOG_STAR_BENTO', 15, 'hunger', 75, 'food', 7),
  ('nova_feast', 'food', 'food', 'CATALOG_NOVA_FEAST', 20, 'hunger', 100, 'food', 8),
  ('pulse_cell', 'item', 'energy', 'CATALOG_PULSE_CELL', 8, 'energy', 20, 'item', 0),
  ('reactor_pack', 'item', 'energy', 'CATALOG_REACTOR_PACK', 18, 'energy', 50, 'item', 1),
  ('vital_patch', 'item', 'battle', 'CATALOG_VITAL_PATCH', 14, 'heal_hp_pct', 30, 'item', 2),
  ('power_chip', 'item', 'battle', 'CATALOG_POWER_CHIP', 12, 'buff_atk', 35, 'item', 3),
  ('surge_lens', 'item', 'battle', 'CATALOG_SURGE_LENS', 12, 'buff_special', 35, 'item', 4),
  ('aegis_plate', 'item', 'battle', 'CATALOG_AEGIS_PLATE', 14, 'buff_guard', 25, 'item', 5),
  ('tempo_coil', 'item', 'battle', 'CATALOG_TEMPO_COIL', 10, 'buff_spd', 40, 'item', 6),
  ('pp_capsule', 'item', 'battle', 'CATALOG_PP_CAPSULE', 14, 'pp_boost', 2, 'item', 7),
  ('phase_shield', 'item', 'battle', 'CATALOG_PHASE_SHIELD', 10, 'phase_shield', 80, 'item', 8);

create table public.player_inventory (
  owner_id   uuid not null references public.profiles(id) on delete cascade,
  item_id    text not null references public.catalog_items(id),
  quantity   integer not null,
  updated_at timestamptz not null default now(),
  primary key (owner_id, item_id),
  constraint player_inventory_qty_valid check (quantity >= 0 and quantity <= 999)
);

create table public.shop_purchases (
  id               uuid primary key default gen_random_uuid(),
  owner_id         uuid not null references public.profiles(id) on delete cascade,
  item_id          text not null references public.catalog_items(id),
  quantity         integer not null default 1,
  price            integer not null,
  idempotency_key  text not null,
  created_at       timestamptz not null default now(),
  constraint shop_purchases_qty_valid check (quantity = 1),
  constraint shop_purchases_price_valid check (price > 0),
  constraint shop_purchases_key_valid check (length(idempotency_key) between 1 and 128),
  constraint shop_purchases_owner_key_unique unique (owner_id, idempotency_key)
);

alter table public.care_events
  add column if not exists catalog_item_id text references public.catalog_items(id);
alter table public.care_events drop constraint if exists care_events_action_valid;
alter table public.care_events add constraint care_events_action_valid
  check (action in ('feed', 'clean', 'sleep', 'wake', 'play', 'summon', 'use_item'));

alter table public.battle_sessions
  add column if not exists item_used_id text references public.catalog_items(id),
  add column if not exists reward_tier text not null default 'even',
  add column if not exists reward_roll smallint not null default 0,
  add column if not exists reward_bits integer not null default 8;
alter table public.battle_sessions drop constraint if exists battle_sessions_reward_tier_valid;
alter table public.battle_sessions add constraint battle_sessions_reward_tier_valid
  check (reward_tier in ('favorable', 'even', 'tough', 'formidable'));
alter table public.battle_sessions drop constraint if exists battle_sessions_reward_roll_valid;
alter table public.battle_sessions add constraint battle_sessions_reward_roll_valid
  check (reward_roll between -1 and 1);
alter table public.battle_sessions drop constraint if exists battle_sessions_reward_bits_valid;
alter table public.battle_sessions add constraint battle_sessions_reward_bits_valid
  check (reward_bits between 5 and 16);

alter table public.battle_turns
  add column if not exists catalog_item_id text references public.catalog_items(id);
alter table public.battle_turns drop constraint if exists battle_turns_action_valid;
alter table public.battle_turns add constraint battle_turns_action_valid
  check (action in ('strike', 'surge', 'guard', 'item'));

create unique index if not exists quota_ledger_battle_train_session_unique
  on public.quota_ledger (ref_id)
  where reason = 'battle_train';

alter table public.catalog_items enable row level security;
alter table public.player_inventory enable row level security;
alter table public.shop_purchases enable row level security;

revoke all on public.catalog_items from anon, authenticated;
revoke all on public.player_inventory from anon, authenticated;
revoke all on public.shop_purchases from anon, authenticated;
grant select on public.catalog_items to authenticated;
grant select on public.player_inventory to authenticated;
grant all on public.catalog_items, public.player_inventory, public.shop_purchases to service_role;

create policy catalog_items_read on public.catalog_items
  for select to authenticated
  using (active);
create policy player_inventory_owner_read on public.player_inventory
  for select to authenticated
  using (auth.uid() = owner_id);
