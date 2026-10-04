-- Execute against a disposable local Supabase database. Rolled back in full.
begin;
create function pg_temp.assert_true(ok boolean, message text) returns void language plpgsql as $$
begin if ok is not true then raise exception 'FAILED: %', message; end if; end $$;
insert into auth.users(id, email) values
  ('00000000-0000-4000-8000-000000000001', 'g2g-admin-test@example.invalid'),
  ('00000000-0000-4000-8000-000000000002', 'g2g-outsider-test@example.invalid');
insert into public.admin_users(user_id) values ('00000000-0000-4000-8000-000000000001');
insert into public.categories(id, name_ar, active) values
  ('10000000-0000-4000-8000-000000000001','وشومات سوار',true),
  ('10000000-0000-4000-8000-000000000002','مخفي',false);
insert into public.products(id,code,name_ar,image_url,active) values
  ('20000000-0000-4000-8000-000000000001','88001','Test tattoo','https://example.invalid/1.png',true),
  ('20000000-0000-4000-8000-000000000002','88002','Test tattoo','https://example.invalid/2.png',false),
  ('20000000-0000-4000-8000-000000000003','88003','Test tattoo','https://example.invalid/3.png',true);
insert into public.product_categories(product_id, category_id) values
  ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001'),
  ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002'),
  ('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000001'),
  ('20000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000002');

set local role anon;
select pg_temp.assert_true((select count(*) from public.products where code like '880%') = 1, 'anon sees only active product with active category');
select pg_temp.assert_true((select count(*) from public.categories where id::text like '10000000%') = 1, 'anon sees only active category');
select pg_temp.assert_true(not public.is_admin(), 'anon is not admin');
select pg_temp.assert_true((select count(*) from public.catalog_products where code like '880%') = 1, 'view applies caller RLS without duplicate products');
select pg_temp.assert_true((select cardinality(category_ids) from public.catalog_products where code = '88001') = 1, 'public membership omits hidden categories');
select pg_temp.assert_true((select count(*) from public.product_categories where product_id::text like '20000000%') = 1, 'hidden products and categories have no public memberships');
do $$ begin
  begin insert into public.categories(name_ar) values ('forbidden'); raise exception 'anon write allowed';
  exception when insufficient_privilege then null; end;
  begin perform public.save_catalog_product('{}'); raise exception 'anon RPC allowed';
  exception when insufficient_privilege then null; end;
end $$;
reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000002';
select pg_temp.assert_true(not public.is_admin(), 'ordinary authenticated user is not admin');
do $$ begin
  begin insert into public.categories(name_ar) values ('forbidden'); raise exception 'outsider write allowed';
  exception when insufficient_privilege then null; end;
  begin insert into public.admin_users(user_id) values ('00000000-0000-4000-8000-000000000002'); raise exception 'privilege escalation allowed';
  exception when insufficient_privilege then null; end;
  begin insert into storage.objects(bucket_id,name) values ('tattoo-images','forbidden.png'); raise exception 'outsider upload allowed';
  exception when insufficient_privilege then null; end;
  begin perform public.save_catalog_product('{}'); raise exception 'outsider RPC allowed';
  exception when insufficient_privilege then null; end;
  begin insert into public.product_categories values ('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002'); raise exception 'outsider membership write allowed';
  exception when insufficient_privilege then null; end;
end $$;
update public.products set active = false where code = '88001';
select pg_temp.assert_true((select active from public.products where code = '88001'), 'outsider cannot change a product');
reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000001';
select pg_temp.assert_true(public.is_admin(), 'allowlisted user is admin');
select pg_temp.assert_true((select count(*) from public.products where code like '880%') = 3, 'admin sees hidden products');
select pg_temp.assert_true((select count(*) from public.catalog_products where code like '880%' and public_visible) = 1, 'public filter stays effective for signed-in admin');
select pg_temp.assert_true((select cardinality(category_ids) = 2 and cardinality(public_category_ids) = 1 from public.catalog_products where code = '88001'), 'admin gets all memberships with public subset');
insert into public.categories(name_ar) values ('admin insert');
update public.products set price = 5000 where code = '88001';
select pg_temp.assert_true((select price from public.products where code = '88001') = 5000, 'admin update works');
insert into storage.objects(bucket_id,name) values ('tattoo-images','allowed-test.png');
select pg_temp.assert_true(exists(select 1 from storage.objects where bucket_id='tattoo-images' and name='allowed-test.png'), 'admin storage insertion works');
do $$ begin
  begin delete from public.categories where id='10000000-0000-4000-8000-000000000001'; raise exception 'unsafe category deletion allowed';
  exception when foreign_key_violation then null; end;
  begin insert into public.products(code,name_ar,image_url) values ('88001','Test tattoo','https://example.invalid/duplicate.png'); raise exception 'duplicate code allowed';
  exception when unique_violation then null; end;
end $$;

do $$
declare saved uuid; payload jsonb;
begin
  payload := '{"code":"88100","name_ar":"Test tattoo","width_cm":3,"height_cm":5,"image_url":"https://example.invalid/multiple.png","category_ids":["10000000-0000-4000-8000-000000000001","10000000-0000-4000-8000-000000000002"],"audiences":["men","women"],"body_placements":["arm","back"]}';
  saved := public.save_catalog_product(payload);
  perform pg_temp.assert_true((select cardinality(category_ids) = 2 and audiences @> array['men','women'] and body_placements @> array['arm','back'] from public.catalog_products where id = saved), 'RPC creates all properties');
  perform pg_temp.assert_true((select count(*) from public.catalog_products where id = saved and audiences @> array['men'] and body_placements && array['back','foot'] and public_category_ids @> array['10000000-0000-4000-8000-000000000001']::uuid[]) = 1, 'combined filters match once');
  begin
    perform public.save_catalog_product(payload || '{"price":123,"category_ids":["99999999-0000-4000-8000-000000000001"]}', saved);
    raise exception 'invalid category allowed';
  exception when foreign_key_violation then null; end;
  perform pg_temp.assert_true((select price is null and cardinality(category_ids) = 2 from public.catalog_products where id = saved), 'failed membership replacement rolls back product and links');
  begin
    perform public.save_catalog_product(payload || '{"audiences":[]}', saved);
    raise exception 'empty audiences allowed';
  exception when check_violation then null; end;
  begin
    perform public.save_catalog_product(payload || '{"body_placements":["invalid"]}', saved);
    raise exception 'invalid placement allowed';
  exception when check_violation then null; end;
  begin
    perform public.save_catalog_product(payload || '{"category_ids":[]}', saved);
    raise exception 'empty memberships allowed';
  exception when check_violation then null; end;
  begin
    perform public.save_catalog_product(payload || '{"body_placements":[]}', saved);
    raise exception 'empty placements allowed';
  exception when check_violation then null; end;
  perform public.save_catalog_product(payload || '{"category_ids":["10000000-0000-4000-8000-000000000002"],"audiences":["women"],"body_placements":["wrist"]}', saved);
  perform pg_temp.assert_true((select cardinality(category_ids) = 1 and not public_visible and audiences = array['women'] and body_placements = array['wrist'] from public.catalog_products where id = saved), 'edit replaces memberships and all properties');
end $$;
reset role;
rollback;
select 'PASS: public visibility, anonymous writes, authenticated outsider, privilege escalation, storage, admin writes, duplicate codes, category deletion, combined filters, atomic multi-category saves' as result;
