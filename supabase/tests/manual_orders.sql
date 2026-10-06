-- Run after all migrations; these fixtures never persist.
begin;
insert into auth.users(id, email) values ('00000000-0000-4000-8000-000000000095', 'manual-admin@example.invalid');
insert into public.admin_users(user_id) values ('00000000-0000-4000-8000-000000000095');
insert into public.categories(id, name_ar) values ('10000000-0000-4000-8000-000000000095', 'Manual order tests');
insert into public.products(id, code, name_ar, image_url, width_cm, height_cm, price)
  values ('20000000-0000-4000-8000-000000000095', '99995', 'Manual flower', 'https://example.invalid/flower.png', 5, 8, 5000);
insert into public.product_categories(product_id, category_id) values ('20000000-0000-4000-8000-000000000095', '10000000-0000-4000-8000-000000000095');
set local role anon;
do $$ declare denied boolean := false; begin
  begin perform public.create_manual_order(gen_random_uuid(), '[]'); exception when insufficient_privilege then denied := true; end;
  if not denied then raise exception 'Anonymous manual creation allowed'; end if;
end $$;
reset role;
set local role authenticated;
set local request.jwt.claim.sub = '';
do $$ declare denied boolean := false; begin
  begin perform public.create_manual_order(gen_random_uuid(), '[]'); exception when insufficient_privilege then denied := true; end;
  if not denied then raise exception 'Non-admin manual creation allowed'; end if;
end $$;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000095';
do $$ declare o jsonb; retry jsonb; denied boolean := false; begin
  o := public.create_manual_order('40000000-0000-4000-8000-000000000095', '[{"product_id":"20000000-0000-4000-8000-000000000095","quantity":2}]');
  retry := public.create_manual_order('40000000-0000-4000-8000-000000000095', '[{"product_id":"20000000-0000-4000-8000-000000000095","quantity":2}]');
  if retry->>'id' <> o->>'id' then raise exception 'Manual retry duplicated order'; end if;
  if o->>'status' <> 'pending' or o ? 'access_token' then raise exception 'Invalid manual result'; end if;
  if o->>'source' <> 'instagram' then raise exception 'Manual order must default to Instagram'; end if;
  if o->'items'->0->>'code' <> '99995' or (o->'items'->0->>'original_price')::integer <> 5000 then raise exception 'Missing price/code snapshot'; end if;
  if (select count(*) from public.order_events where order_id = (o->>'id')::uuid) <> 1 then raise exception 'Duplicate audit event'; end if;
  if not exists(select 1 from public.order_events where order_id = (o->>'id')::uuid and actor_kind = 'admin' and actor_id = auth.uid()) then raise exception 'Manual creation not attributed to staff'; end if;
  begin perform public.create_manual_order(gen_random_uuid(), '[{"product_id":"20000000-0000-4000-8000-000000000095","quantity":0}]'); exception when raise_exception then denied := true; end;
  if not denied then raise exception 'Invalid manual quantity allowed'; end if;
  o := public.update_selection_order((o->>'id')::uuid, 1, '{"status":"confirmed","phone":"07701234567","governorate":"Baghdad","area":"Mansour","source":"whatsapp"}');
  if o->>'status' <> 'confirmed' or o->>'source' <> 'whatsapp' then raise exception 'Manual confirmation failed'; end if;
  retry := public.create_manual_order('40000000-0000-4000-8000-000000000095', '[{"product_id":"20000000-0000-4000-8000-000000000095","quantity":2}]');
  if retry <> o then raise exception 'Retry reset existing order'; end if;
end $$;
reset role;
rollback;
