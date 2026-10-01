begin;
insert into auth.users(id, email) values ('00000000-0000-4000-8000-000000000071', 'tag-filter-admin@example.invalid');
insert into public.admin_users(user_id) values ('00000000-0000-4000-8000-000000000071');
insert into public.categories(id, name_ar, active) values
  ('10000000-0000-4000-8000-000000000071','Tag filter visible',true),
  ('10000000-0000-4000-8000-000000000072','Tag filter hidden',false);
insert into public.products(id, code, name_ar, image_url, active, tags) values
  ('20000000-0000-4000-8000-000000000071','G2G-88771','First','https://example.invalid/1.png',true,array['public-tag-test','shared-tag-test']),
  ('20000000-0000-4000-8000-000000000072','G2G-88772','Second','https://example.invalid/2.png',true,array['shared-tag-test']),
  ('20000000-0000-4000-8000-000000000073','G2G-88773','Hidden category','https://example.invalid/3.png',true,array['hidden-tag-test']),
  ('20000000-0000-4000-8000-000000000074','G2G-88774','Inactive','https://example.invalid/4.png',false,array['inactive-tag-test']);
insert into public.product_categories values
  ('20000000-0000-4000-8000-000000000071','10000000-0000-4000-8000-000000000071'),
  ('20000000-0000-4000-8000-000000000072','10000000-0000-4000-8000-000000000071'),
  ('20000000-0000-4000-8000-000000000073','10000000-0000-4000-8000-000000000072'),
  ('20000000-0000-4000-8000-000000000074','10000000-0000-4000-8000-000000000071');
set local role anon;
do $$ begin
  if (select count(*) from public.catalog_available_tags() tag where tag in ('public-tag-test','shared-tag-test')) <> 2 then raise exception 'Public tags missing or duplicated'; end if;
  if exists(select 1 from public.catalog_available_tags() tag where tag in ('hidden-tag-test','inactive-tag-test')) then raise exception 'Hidden tags leaked'; end if;
  if (select count(*) from public.catalog_products where public_visible and tags && array['public-tag-test','shared-tag-test']) <> 2 then raise exception 'Multiple tag filter failed'; end if;
end $$;
reset role;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000071';
do $$ begin
  if exists(select 1 from public.catalog_available_tags() tag where tag in ('hidden-tag-test','inactive-tag-test')) then raise exception 'Admin public options leaked hidden tags'; end if;
end $$;
reset role;
rollback;
select 'PASS: distinct public tag options, any-tag matching, hidden and inactive tag filtering' as result;
