begin;
insert into auth.users(id, email) values ('00000000-0000-4000-8000-000000000081', 'search-admin@example.invalid');
insert into public.admin_users(user_id) values ('00000000-0000-4000-8000-000000000081');
insert into public.categories(id, name_ar, active) values
  ('10000000-0000-4000-8000-000000000081', 'Visible sizes', true),
  ('10000000-0000-4000-8000-000000000082', 'Hidden sizes', false);
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000081';
do $$
declare saved uuid; payload jsonb; bad jsonb;
begin
  if public.normalize_catalog_search('  وَرْدَة أَلِفٌ FLOWER  ') <> 'ورده الف flower' then raise exception 'Normalization mismatch'; end if;
  payload := '{"code":"G2G-88881","name_ar":"وَرْدَة","image_url":"https://example.invalid/tattoo.png","category_ids":["10000000-0000-4000-8000-000000000081"],"audiences":["women"],"body_placements":["arm"],"width_cm":5.5,"height_cm":8,"tags":["نَاعِم","FLOWER"]}';
  saved := public.save_catalog_product(payload);
  if not exists(select 1 from public.catalog_products where id = saved and search_text like '%ورده%' and search_text like '%ناعم%' and search_text like '%flower%' and width_cm = 5.5 and height_cm = 8) then raise exception 'Combined name/tag/size search failed'; end if;
  if exists(select 1 from public.catalog_products where id = saved and search_text like '%88881%') then raise exception 'Customer search includes internal code'; end if;
  if not exists(select 1 from public.catalog_products where id = saved and admin_search_text like '%88881%') then raise exception 'Admin code search failed'; end if;
  foreach bad in array array[
    '{"name_ar":" "}'::jsonb, '{"width_cm":null}'::jsonb, '{"height_cm":null}'::jsonb,
    '{"width_cm":0}'::jsonb, '{"tags":[null]}'::jsonb, '{"tags":[" "]}'::jsonb,
    '{"tags":{}}'::jsonb, '{"tags":[42]}'::jsonb
  ] loop
    begin
      perform public.save_catalog_product(payload || bad, saved);
      raise exception 'Invalid name/size/tags accepted: %', bad;
    exception when check_violation then null; end;
  end loop;
  perform public.save_catalog_product(payload - 'tags', saved);
  if not exists(select 1 from public.products where id = saved and tags = array['نَاعِم','FLOWER']) then raise exception 'Older client erased tags'; end if;
  perform public.save_catalog_product(payload || '{"tags":["جديد"]}', saved);
  if not exists(select 1 from public.products where id = saved and search_text like '%جديد%' and search_text not like '%flower%') then raise exception 'Search index did not update'; end if;
  perform public.save_catalog_product(payload || '{"code":"G2G-88882","width_cm":987,"height_cm":654,"category_ids":["10000000-0000-4000-8000-000000000082"]}');
  if exists(select 1 from public.catalog_available_sizes() where width_cm = 987 and height_cm = 654) then raise exception 'Admin customer sizes include hidden category'; end if;
end $$;
reset role;
set local role anon;
do $$ begin
  if (select count(*) from public.catalog_available_sizes() where width_cm = 5.5 and height_cm = 8) <> 1 then raise exception 'Distinct available size missing'; end if;
  if exists(select 1 from public.catalog_available_sizes() where width_cm = 987 and height_cm = 654) then raise exception 'Hidden size is public'; end if;
end $$;
reset role;
rollback;
select 'PASS: required names, exact sizes, public size visibility, normalized tags, atomic validation, admin code search' as result;
