-- Run against a migrated test database; all fixtures and changes roll back.
begin;
insert into auth.users(id,email,raw_app_meta_data) values
  ('00000000-0000-4000-8000-000000000181','prep-admin@example.invalid','{}'),
  ('00000000-0000-4000-8000-000000000182','prep-employee@example.invalid','{}'),
  ('00000000-0000-4000-8000-000000000183','prep-customer@example.invalid','{}');
insert into public.admin_users(user_id) values ('00000000-0000-4000-8000-000000000181');
insert into public.employee_users(user_id) values ('00000000-0000-4000-8000-000000000182');
insert into public.order_code_reservations(code,reserved_at) values ('QRP1',now()),('QRP2',now());
insert into public.orders(id,access_token,code,status,prime_case_id,items,delivery_cost,phone,governorate,area)
values
  ('40000000-0000-4000-8000-000000000181',gen_random_uuid(),'QRP1','uploaded','0012345',
   '[{"product_id":"20000000-0000-4000-8000-000000000181","name":"Preparation tattoo","code":"PREP-1","quantity":2,"original_price":5000,"unit_price":5000,"accepted_quantity":0}]',
   0,'07701234567','بغداد','المنصور'),
  ('40000000-0000-4000-8000-000000000182',gen_random_uuid(),'QRP2','uploaded','12345',
   '[{"product_id":"20000000-0000-4000-8000-000000000181","name":"Preparation tattoo","code":"PREP-1","quantity":1,"original_price":5000,"unit_price":5000,"accepted_quantity":0}]',
   0,'07701234567','بغداد','المنصور');

set local role anon;
do $$ begin
  begin
    perform public.get_order_by_prime_case_id('0012345');
    raise exception 'Anonymous lookup allowed';
  exception when insufficient_privilege then null; end;
end $$;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000183';
do $$ begin
  begin
    perform public.get_order_by_prime_case_id('0012345');
    raise exception 'Non-staff lookup allowed';
  exception when insufficient_privilege then null; end;
end $$;

set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000181';
do $$ declare o jsonb; begin
  o := public.get_order_by_prime_case_id(' 0012345 ');
  if o->>'id' <> '40000000-0000-4000-8000-000000000181' or o ? 'access_token' then
    raise exception 'Incorrect order or private token leak';
  end if;
  if public.get_order_by_prime_case_id('12345')->>'id' <> '40000000-0000-4000-8000-000000000182' then
    raise exception 'Leading zeros lost';
  end if;
  begin
    perform public.get_order_by_prime_case_id('123');
    raise check_violation using message = 'Partial ID matched';
  exception when raise_exception then null; end;
  begin
    perform public.get_order_by_prime_case_id('');
    raise check_violation using message = 'Blank ID matched';
  exception when raise_exception then null; end;
  begin
    perform public.get_order_by_prime_case_id(null);
    raise check_violation using message = 'Null ID matched';
  exception when raise_exception then null; end;
end $$;

set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000182';
do $$ declare o jsonb; updated jsonb; begin
  o := public.get_order_by_prime_case_id('0012345');
  updated := public.update_selection_order((o->>'id')::uuid,(o->>'version')::int,
    '{"delivery_notes":"Updated by another staff member"}');
  begin
    perform public.update_selection_order((o->>'id')::uuid,(o->>'version')::int,'{"status":"packed"}');
    raise check_violation using message = 'Stale packing succeeded';
  exception when raise_exception then null; end;
  o := public.get_order_by_prime_case_id('0012345');
  updated := public.update_selection_order((o->>'id')::uuid,(o->>'version')::int,'{"status":"packed"}');
  if updated->>'status' <> 'packed' or updated->'items' <> o->'items' then
    raise exception 'Packing changed items or failed';
  end if;
  if public.get_order_by_prime_case_id('0012345')->>'status' <> 'packed' then
    raise exception 'Packed order not available on rescan';
  end if;
  if not exists(select 1 from public.order_events where order_id = (o->>'id')::uuid
    and from_status = 'uploaded' and to_status = 'packed' and actor_id = auth.uid()) then
    raise exception 'Packing audit event missing';
  end if;
end $$;

reset role;
update public.orders set prime_case_id = '0012345'
where id = '40000000-0000-4000-8000-000000000182';
set local role authenticated;
do $$ begin
  begin
    perform public.get_order_by_prime_case_id('0012345');
    raise check_violation using message = 'Ambiguous carrier ID selected an order';
  exception when raise_exception then null; end;
end $$;
rollback;
