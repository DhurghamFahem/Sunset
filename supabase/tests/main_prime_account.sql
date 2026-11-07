begin;
-- Transactional fixtures; no Prime network calls or persistent changes.
insert into auth.users(id,email,raw_app_meta_data) values
 ('00000000-0000-4000-8000-000000000171','getoge@gmail.com','{}'),
 ('00000000-0000-4000-8000-000000000172','main-prime-worker@example.invalid',
 '{"employee_profile":{"id":"30000000-0000-4000-8000-000000000172","name":"Worker","phone":"07701234567"}}'),
 ('00000000-0000-4000-8000-000000000173','other-prime-admin@example.invalid','{}');
insert into public.admin_users(user_id) values
 ('00000000-0000-4000-8000-000000000171'), ('00000000-0000-4000-8000-000000000173');
insert into public.categories(id,name_ar) values ('10000000-0000-4000-8000-000000000171','Main Prime tests');
insert into public.products(id,code,name_ar,image_url,price) values
 ('20000000-0000-4000-8000-000000000171','MAIN-PRIME-TEST','Tattoo','https://example.invalid/test.png',5000);
insert into public.product_categories(product_id,category_id) values
 ('20000000-0000-4000-8000-000000000171','10000000-0000-4000-8000-000000000171');
update private.prime_upload_jobs set next_attempt_at = now() + interval '1 day', lease_until = now() + interval '1 day';

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000171';
do $$ begin
  if public.get_main_prime_account() <> '{"username":"","configured":false}'::jsonb then
    raise exception 'Unexpected initial settings'; end if;
  begin
    perform public.save_main_prime_account('main-user');
    raise check_violation using message = 'Password not required';
  exception when raise_exception then null; end;
end $$;
select public.save_main_prime_account(' main-user ','main-secret');
select public.save_main_prime_account('main-user',null);
select public.save_employee_prime_account('30000000-0000-4000-8000-000000000172','employee-user','employee-secret');
do $$ begin
  if public.get_main_prime_account() <> '{"username":"main-user","configured":true}'::jsonb then
    raise exception 'Settings leaked password or failed to save'; end if;
  begin perform 1 from private.main_prime_accounts; raise exception 'Client can read credentials';
  exception when insufficient_privilege then null; end;
  begin perform private.prime_order_account(gen_random_uuid()); raise exception 'Client can resolve credentials';
  exception when insufficient_privilege then null; end;
  begin
    perform public.save_main_prime_account('renamed-user',null);
    raise check_violation using message = 'Username changed without password';
  exception when raise_exception then null; end;
end $$;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000172';
do $$ begin
  begin perform public.get_main_prime_account(); raise exception 'Employee can read main settings';
  exception when insufficient_privilege then null; end;
  begin perform public.save_main_prime_account('bad','bad'); raise exception 'Employee can change main credentials';
  exception when insufficient_privilege then null; end;
end $$;
set local role anon;
do $$ begin
  begin perform public.get_main_prime_account(); raise exception 'Anonymous settings access';
  exception when insufficient_privilege then null; end;
  begin perform public.save_main_prime_account('bad','bad'); raise exception 'Anonymous settings write';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000171';
do $$
declare o jsonb; j jsonb; oid uuid; secret_id uuid; lookup jsonb;
begin
  o := public.create_manual_order(gen_random_uuid(),
    '[{"product_id":"20000000-0000-4000-8000-000000000171","quantity":1}]');
  oid := (o->>'id')::uuid;
  if o->>'created_by' <> auth.uid()::text then raise exception 'Main creator not stamped'; end if;
  if public.prime_location_account(oid,auth.uid())->>'password' <> 'main-secret' then
    raise exception 'Main address lookup did not preserve saved password'; end if;
  -- Editing a main order as an employee still uses the main account.
  lookup := public.prime_location_account(oid,'00000000-0000-4000-8000-000000000172');
  if lookup->>'username' <> 'main-user' then raise exception 'Editing switched main credentials'; end if;
  o := public.update_selection_order(oid,1,
    '{"status":"confirmed","phone":"07701234567","governorate":"بغداد","area":"المنصور"}');
  j := public.claim_prime_upload();
  if j->'order'->>'id' is distinct from oid::text or j->>'username' is distinct from 'main-user' or
    j->>'password' is distinct from 'main-secret' then raise exception 'Wrong main upload credentials'; end if;
  if (j->'order') ? 'access_token' then raise exception 'Customer token leaked'; end if;
  perform public.finish_prime_upload(oid,(j->>'claim_token')::uuid,'failed',null,'upload_rejected');
  select password_id into secret_id from private.main_prime_accounts where user_id = auth.uid();
  perform public.save_main_prime_account('main-user','rotated-secret');
  if public.prime_location_account(oid,auth.uid())->>'password' <> 'rotated-secret' then
    raise exception 'Password rotation failed'; end if;
  perform public.save_main_prime_account('',null);
  if exists(select 1 from vault.secrets where id = secret_id) then raise exception 'Removed secret retained'; end if;
  if public.prime_location_account(oid,'00000000-0000-4000-8000-000000000172') is not null then
    raise exception 'Main order fell back to employee credentials'; end if;
  perform public.save_main_prime_account('main-user','main-secret');
end $$;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000172';
do $$
declare o jsonb; j jsonb; oid uuid;
begin
  o := public.create_manual_order(gen_random_uuid(),
    '[{"product_id":"20000000-0000-4000-8000-000000000171","quantity":1}]');
  oid := (o->>'id')::uuid;
  if public.prime_location_account(oid,'00000000-0000-4000-8000-000000000171')->>'username' <> 'employee-user' then
    raise exception 'Main editor overrode employee account'; end if;
  o := public.update_selection_order(oid,1,
    '{"status":"confirmed","phone":"07701234567","governorate":"بغداد","area":"المنصور"}');
  j := public.claim_prime_upload();
  if j->'order'->>'id' is distinct from oid::text or j->>'password' is distinct from 'employee-secret' then
    raise exception 'Employee upload credentials changed'; end if;
end $$;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000173';
do $$ declare o jsonb; begin
  o := public.create_manual_order(gen_random_uuid(),
    '[{"product_id":"20000000-0000-4000-8000-000000000171","quantity":1}]');
  if public.prime_location_account((o->>'id')::uuid,auth.uid()) is not null then
    raise exception 'Other admin inherited main credentials'; end if;
end $$;
rollback;
