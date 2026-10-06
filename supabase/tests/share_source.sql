-- Execute against a local database with all migrations; fixtures roll back.
begin;
insert into public.categories(id, name_ar) values ('10000000-0000-4000-8000-000000000096', 'Sharing tests');
insert into public.products(id, code, name_ar, image_url, width_cm, height_cm, price)
  values ('20000000-0000-4000-8000-000000000096', '99996', 'Sharing flower', 'https://example.invalid/f.png', 5, 8, 5000);
insert into public.product_categories(product_id, category_id)
  values ('20000000-0000-4000-8000-000000000096', '10000000-0000-4000-8000-000000000096');
set local role anon;
do $$ declare o jsonb; changed jsonb; denied boolean; begin
  o := public.create_selection_order('40000000-0000-4000-8000-000000000096', '[{"product_id":"20000000-0000-4000-8000-000000000096","quantity":1}]');
  if o->>'source' <> 'instagram' then raise exception 'Wrong initial source'; end if;
  denied := false;
  begin perform public.set_order_share_source((o->>'id')::uuid, gen_random_uuid(), 'whatsapp');
  exception when raise_exception then denied := true; end;
  if not denied then raise exception 'Wrong capability accepted'; end if;
  denied := false;
  begin perform public.set_order_share_source((o->>'id')::uuid, '40000000-0000-4000-8000-000000000096', 'website');
  exception when raise_exception then denied := true; end;
  if not denied then raise exception 'Invalid share destination accepted'; end if;
  changed := public.set_order_share_source((o->>'id')::uuid, '40000000-0000-4000-8000-000000000096', 'whatsapp');
  if changed->>'source' <> 'whatsapp' or (changed->>'version')::int <> 2 or changed->'items' <> o->'items' then
    raise exception 'Source update changed unrelated fields'; end if;
  o := public.set_order_share_source((o->>'id')::uuid, '40000000-0000-4000-8000-000000000096', 'whatsapp');
  if o <> changed then raise exception 'Source retry is not idempotent'; end if;
  o := public.set_order_share_source((o->>'id')::uuid, '40000000-0000-4000-8000-000000000096', 'instagram');
  if o->>'source' <> 'instagram' then raise exception 'Cannot switch back to Instagram'; end if;
  o := public.update_selection_order((o->>'id')::uuid, (o->>'version')::int, '{"status":"cancelled"}', '40000000-0000-4000-8000-000000000096');
  denied := false;
  begin perform public.set_order_share_source((o->>'id')::uuid, '40000000-0000-4000-8000-000000000096', 'whatsapp');
  exception when raise_exception then denied := true; end;
  if not denied then raise exception 'Closed source changed'; end if;
end $$;
reset role;
rollback;
