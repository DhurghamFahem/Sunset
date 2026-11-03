begin;
insert into auth.users(id,email,raw_app_meta_data) values
 ('00000000-0000-4000-8000-000000000121','prime-worker@example.invalid',
 '{"employee_profile":{"id":"30000000-0000-4000-8000-000000000121","name":"Prime worker","phone":"07701234567"}}'),
 ('00000000-0000-4000-8000-000000000122','prime-admin@example.invalid','{}');
insert into public.admin_users(user_id) values ('00000000-0000-4000-8000-000000000122');
insert into public.categories(id,name_ar) values ('10000000-0000-4000-8000-000000000121','Prime tests');
insert into public.products(id,code,name_ar,image_url,price) values
 ('20000000-0000-4000-8000-000000000121','PRIME-TEST','Tattoo','https://example.invalid/test.png',5000);
insert into public.product_categories(product_id,category_id) values
 ('20000000-0000-4000-8000-000000000121','10000000-0000-4000-8000-000000000121');
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000122';
select public.save_employee_prime_account('30000000-0000-4000-8000-000000000121','prime-user','test-secret',7,44);
-- A profile edit with blank password preserves the encrypted secret.
select public.save_employee_prime_account('30000000-0000-4000-8000-000000000121','prime-user',null,7,44);
do $$ begin
  begin perform public.claim_prime_upload(); raise exception 'Client can claim';
  exception when insufficient_privilege then null; end;
  begin perform public.mark_prime_sending(gen_random_uuid(),gen_random_uuid()); raise exception 'Client can send';
  exception when insufficient_privilege then null; end;
  begin perform public.finish_prime_upload(gen_random_uuid(),gen_random_uuid(),'success','123'); raise exception 'Client can finish';
  exception when insufficient_privilege then null; end;
  begin perform 1 from private.prime_accounts; raise exception 'Client can read credentials';
  exception when insufficient_privilege then null; end;
  begin perform 1 from vault.decrypted_secrets; raise exception 'Client can read Vault';
  exception when insufficient_privilege then null; end;
end $$;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000121';
do $$ begin
  begin perform public.save_employee_prime_account('30000000-0000-4000-8000-000000000121','bad','bad');
    raise exception 'Employee can edit credentials'; exception when insufficient_privilege then null; end;
end $$;
reset role;
-- Isolate the worker from any pre-existing local jobs, without persisting changes.
update private.prime_upload_jobs set next_attempt_at = now() + interval '1 day', lease_until = now() + interval '1 day';
do $$
declare o jsonb; j jsonb; oid uuid; claim uuid; v integer; event_count integer;
begin
  o := public.create_manual_order('40000000-0000-4000-8000-000000000121',
    '[{"product_id":"20000000-0000-4000-8000-000000000121","quantity":2}]');
  oid := (o->>'id')::uuid;
  if exists(select 1 from private.prime_upload_jobs where order_id=oid) then raise exception 'Pending order queued'; end if;
  o := public.update_selection_order(oid,1,'{"status":"confirmed","phone":"07701234567","governorate":"بغداد","area":"المنصور"}');
  if (select count(*) from private.prime_upload_jobs where order_id=oid) <> 1 then raise exception 'Queue missing'; end if;
  o := public.update_selection_order(oid,2,'{"delivery_notes":"Call first"}');
  begin perform public.update_selection_order(oid,3,'{"status":"uploaded"}');
    raise check_violation using message='Manual uploaded accepted'; exception when raise_exception then null; end;
  j := public.claim_prime_upload(); claim := (j->>'claim_token')::uuid;
  if j->'order'->>'id' <> oid::text or j->>'password' <> 'test-secret' or j->>'username' <> 'prime-user' then raise exception 'Wrong credential/order'; end if;
  if (j->'order') ? 'access_token' then raise exception 'Customer token leaked to worker'; end if;
  if public.claim_prime_upload() is not null then raise exception 'Concurrent claim duplicated'; end if;
  if public.mark_prime_sending(oid,gen_random_uuid()) then raise exception 'Stale claim accepted'; end if;
  begin perform public.update_selection_order(oid,3,'{"status":"cancelled"}');
    raise check_violation using message='In-flight edit accepted'; exception when raise_exception then null; end;
  if not public.mark_prime_sending(oid,claim) then raise exception 'Send not marked'; end if;
  if not public.finish_prime_upload(oid,claim,'success','987654') then raise exception 'Finish failed'; end if;
  if not public.finish_prime_upload(oid,claim,'success','987654') then raise exception 'Acknowledgement retry failed'; end if;
  select version into v from public.orders where orders.id=oid and status='uploaded';
  if v is distinct from 4 then raise exception 'Wrong status/version'; end if;
  select count(*) into event_count from public.order_events where order_id=oid and to_status='uploaded' and actor_kind='system';
  if event_count <> 1 then raise exception 'Wrong audit count'; end if;
  if public.claim_prime_upload() is not null then raise exception 'Successful job repeated'; end if;

  -- Every failed attempt leaves the order untouched; fifth exhausts the budget.
  o := public.create_manual_order('40000000-0000-4000-8000-000000000122',
    '[{"product_id":"20000000-0000-4000-8000-000000000121","quantity":1}]');
  oid := (o->>'id')::uuid;
  o := public.update_selection_order(oid,1,'{"status":"confirmed","phone":"07701234567","governorate":"بغداد","area":"المنصور"}');
  for attempt in 1..5 loop
    j := public.claim_prime_upload(); claim := (j->>'claim_token')::uuid;
    if (j->>'attempt')::integer <> attempt then raise exception 'Wrong attempts'; end if;
    perform public.finish_prime_upload(oid,claim,'retry',null,'login_failed');
    if (select status from public.orders where orders.id=oid) <> 'confirmed' then raise exception 'Failed order advanced'; end if;
    if (select version from public.orders where orders.id=oid) <> 2 then raise exception 'Failure modified order'; end if;
    if attempt < 5 then
      if public.claim_prime_upload() is not null then raise exception 'Backoff ignored'; end if;
      if (select next_attempt_at from private.prime_upload_jobs where order_id=oid) <> now() + make_interval(secs => (60*power(2,attempt-1))::integer) then raise exception 'Wrong backoff'; end if;
      update private.prime_upload_jobs set next_attempt_at = now() where order_id=oid;
    end if;
  end loop;
  if (select state from private.prime_upload_jobs where order_id=oid) <> 'failed' then raise exception 'Not exhausted'; end if;
  if public.claim_prime_upload() is not null then raise exception 'Exhausted job claimed'; end if;

  -- Cancel before claim: no shipment. Worker loss before POST is recoverable;
  -- worker loss after POST is ambiguous and must not duplicate a shipment.
  o := public.create_manual_order('40000000-0000-4000-8000-000000000123',
    '[{"product_id":"20000000-0000-4000-8000-000000000121","quantity":1}]');
  oid := (o->>'id')::uuid;
  o := public.update_selection_order(oid,1,'{"status":"confirmed","phone":"07701234567","governorate":"بغداد","area":"المنصور"}');
  j := public.claim_prime_upload(); claim := (j->>'claim_token')::uuid;
  update private.prime_upload_jobs set lease_until=now()-interval '1 second' where order_id=oid;
  j := public.claim_prime_upload();
  if j->>'claim_token' = claim::text or (j->>'attempt')::integer <> 2 then raise exception 'Lease not recovered'; end if;
  if public.finish_prime_upload(oid,claim,'retry') then raise exception 'Stale worker completed'; end if;
  claim := (j->>'claim_token')::uuid;
  perform public.mark_prime_sending(oid,claim);
  update private.prime_upload_jobs set lease_until=now()-interval '1 second' where order_id=oid;
  if public.claim_prime_upload() is not null then raise exception 'Ambiguous POST repeated'; end if;
  if (select state from private.prime_upload_jobs where order_id=oid) <> 'review' then raise exception 'Not held for review'; end if;
  perform public.finish_prime_upload(oid,claim,'success','987655');

  o := public.create_manual_order('40000000-0000-4000-8000-000000000124',
    '[{"product_id":"20000000-0000-4000-8000-000000000121","quantity":1}]');
  oid := (o->>'id')::uuid;
  o := public.update_selection_order(oid,1,'{"status":"confirmed","phone":"07701234567","governorate":"بغداد","area":"المنصور"}');
  perform public.update_selection_order(oid,2,'{"status":"cancelled"}');
  if public.claim_prime_upload() is not null then raise exception 'Cancelled job claimed'; end if;
end $$;
rollback;
