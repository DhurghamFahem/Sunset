begin;
insert into auth.users(id, email) values ('00000000-0000-4000-8000-000000000097', 'optional-name@example.invalid');
insert into public.admin_users(user_id) values ('00000000-0000-4000-8000-000000000097');
insert into public.categories(id, name_ar) values ('10000000-0000-4000-8000-000000000097', 'Optional names');
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000097';
do $$
declare saved uuid; other_id uuid; payload jsonb; value text; result jsonb;
begin
  payload := '{"code":"ABC-001 / وشم ★","image_url":"https://example.invalid/tattoo.png","category_ids":["10000000-0000-4000-8000-000000000097"],"audiences":["women"],"body_placements":["arm"],"width_cm":3,"height_cm":5}';
  saved := public.save_catalog_product(payload);
  if not exists(select 1 from public.catalog_products where id = saved and name_ar is null and admin_search_text like '%abc%') then
    raise exception 'Unnamed tattoo lost its admin code search';
  end if;
  foreach value in array array['001234', 'ABC', '١٢', '#@!★', '1 2', 'ABC-001 / وشم ★'] loop
    perform public.save_catalog_product(payload || jsonb_build_object('code', value, 'name_ar', null), saved);
    if not exists(select 1 from public.products where id = saved and code = value and name_ar is null) then
      raise exception 'Code changed or optional name rejected: %', value;
    end if;
  end loop;
  foreach value in array array['', '   ', E'\t\n', null] loop
    begin
      perform public.save_catalog_product(payload || jsonb_build_object('code', value), saved);
      raise exception 'Empty code accepted';
    exception when check_violation or not_null_violation then null; end;
    begin
      update public.products set code = value where id = saved;
      raise exception 'Direct write accepted an empty code';
    exception when check_violation or not_null_violation then null; end;
  end loop;
  begin
    perform public.save_catalog_product(payload);
    raise exception 'Duplicate code accepted';
  exception when unique_violation then null; end;
  other_id := public.save_catalog_product(payload || '{"code":"other-unique-code"}');
  begin
    perform public.save_catalog_product(payload, other_id);
    raise exception 'Editing accepted another tattoo code';
  exception when unique_violation then null; end;
  if not exists(select 1 from public.products where id = other_id and code = 'other-unique-code') then
    raise exception 'Rejected edit changed the existing code';
  end if;
  result := public.create_manual_order(gen_random_uuid(), jsonb_build_array(jsonb_build_object('product_id', saved, 'quantity', 1)));
  if result->'items'->0->>'name' is distinct from 'وشم عشبي' then
    raise exception 'Unnamed tattoo order is missing its display name';
  end if;
  perform public.save_catalog_product(payload || '{"name_ar":" "}', saved);
end $$;
reset role;
rollback;
select 'PASS: arbitrary required codes, optional names, admin search, and unnamed orders' as result;
