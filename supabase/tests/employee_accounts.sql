-- Run on a migrated disposable database; all fixtures roll back.
begin;
insert into auth.users(id, email, raw_app_meta_data) values
  ('00000000-0000-4000-8000-000000000111', 'new-worker@example.invalid',
   '{"employee_profile":{"id":"30000000-0000-4000-8000-000000000111","name":"Creator one","phone":"07701234567"}}'),
  ('00000000-0000-4000-8000-000000000112', 'second-worker@example.invalid',
   '{"employee_profile":{"id":"30000000-0000-4000-8000-000000000112","name":"Creator two","phone":"07701234567"}}'),
  ('00000000-0000-4000-8000-000000000113', 'account-admin@example.invalid', '{}');
insert into public.admin_users(user_id) values ('00000000-0000-4000-8000-000000000113');
-- User-editable metadata must never grant employee access.
insert into auth.users(id, email, raw_user_meta_data) values
  ('00000000-0000-4000-8000-000000000114', 'untrusted@example.invalid',
   '{"employee_profile":{"id":"30000000-0000-4000-8000-000000000114","name":"Forbidden","phone":"07701234567"}}');
do $$ begin
  if not exists(select 1 from public.employees where user_id='00000000-0000-4000-8000-000000000111' and email='new-worker@example.invalid') then raise exception 'Missing linked account'; end if;
  if not exists(select 1 from public.employee_users where user_id='00000000-0000-4000-8000-000000000111') then raise exception 'Missing employee role'; end if;
  if exists(select 1 from public.employee_users where user_id='00000000-0000-4000-8000-000000000114') then raise exception 'Untrusted metadata grants access'; end if;
  -- Failure rolls back the Auth user, employee and allowlist together.
  begin
    insert into auth.users(id,email,raw_app_meta_data) values
      ('00000000-0000-4000-8000-000000000115','invalid-profile@example.invalid',
       '{"employee_profile":{"id":"30000000-0000-4000-8000-000000000115","name":"Bad","phone":"x"}}');
    raise exception 'Invalid profile accepted';
  exception when check_violation then null; end;
  if exists(select 1 from auth.users where id='00000000-0000-4000-8000-000000000115') then raise exception 'Orphan account'; end if;
end $$;
insert into public.categories(id,name_ar) values ('10000000-0000-4000-8000-000000000111','Account tests');
insert into public.products(id,code,name_ar,image_url,width_cm,height_cm,price)
  values ('20000000-0000-4000-8000-000000000111','ACCOUNT-TEST-111','Creator test','https://example.invalid/test.png',5,8,5000);

insert into public.product_categories(product_id,category_id) values ('20000000-0000-4000-8000-000000000111','10000000-0000-4000-8000-000000000111');

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000111';
do $$ declare o jsonb; bad jsonb; begin
  if public.is_admin() or not public.can_manage_orders() then raise exception 'Incorrect employee permissions'; end if;
  o := public.create_manual_order('40000000-0000-4000-8000-000000000111','[{"product_id":"20000000-0000-4000-8000-000000000111","quantity":1}]');
  if o->>'created_by' is distinct from auth.uid()::text or o->>'created_by_name' is distinct from 'Creator one' then raise exception 'Missing creator'; end if;
  foreach bad in array array['{"created_by":null}'::jsonb,'{"created_by_name":"forged"}','{"employee_id":null}'] loop
    begin
      perform public.update_selection_order((o->>'id')::uuid,1,bad);
      raise check_violation using message = 'Creator mutation accepted';
    exception when raise_exception then null; end;
  end loop;
  begin
    perform public.update_employee_profile('30000000-0000-4000-8000-000000000111','Forbidden','07701234567');
    raise exception 'Employee can manage accounts';
  exception when insufficient_privilege then null; end;
end $$;

set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000112';
do $$ declare o jsonb; begin
  o := public.create_manual_order('40000000-0000-4000-8000-000000000111','[{"product_id":"20000000-0000-4000-8000-000000000111","quantity":1}]');
  o := public.update_selection_order((o->>'id')::uuid,1,'{"customer_name":"Updated by second worker"}');
  if o->>'created_by' is distinct from '00000000-0000-4000-8000-000000000111' or o->>'created_by_name' is distinct from 'Creator one' then raise exception 'Creator changed on retry/edit'; end if;
end $$;

set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000113';
do $$ declare stats jsonb; begin
  perform public.update_employee_profile('30000000-0000-4000-8000-000000000111','Renamed employee','07701234567');
  select value into stats from public.order_employee_performance() value where value->>'name'='Renamed employee';
  if stats->>'orders' is distinct from '1' then raise exception 'Wrong creator performance'; end if;
  begin
    update public.employees set user_id='00000000-0000-4000-8000-000000000113';
    raise exception 'Client can rebind employee identity';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
set local request.jwt.claim.sub = '';
set local role anon;
do $$ declare o jsonb; begin
  o := public.create_selection_order('40000000-0000-4000-8000-000000000112','[{"product_id":"20000000-0000-4000-8000-000000000111","quantity":1}]');
  if o->>'created_by' is not null or o->>'created_by_name' is distinct from 'الزبون' then raise exception 'Customer attributed to staff'; end if;
end $$;
reset role;
rollback;
select 'PASS: atomic employee provisioning, restricted access, immutable creator and creator performance' as result;
