begin;
insert into auth.users(id, email) values ('00000000-0000-4000-8000-000000000093', 'order-admin@example.invalid');
insert into public.admin_users(user_id) values ('00000000-0000-4000-8000-000000000093');
insert into public.categories(id, name_ar) values ('10000000-0000-4000-8000-000000000093', 'Order tests');
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000093';
insert into public.products(id, code, name_ar, image_url, width_cm, height_cm, price)
  values ('20000000-0000-4000-8000-000000000093', '99993', 'Order flower', 'https://example.invalid/flower.png', 5, 8, 5000);
insert into public.product_categories(product_id, category_id) values ('20000000-0000-4000-8000-000000000093', '10000000-0000-4000-8000-000000000093');
insert into public.employees(id, name, phone) values ('30000000-0000-4000-8000-000000000093', 'Test employee', '07701234567');
update public.order_settings set delivery_cost = 5000;
reset role;
set local request.jwt.claim.sub = '';
set local role anon;
do $$
declare o jsonb; same jsonb; bad jsonb; denied boolean; token uuid := '40000000-0000-4000-8000-000000000093';
begin
  o := public.create_selection_order(token, '[{"product_id":"20000000-0000-4000-8000-000000000093","quantity":3}]');
  if o->>'code' !~ '^[A-Z0-9]{4}$' or o ? 'access_token' then raise exception 'Invalid public order result'; end if;
  same := public.create_selection_order(token, '[{"product_id":"20000000-0000-4000-8000-000000000093","quantity":3}]');
  if same->>'id' <> o->>'id' then raise exception 'Retry created another order'; end if;
  denied := false;
  begin perform public.get_selection_order((o->>'id')::uuid, gen_random_uuid()); exception when raise_exception then denied := true; end;
  if not denied then raise exception 'Guessed token read private data'; end if;
  denied := false;
  begin perform 1 from public.orders; exception when insufficient_privilege then denied := true; end;
  if not denied then raise exception 'Anonymous table read'; end if;
  foreach bad in array array['{"status":"confirmed"}'::jsonb, '{"status":"shipped"}', '{"status":"confirmed","phone":"07701234567","governorate":"Baghdad","area":"Mansour"}', '{"phone":"07701234567","status":"cancelled"}', '{"final_total":1}', '{"employee_id":"30000000-0000-4000-8000-000000000093"}'] loop
    denied := false;
    begin perform public.update_selection_order((o->>'id')::uuid, 1, bad, token); exception when raise_exception then denied := true; end;
    if not denied then raise exception 'Invalid customer mutation: %', bad; end if;
  end loop;
end $$;
reset role;
set local role authenticated;
-- Signed-in non-admins also cannot enumerate or manage orders.
do $$ declare denied boolean := false; begin
  begin perform public.list_selection_orders(); exception when insufficient_privilege then denied := true; end;
  if not denied then raise exception 'Non-admin can list orders'; end if;
end $$;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000093';
do $$
declare o jsonb; bad jsonb; denied boolean; items jsonb; stats jsonb;
begin
  o := public.create_selection_order('40000000-0000-4000-8000-000000000093', '[{"product_id":"20000000-0000-4000-8000-000000000093","quantity":3}]');
  o := public.update_selection_order((o->>'id')::uuid, 1, '{"status":"confirmed","phone":"07701234567","governorate":"Baghdad","area":"Mansour"}');
  if o->>'status' <> 'confirmed' then raise exception 'Employee booking failed'; end if;
  items := jsonb_set(o->'items', '{0,unit_price}', '4000');
  o := public.update_selection_order((o->>'id')::uuid, (o->>'version')::integer,
    jsonb_build_object('items', items, 'final_total', 14000, 'employee_id', '30000000-0000-4000-8000-000000000093'));
  foreach bad in array array['{"final_total":18000}'::jsonb, '{"final_total":-1}', '{"status":"delivered"}',
    jsonb_build_object('items', jsonb_set(items, '{0,original_price}', '6000')),
    jsonb_build_object('items', jsonb_set(items, '{0,quantity}', '1.5'))] loop
    denied := false;
    begin perform public.update_selection_order((o->>'id')::uuid, (o->>'version')::integer, bad); exception when raise_exception then denied := true; end;
    if not denied then raise exception 'Invalid admin mutation: %', bad; end if;
  end loop;
  denied := false;
  begin perform public.update_selection_order((o->>'id')::uuid, 1, '{"status":"packed"}'); exception when raise_exception then denied := true; end;
  if not denied then raise exception 'Stale version allowed'; end if;
  o := public.update_selection_order((o->>'id')::uuid, (o->>'version')::integer, '{"status":"packed"}');
  o := public.update_selection_order((o->>'id')::uuid, (o->>'version')::integer, '{"status":"shipped"}');
  foreach bad in array array['{"status":"cancelled"}'::jsonb, '{"final_total":100}', '{"status":"partial"}',
    jsonb_build_object('items', jsonb_set(items, '{0,quantity}', '4'))] loop
    denied := false;
    begin perform public.update_selection_order((o->>'id')::uuid, (o->>'version')::integer, bad); exception when raise_exception then denied := true; end;
    if not denied then raise exception 'Invalid shipped mutation: %', bad; end if;
  end loop;
  o := public.update_selection_order((o->>'id')::uuid, (o->>'version')::integer,
    jsonb_build_object('status', 'partial', 'items', jsonb_set(items, '{0,accepted_quantity}', '1')));
  select value into stats from public.order_employee_performance() value where value->>'name' = 'Test employee';
  if (stats->>'revenue')::integer <> 8000 or (stats->>'accepted_pieces')::integer <> 1 then raise exception 'Partial reporting mismatch: %', stats; end if;
  denied := false;
  begin perform public.update_selection_order((o->>'id')::uuid, (o->>'version')::integer, '{"status":"partial"}'); exception when raise_exception then denied := true; end;
  if not denied then raise exception 'Terminal order modified'; end if;
end $$;
reset role;
-- Customer receipt confirmation uses the same shipping locks as staff.
set local request.jwt.claim.sub = '';
set local role anon;
do $$ declare o jsonb; begin
  o := public.create_selection_order('40000000-0000-4000-8000-000000000094', '[{"product_id":"20000000-0000-4000-8000-000000000093","quantity":2}]');
end $$;
reset role;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000093';
set local role authenticated;
do $$ declare o jsonb; begin
  o := public.create_selection_order('40000000-0000-4000-8000-000000000094', '[{"product_id":"20000000-0000-4000-8000-000000000093","quantity":2}]');
  o := public.update_selection_order((o->>'id')::uuid, 1, '{"status":"confirmed","phone":"07709876543","governorate":"Baghdad","area":"Mansour"}');
  o := public.update_selection_order((o->>'id')::uuid, 2, '{"status":"packed"}');
  perform public.update_selection_order((o->>'id')::uuid, 3, '{"status":"shipped"}');
end $$;
reset role;
set local request.jwt.claim.sub = '';
set local role anon;
do $$ declare o jsonb; denied boolean := false; token uuid := '40000000-0000-4000-8000-000000000094'; begin
  o := public.create_selection_order(token, '[{"product_id":"20000000-0000-4000-8000-000000000093","quantity":2}]');
  begin
    perform public.update_selection_order((o->>'id')::uuid, 4,
      jsonb_build_object('status', 'partial', 'items', jsonb_set(jsonb_set(o->'items', '{0,unit_price}', '1'), '{0,accepted_quantity}', '1')), token);
  exception when raise_exception then denied := true; end;
  if not denied then raise exception 'Customer changed shipped price'; end if;
  o := public.update_selection_order((o->>'id')::uuid, 4, '{"status":"delivered"}', token);
  if (o->'items'->0->>'accepted_quantity')::integer <> 2 then raise exception 'Full customer receipt failed'; end if;
  for n in 1..50 loop
    perform public.create_selection_order(gen_random_uuid(), '[{"product_id":"20000000-0000-4000-8000-000000000093","quantity":1}]');
  end loop;
end $$;
reset role;
do $$ begin
  if exists(select code from public.orders where created_at > now() - interval '30 days' group by code having count(*) > 1) then raise exception 'Duplicate recent codes'; end if;
  if (select count(*) from public.order_events where actor_kind = 'admin') < 4 then raise exception 'Missing audit events'; end if;
end $$;
rollback;
select 'PASS: order privacy, booking, discounts, quantity validation, transitions, shipping lock, partial acceptance, employee performance, audit' as result;
