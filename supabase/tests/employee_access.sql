-- Run after all migrations. Every fixture and attempted write is rolled back.
begin;
insert into auth.users(id, email) values
  ('00000000-0000-4000-8000-000000000101', 'employee-test@example.invalid'),
  ('00000000-0000-4000-8000-000000000102', 'employee-admin-test@example.invalid');
insert into public.employee_users(user_id) values ('00000000-0000-4000-8000-000000000101');
insert into public.admin_users(user_id) values ('00000000-0000-4000-8000-000000000102');
insert into public.categories(id, name_ar) values ('10000000-0000-4000-8000-000000000101', 'Employee test');
insert into public.products(id, code, name_ar, image_url, width_cm, height_cm, price)
  values ('20000000-0000-4000-8000-000000000101', 'EMPLOYEE-TEST-101', 'Employee test', 'https://example.invalid/test.png', 5, 8, 5000);
insert into public.product_categories(product_id, category_id)
  values ('20000000-0000-4000-8000-000000000101', '10000000-0000-4000-8000-000000000101');
insert into public.employees(id, name, phone, user_id)
  values ('30000000-0000-4000-8000-000000000101', 'Employee test', '07701234567', '00000000-0000-4000-8000-000000000101');

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000101';
do $$ declare o jsonb; result jsonb; affected integer; begin
  if public.is_admin() or not public.can_manage_orders() then raise exception 'Wrong employee role'; end if;
  o := public.create_manual_order('40000000-0000-4000-8000-000000000101', '[{"product_id":"20000000-0000-4000-8000-000000000101","quantity":2}]');
  if o ? 'access_token' then raise exception 'Private customer token exposed'; end if;
  if not exists(select 1 from public.list_selection_orders('') x where x->>'id' = o->>'id') then raise exception 'Employee cannot list orders'; end if;
  result := public.get_selection_order((o->>'id')::uuid);
  if result <> o then raise exception 'Employee cannot read order'; end if;
  o := public.update_selection_order((o->>'id')::uuid, 1, '{"status":"confirmed","phone":"07701234567","governorate":"Baghdad","area":"Mansour"}');
  if o->>'status' <> 'confirmed' then raise exception 'Employee cannot confirm'; end if;
  if not exists(select 1 from public.order_events where order_id=(o->>'id')::uuid and actor_kind='employee' and actor_id=auth.uid()) then raise exception 'Employee audit missing'; end if;
  if o->>'created_by' <> auth.uid()::text or o->>'created_by_name' <> 'Employee test' then raise exception 'Creator missing'; end if;
  if exists(select 1 from public.employees) then raise exception 'Employee can read login directory'; end if;
  if not exists(select 1 from public.catalog_products where id='20000000-0000-4000-8000-000000000101') then raise exception 'Customer images unavailable'; end if;

  begin
    perform public.order_employee_performance();
    raise exception 'Employee can read team performance';
  exception when insufficient_privilege then null; end;
  begin
    insert into public.admin_users(user_id) values (auth.uid());
    raise exception 'Employee can escalate to admin';
  exception when insufficient_privilege then null; end;
  begin
    insert into public.employee_users(user_id) values ('00000000-0000-4000-8000-000000000102');
    raise exception 'Employee can grant access';
  exception when insufficient_privilege then null; end;
  begin
    perform public.save_catalog_product('{}', null);
    raise exception 'Employee can save catalog';
  exception when insufficient_privilege then null; end;
  begin
    perform public.save_catalog_offer(gen_random_uuid(), 'Forbidden', 1, array['20000000-0000-4000-8000-000000000101'::uuid], true);
    raise exception 'Employee can save offers';
  exception when insufficient_privilege then null; end;
  begin
    perform public.delete_catalog_offer(gen_random_uuid());
    raise exception 'Employee can delete offers';
  exception when insufficient_privilege then null; end;
  begin
    insert into public.categories(name_ar) values ('Forbidden');
    raise exception 'Employee can create category';
  exception when insufficient_privilege then null; end;
  begin
    insert into public.employees(name,phone) values ('Forbidden','07701234567');
    raise exception 'Employee can create assignee';
  exception when insufficient_privilege then null; end;
  begin
    insert into storage.objects(bucket_id,name) values ('tattoo-images','employee-forbidden.png');
    raise exception 'Employee can upload catalog image';
  exception when insufficient_privilege then null; end;
  update public.order_settings set delivery_cost=delivery_cost+1;
  get diagnostics affected = row_count;
  if affected <> 0 then raise exception 'Employee can change delivery settings'; end if;
  begin
    update public.employees set name='Forbidden' where id='30000000-0000-4000-8000-000000000101';
    raise exception 'Employee can edit employee';
  exception when insufficient_privilege then null; end;
  delete from public.products where id='20000000-0000-4000-8000-000000000101';
  get diagnostics affected = row_count;
  if affected <> 0 then raise exception 'Employee can delete tattoo'; end if;
end $$;

-- Ordinary authenticated users and anonymous visitors have no staff access.
set local request.jwt.claim.sub = '';
do $$ begin
  if public.can_manage_orders() then raise exception 'Ordinary user is staff'; end if;
  begin perform public.list_selection_orders(); raise exception 'Ordinary user can list';
  exception when insufficient_privilege then null; end;
end $$;
set local role anon;
do $$ begin
  if public.can_manage_orders() then raise exception 'Anonymous user is staff'; end if;
end $$;
reset role;

-- Removing membership takes effect immediately, even for an existing session.
delete from public.employee_users where user_id='00000000-0000-4000-8000-000000000101';
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000101';
do $$ begin
  if public.can_manage_orders() then raise exception 'Revocation ineffective'; end if;
  begin perform public.list_selection_orders(); raise exception 'Revoked employee can list';
  exception when insufficient_privilege then null; end;
end $$;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000102';
do $$ begin
  if not public.is_admin() or not public.can_manage_orders() then raise exception 'Administrator access broken'; end if;
  perform public.list_selection_orders();
  perform public.order_employee_performance();
end $$;
reset role;
rollback;
