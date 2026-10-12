-- New order snapshots use the tattoo code when its name is missing.
create or replace function public.create_selection_order(p_token uuid, p_items jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  order_id uuid; code_value text; alphabet constant text := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  snapshot jsonb; row_count integer; distinct_count integer; claimed text; bytes bytea;
begin
  if p_token is null or jsonb_typeof(p_items) is distinct from 'array'
    or jsonb_array_length(p_items) not between 1 and 100 then
    raise exception 'ORDER:اختيارات غير صحيحة';
  end if;
  -- A retry on any device is atomic and returns the same order.
  perform pg_advisory_xact_lock(hashtextextended(p_token::text, 0));
  select id into order_id from public.orders where access_token = p_token;
  if found then return public.get_selection_order(order_id, p_token); end if;
  if exists(select 1 from jsonb_array_elements(p_items) i where
    coalesce((i->>'quantity')::numeric, 0) not between 1 and 99 or
    (i->>'quantity')::numeric <> trunc((i->>'quantity')::numeric)) then
    raise exception 'ORDER:الكمية يجب أن تكون من 1 إلى 99';
  end if;
  select count(*), count(distinct i->>'product_id') into row_count, distinct_count from jsonb_array_elements(p_items) i;
  if row_count <> distinct_count then raise exception 'ORDER:وشم مكرر'; end if;
  select jsonb_agg(jsonb_build_object('product_id', p.id, 'name', coalesce(nullif(trim(p.name_ar), ''), p.code), 'code', p.code,
    'quantity', (i->>'quantity')::integer, 'original_price', p.price, 'unit_price', p.price,
    'accepted_quantity', 0) order by ord) into snapshot
    from jsonb_array_elements(p_items) with ordinality as x(i, ord)
    join public.products p on p.id = (i->>'product_id')::uuid
    where public.catalog_product_visible(p.id);
  if coalesce(jsonb_array_length(snapshot), 0) <> row_count then
    raise exception 'ORDER:بعض الوشومات لم تعد متوفرة';
  end if;
  for attempt in 1..200 loop
    bytes := extensions.gen_random_bytes(4);
    code_value := '';
    -- Rejection sampling keeps each of the 36 characters equally likely.
    for n in 0..3 loop
      while get_byte(bytes, n) >= 252 loop bytes := set_byte(bytes, n, get_byte(extensions.gen_random_bytes(1), 0)); end loop;
      code_value := code_value || substr(alphabet, (get_byte(bytes, n) % 36) + 1, 1);
    end loop;
    claimed := null;
    insert into public.order_code_reservations as r(code, reserved_at) values (code_value, clock_timestamp())
      on conflict (code) do update set reserved_at = excluded.reserved_at
      where r.reserved_at <= clock_timestamp() - interval '30 days'
        and not exists (select 1 from public.orders o where o.code = r.code and o.status in ('pending','confirmed','packed','shipped'))
      returning code into claimed;
    exit when claimed is not null;
  end loop;
  if claimed is null then raise exception 'ORDER:تعذر تخصيص رمز. حاول مرة ثانية'; end if;
  insert into public.orders(access_token, code, items, delivery_cost)
    values (p_token, code_value, snapshot, (select delivery_cost from public.order_settings where id)) returning id into order_id;
  insert into public.order_events(order_id, to_status, version, actor_id, actor_kind)
    values (order_id, 'pending', 1, auth.uid(), 'customer');
  return public.get_selection_order(order_id, p_token);
end;
$$;

notify pgrst, 'reload schema';
