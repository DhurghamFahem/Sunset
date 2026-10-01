-- Run after all migrations. Fixtures and changes are rolled back.
begin;
insert into auth.users(id, email) values ('00000000-0000-4000-8000-000000000091', 'gallery-admin@example.invalid');
insert into public.admin_users(user_id) values ('00000000-0000-4000-8000-000000000091');
insert into public.categories(id, name_ar) values ('10000000-0000-4000-8000-000000000091', 'Gallery test');
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000091';
do $$
declare saved uuid; payload jsonb; bad jsonb;
begin
  payload := '{"code":"G2G-88991","image_url":"https://example.invalid/cover.png","thumbnail_url":"https://example.invalid/cover-thumb.png","category_ids":["10000000-0000-4000-8000-000000000091"],"audiences":["men","women"],"body_placements":["arm"],"additional_images":[{"image_url":"https://example.invalid/second.png","thumbnail_url":"https://example.invalid/second-thumb.png"},{"image_url":"https://example.invalid/third.png"}]}';
  saved := public.save_catalog_product(payload);
  if not exists(select 1 from public.catalog_products where id = saved and jsonb_array_length(additional_images) = 2 and additional_images->0->>'image_url' = 'https://example.invalid/second.png') then
    raise exception 'Gallery did not round trip through public view';
  end if;
  -- Legacy clients must not erase a gallery when the new field is absent.
  perform public.save_catalog_product(payload - 'additional_images', saved);
  if (select jsonb_array_length(additional_images) from public.products where id = saved) <> 2 then raise exception 'Legacy edit erased gallery'; end if;
  foreach bad in array array['{}'::jsonb, 'null'::jsonb, '[{}]'::jsonb, '[{"image_url":"bad"}]'::jsonb, '[{"image_url":"https://example.invalid/image.png","thumbnail_url":12}]'::jsonb] loop
    begin
      perform public.save_catalog_product(payload || jsonb_build_object('additional_images', bad, 'price', 123), saved);
      raise exception 'Malformed gallery accepted: %', bad;
    exception when check_violation then null; end;
  end loop;
  if not exists(select 1 from public.products where id = saved and price is null and jsonb_array_length(additional_images) = 2) then raise exception 'Invalid save was not atomic'; end if;
  -- Promote the second image and retain the old cover as an extra image.
  perform public.save_catalog_product(payload || '{"image_url":"https://example.invalid/second.png","thumbnail_url":"https://example.invalid/second-thumb.png","additional_images":[{"image_url":"https://example.invalid/cover.png"}]}', saved);
  if not exists(select 1 from public.products where id = saved and image_url = 'https://example.invalid/second.png' and jsonb_array_length(additional_images) = 1) then raise exception 'Cover change failed'; end if;
  perform public.save_catalog_product(payload || '{"additional_images":[]}', saved);
  if (select additional_images from public.products where id = saved) <> '[]'::jsonb then raise exception 'Gallery removal failed'; end if;
end $$;
reset role;
set local role anon;
do $$ begin
  if not exists(select 1 from public.catalog_products where code = 'G2G-88991' and additional_images = '[]'::jsonb) then raise exception 'Public gallery read failed'; end if;
end $$;
reset role;
rollback;
select 'PASS: galleries, cover changes, legacy edits, validation, atomic saves, public reads' as result;
