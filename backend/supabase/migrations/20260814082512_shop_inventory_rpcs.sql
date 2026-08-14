-- Purchase + consume inventory. Tabel sudah di shop_inventory_bits.

create or replace function public._consume_inventory(p_owner uuid, p_item_id text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_qty integer;
begin
  update public.player_inventory
     set quantity = quantity - 1,
         updated_at = now()
   where owner_id = p_owner
     and item_id = p_item_id
     and quantity > 0
  returning quantity into v_qty;
  if not found then raise exception 'NO_ITEM'; end if;
  if v_qty = 0 then
    delete from public.player_inventory
     where owner_id = p_owner and item_id = p_item_id;
  end if;
  return v_qty;
end $$;

revoke all on function public._consume_inventory(uuid, text)
  from public, anon, authenticated;
grant execute on function public._consume_inventory(uuid, text) to service_role;

create or replace function public.purchase_catalog_item(
  p_owner uuid,
  p_item_id text,
  p_expected_price integer,
  p_key text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item public.catalog_items;
  v_purchase public.shop_purchases;
  v_bits integer;
  v_qty integer := 0;
  v_replayed boolean := false;
begin
  if p_key is null or length(p_key) not between 1 and 128 then
    raise exception 'INVALID_IDEMPOTENCY_KEY';
  end if;

  begin
    insert into public.shop_purchases (owner_id, item_id, price, idempotency_key)
    values (p_owner, p_item_id, greatest(coalesce(p_expected_price, 0), 1), p_key)
    returning * into v_purchase;
  exception
    when unique_violation then
      select * into v_purchase
        from public.shop_purchases
       where owner_id = p_owner and idempotency_key = p_key;
      if not found
         or v_purchase.item_id is distinct from p_item_id then
        raise exception 'IDEMPOTENCY_CONFLICT';
      end if;
      v_replayed := true;
  end;

  select * into v_item
    from public.catalog_items
   where id = p_item_id and active
   for share;
  if not found then raise exception 'INVALID_ITEM'; end if;

  select bits into v_bits
    from public.profiles
   where id = p_owner
   for update;
  if not found then raise exception 'NO_PROFILE'; end if;

  if v_replayed then
    select coalesce(quantity, 0) into v_qty
      from public.player_inventory
     where owner_id = p_owner and item_id = p_item_id;
    return jsonb_build_object(
      'bits', v_bits,
      'item_id', p_item_id,
      'quantity', coalesce(v_qty, 0),
      'price', v_purchase.price,
      'replayed', true
    );
  end if;

  if p_expected_price is distinct from v_item.price then
    raise exception 'PRICE_CHANGED';
  end if;
  if v_bits < v_item.price then raise exception 'NO_BITS'; end if;

  select coalesce(quantity, 0) into v_qty
    from public.player_inventory
   where owner_id = p_owner and item_id = p_item_id;
  if v_qty >= 999 then raise exception 'STACK_FULL'; end if;

  update public.shop_purchases
     set price = v_item.price
   where id = v_purchase.id;

  update public.profiles
     set bits = bits - v_item.price
   where id = p_owner
  returning bits into v_bits;

  insert into public.player_inventory (owner_id, item_id, quantity)
  values (p_owner, p_item_id, 1)
  on conflict (owner_id, item_id) do update
    set quantity = public.player_inventory.quantity + 1,
        updated_at = now()
  returning quantity into v_qty;

  insert into public.quota_ledger (owner_id, currency, delta, reason, ref_id)
  values (p_owner, 'bits', -v_item.price, 'shop_buy', v_purchase.id);

  return jsonb_build_object(
    'bits', v_bits,
    'item_id', p_item_id,
    'quantity', v_qty,
    'price', v_item.price,
    'replayed', false
  );
end $$;

revoke all on function public.purchase_catalog_item(uuid, text, integer, text)
  from public, anon, authenticated;
grant execute on function public.purchase_catalog_item(uuid, text, integer, text)
  to service_role;

