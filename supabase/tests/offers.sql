begin;
insert into auth.users(id, email) values
  ('00000000-0000-4000-8000-000000000094', 'offers@example.invalid');
insert into public.admin_users(user_id) values ('00000000-0000-4000-8000-000000000094');
insert into public.categories(id, name_ar) values ('10000000-0000-4000-8000-000000000094', 'Offer tests');
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000094';
do $$
declare
  first_id uuid;
  second_id uuid;
  offer_id uuid := '30000000-0000-4000-8000-000000000094';
  payload jsonb := '{"code":"offer-test-one","image_url":"https://example.invalid/tattoo.png","category_ids":["10000000-0000-4000-8000-000000000094"],"audiences":["women"],"body_placements":["arm"],"width_cm":3,"height_cm":5,"price":9000}';
begin
  first_id := public.save_catalog_product(payload);
  second_id := public.save_catalog_product(payload || '{"code":"offer-test-two"}');
  perform public.save_catalog_offer(offer_id, 'Single', 0, array[first_id], true);
  if not exists (select 1 from public.catalog_offers where id = offer_id and price = 0 and jsonb_array_length(products) = 1) then
    raise exception 'Single tattoo offer failed';
  end if;
  perform public.save_catalog_offer(offer_id, 'Bundle', 12000, array[second_id, first_id], true);
  perform public.save_catalog_offer(offer_id, 'Bundle', 12000, array[second_id, first_id], true);
  if not exists (select 1 from public.catalog_offers where id = offer_id and products->0->>'id' = second_id::text and jsonb_array_length(products) = 2) then
    raise exception 'Bundle order or retry failed';
  end if;
  begin
    perform public.save_catalog_offer(offer_id, 'Bad', 1, '{}'::uuid[], true);
    raise exception 'Empty offer accepted';
  exception when check_violation then null; end;
  begin
    perform public.save_catalog_offer(offer_id, 'Bad', 1, array[first_id, first_id], true);
    raise exception 'Duplicate tattoo accepted';
  exception when check_violation then null; end;
  begin
    perform public.save_catalog_offer(offer_id, 'Bad', 1, array_fill(first_id, array[101]), true);
    raise exception 'Oversize offer accepted';
  exception when check_violation then null; end;
  begin
    perform public.save_catalog_offer(offer_id, 'Bad', -1, array[first_id], true);
    raise exception 'Negative price accepted';
  exception when check_violation then null; end;
  begin
    perform public.save_catalog_offer(offer_id, 'Bad', 1, array[gen_random_uuid()], true);
    raise exception 'Unknown tattoo accepted';
  exception when foreign_key_violation then null; end;
  if not exists (select 1 from public.catalog_offers where id = offer_id and name_ar = 'Bundle' and price = 12000 and jsonb_array_length(products) = 2) then
    raise exception 'Failed save changed the bundle';
  end if;
  begin
    delete from public.products where id = first_id;
    raise exception 'Referenced tattoo deletion accepted';
  exception when foreign_key_violation then null; end;
  begin
    delete from public.offer_products op where op.offer_id = '30000000-0000-4000-8000-000000000094';
    raise exception 'Direct membership mutation accepted';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
set local request.jwt.claim.sub = '';
set local role anon;
do $$ begin
  if not exists (select 1 from public.catalog_offers where id = '30000000-0000-4000-8000-000000000094' and jsonb_array_length(products) = 2) then
    raise exception 'Public bundle not visible';
  end if;
  begin
    perform public.delete_catalog_offer('30000000-0000-4000-8000-000000000094');
    raise exception 'Anonymous mutation accepted';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
set local role authenticated;
do $$ begin
  begin
    perform public.save_catalog_offer('30000000-0000-4000-8000-000000000094', 'Forbidden', 1, array[gen_random_uuid()], true);
    raise exception 'Non-admin mutation accepted';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
update public.products set active = false where code = 'offer-test-one';
set local role anon;
do $$ begin
  if exists (select 1 from public.catalog_offers where id = '30000000-0000-4000-8000-000000000094')
    or exists (select 1 from public.offer_products where offer_id = '30000000-0000-4000-8000-000000000094') then
    raise exception 'Partial bundle leaked to public';
  end if;
end $$;
reset role;
update public.products set active = true where code = 'offer-test-one';
update public.categories set active = false where id = '10000000-0000-4000-8000-000000000094';
set local role anon;
do $$ begin
  if exists (select 1 from public.catalog_offers where id = '30000000-0000-4000-8000-000000000094') then
    raise exception 'Hidden-category bundle leaked';
  end if;
end $$;
reset role;
update public.categories set active = true where id = '10000000-0000-4000-8000-000000000094';
update public.offers set active = false where id = '30000000-0000-4000-8000-000000000094';
set local role anon;
do $$ begin
  if exists (select 1 from public.catalog_offers where id = '30000000-0000-4000-8000-000000000094') then
    raise exception 'Inactive offer leaked';
  end if;
end $$;
reset role;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000094';
do $$ begin
  if not exists (select 1 from public.catalog_offers where id = '30000000-0000-4000-8000-000000000094' and not public_visible) then
    raise exception 'Admin cannot manage hidden offer';
  end if;
  perform public.delete_catalog_offer('30000000-0000-4000-8000-000000000094');
  if (select count(*) from public.products where code in ('offer-test-one', 'offer-test-two') and price = 9000) <> 2 then
    raise exception 'Offer mutation affected original tattoos';
  end if;
end $$;
reset role;
rollback;
select 'PASS: offers, atomic validation, retry, membership, public visibility and authorization' as result;
