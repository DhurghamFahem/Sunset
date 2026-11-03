begin;

-- Simulate a verified carrier receipt for tests of later order stages.
create function pg_temp.prime_accept(p_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare claim uuid := gen_random_uuid(); v integer;
begin
  select version into v from public.orders where id=p_id for update;
  update private.prime_upload_jobs set state='sending', claim_token=claim, order_version=v where order_id=p_id;
  perform public.finish_prime_upload(p_id,claim,'success','987654');
  return public.get_selection_order(p_id);
end $$;

insert into auth.users(id, email) values ('00000000-0000-4000-8000-000000000088', 'tattoo-edit@example.invalid');
insert into public.admin_users(user_id) values ('00000000-0000-4000-8000-000000000088');
insert into public.categories(id, name_ar) values ('10000000-0000-4000-8000-000000000088', 'Edit tattoos');
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000088';
insert into public.products(id, code, name_ar, image_url, price, active) values
  ('20000000-0000-4000-8000-000000000088', 'EDIT-A', 'First', 'https://example.invalid/a.png', 5000, true),
  ('20000000-0000-4000-8000-000000000089', 'EDIT-B', null, 'https://example.invalid/b.png', 3000, true),
  ('20000000-0000-4000-8000-000000000090', 'EDIT-HIDDEN', null, 'https://example.invalid/c.png', 1000, false);
insert into public.product_categories(product_id, category_id)
  select id, '10000000-0000-4000-8000-000000000088'::uuid from public.products where code like 'EDIT-%';
do $$
declare
  o jsonb; first_item jsonb; second_item jsonb; bad jsonb; denied boolean;
  stage text; stale integer; token uuid := '40000000-0000-4000-8000-000000000088';
begin
  o := public.create_selection_order(token, '[{"product_id":"20000000-0000-4000-8000-000000000088","quantity":1}]');
  first_item := o->'items'->0;
  second_item := '{"product_id":"20000000-0000-4000-8000-000000000089","name":"EDIT-B","code":"EDIT-B","quantity":2,"original_price":3000,"unit_price":2500,"accepted_quantity":0}';
  foreach stage in array array['pending','confirmed','uploaded','packed'] loop
    if stage = 'uploaded' then
      o := pg_temp.prime_accept((o->>'id')::uuid);
    elsif stage <> 'pending' then
      o := public.update_selection_order((o->>'id')::uuid, (o->>'version')::integer,
        jsonb_build_object('status', stage, 'phone', '07701234567', 'governorate', 'Baghdad', 'area', 'Mansour'));
    end if;
    o := public.update_selection_order((o->>'id')::uuid, (o->>'version')::integer,
      jsonb_build_object('items', jsonb_build_array(second_item, first_item)));
    if jsonb_array_length(o->'items') <> 2 or o->'items'->0->>'code' <> 'EDIT-B' then raise exception 'Addition failed'; end if;
    -- Customers cannot change selections even when they know the order token.
    perform set_config('request.jwt.claim.sub', '', true);
    denied := false;
    begin
      perform public.update_selection_order((o->>'id')::uuid, (o->>'version')::integer,
        jsonb_build_object('items', jsonb_build_array(first_item)), token);
    exception when raise_exception then denied := true; end;
    if not denied then raise exception 'Customer changed selection'; end if;
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000088', true);
    o := public.update_selection_order((o->>'id')::uuid, (o->>'version')::integer,
      jsonb_build_object('items', jsonb_build_array(second_item)));
    o := public.update_selection_order((o->>'id')::uuid, (o->>'version')::integer,
      jsonb_build_object('items', jsonb_build_array(first_item)));
    if o->>'status' <> stage or o->'items'->0->>'code' <> 'EDIT-A' then raise exception 'Replacement failed'; end if;
  end loop;
  foreach bad in array array[
    '[]'::jsonb, jsonb_build_array(first_item, first_item),
    jsonb_build_array(jsonb_set(second_item, '{product_id}', '"20000000-0000-4000-8000-000000000090"')),
    jsonb_build_array(jsonb_set(second_item, '{product_id}', '"20000000-0000-4000-8000-000000000091"')),
    jsonb_build_array(jsonb_set(second_item, '{original_price}', '6000')),
    jsonb_build_array(jsonb_set(second_item, '{name}', '"Forged"')),
    jsonb_build_array(jsonb_set(second_item, '{code}', '"Forged"')),
    jsonb_build_array(jsonb_set(second_item, '{quantity}', '0')),
    jsonb_build_array(jsonb_set(second_item, '{quantity}', '1.5')),
    jsonb_build_array(jsonb_set(second_item, '{accepted_quantity}', '1'))
  ] loop
    denied := false;
    begin
      perform public.update_selection_order((o->>'id')::uuid, (o->>'version')::integer, jsonb_build_object('items', bad));
    exception when raise_exception then denied := true; end;
    if not denied then raise exception 'Invalid selection allowed: %', bad; end if;
  end loop;
  -- Retained snapshots survive catalog changes and deactivation.
  update public.products set price = 9000, name_ar = 'Renamed', active = false
    where id = '20000000-0000-4000-8000-000000000088';
  o := public.update_selection_order((o->>'id')::uuid, (o->>'version')::integer,
    jsonb_build_object('items', jsonb_build_array(first_item, second_item)));
  if o->'items'->0->>'original_price' <> '5000' or o->'items'->0->>'name' <> 'First' then raise exception 'Snapshot overwritten'; end if;
  stale := (o->>'version')::integer;
  o := public.update_selection_order((o->>'id')::uuid, stale, '{"status":"shipped"}');
  denied := false;
  begin perform public.update_selection_order((o->>'id')::uuid, stale, jsonb_build_object('items', jsonb_build_array(second_item)));
  exception when raise_exception then denied := true; end;
  if not denied then raise exception 'Stale selection edit succeeded'; end if;
  foreach bad in array array[jsonb_build_array(second_item), jsonb_build_array(second_item, first_item),
    jsonb_build_array(first_item, first_item), jsonb_build_array(first_item, second_item, first_item)] loop
    denied := false;
    begin perform public.update_selection_order((o->>'id')::uuid, (o->>'version')::integer, jsonb_build_object('items', bad));
    exception when raise_exception then denied := true; end;
    if not denied then raise exception 'Shipped selection changed'; end if;
  end loop;
  o := public.update_selection_order((o->>'id')::uuid, (o->>'version')::integer,
    jsonb_build_object('status', 'partial', 'items', jsonb_set(o->'items', '{1,accepted_quantity}', '1')));
  if o->'items'->1->>'accepted_quantity' <> '1' then raise exception 'Receipt failed after editing tattoos'; end if;
end $$;
rollback;
