-- Cover fields remain compatible with existing cards, exports, and snapshots.
-- Extra images carry their own thumbnail and retain their editorial order.
create function public.valid_additional_images(images jsonb) returns boolean
language sql immutable set search_path = '' as $$
  select case when jsonb_typeof(images) <> 'array' then false else
    not exists (
      select 1 from jsonb_array_elements(images) image
      where jsonb_typeof(image) <> 'object'
        or jsonb_typeof(image->'image_url') is distinct from 'string'
        or (image->>'image_url') !~ '^https?://'
        or (image ? 'thumbnail_url' and image->'thumbnail_url' <> 'null'::jsonb and (
          jsonb_typeof(image->'thumbnail_url') <> 'string'
          or (image->>'thumbnail_url') !~ '^https?://'
        ))
    ) end;
$$;
revoke all on function public.valid_additional_images(jsonb) from public;
grant execute on function public.valid_additional_images(jsonb) to anon, authenticated;
alter table public.products add column additional_images jsonb not null default '[]'::jsonb
  check (public.valid_additional_images(additional_images));

-- Append the field without changing the existing view's column order or grants.
create or replace view public.catalog_products with (security_invoker = true) as
select p.id, p.code, p.name_ar, p.name_en, p.image_url, p.thumbnail_url,
  p.width_cm, p.height_cm, p.area_cm2, p.price, p.active, p.featured, p.is_new,
  p.sort_order, p.created_at, p.updated_at, p.audiences, p.body_placements,
  membership.category_ids, membership.public_category_ids,
  (p.active and cardinality(membership.public_category_ids) > 0) as public_visible,
  p.additional_images
from public.products p
cross join lateral (
  select coalesce(array_agg(c.id order by c.sort_order, c.id), '{}'::uuid[]) as category_ids,
    coalesce(array_agg(c.id order by c.sort_order, c.id) filter (where c.active), '{}'::uuid[]) as public_category_ids
  from public.product_categories pc join public.categories c on c.id = pc.category_id
  where pc.product_id = p.id
) membership;

create or replace function public.save_catalog_product(p_data jsonb, p_id uuid default null)
returns uuid language plpgsql security invoker set search_path = '' as $$
declare
  saved_id uuid := coalesce(p_id, gen_random_uuid());
  category_ids uuid[];
  selected_audiences text[];
  placements text[];
begin
  if not public.is_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  select array_agg(distinct value::uuid) into category_ids
    from jsonb_array_elements_text(p_data->'category_ids');
  select array_agg(distinct value) into selected_audiences
    from jsonb_array_elements_text(p_data->'audiences');
  select array_agg(distinct value) into placements
    from jsonb_array_elements_text(p_data->'body_placements');
  if coalesce(cardinality(category_ids), 0) = 0
    or coalesce(cardinality(selected_audiences), 0) = 0
    or coalesce(cardinality(placements), 0) = 0 then
    raise exception 'Select at least one category, audience, and body placement' using errcode = '23514';
  end if;
  if p_id is not null then
    perform 1 from public.products where id = p_id for update;
    if not found then raise exception 'Product not found' using errcode = 'P0002'; end if;
  end if;
  insert into public.products(id, code, name_ar, image_url, thumbnail_url,
    width_cm, height_cm, price, active, featured, is_new, sort_order, audiences, body_placements, additional_images)
  values (saved_id, p_data->>'code', p_data->>'name_ar', p_data->>'image_url', p_data->>'thumbnail_url',
    (p_data->>'width_cm')::numeric, (p_data->>'height_cm')::numeric, (p_data->>'price')::integer,
    coalesce((p_data->>'active')::boolean, true), coalesce((p_data->>'featured')::boolean, false),
    coalesce((p_data->>'is_new')::boolean, false), coalesce((p_data->>'sort_order')::integer, 0),
    selected_audiences, placements, coalesce(p_data->'additional_images',
      (select additional_images from public.products where id = saved_id), '[]'::jsonb))
  on conflict (id) do update set
    code = excluded.code, name_ar = excluded.name_ar, image_url = excluded.image_url,
    thumbnail_url = excluded.thumbnail_url, width_cm = excluded.width_cm, height_cm = excluded.height_cm,
    price = excluded.price, active = excluded.active, featured = excluded.featured,
    is_new = excluded.is_new, sort_order = excluded.sort_order,
    audiences = excluded.audiences, body_placements = excluded.body_placements, additional_images = excluded.additional_images;
  delete from public.product_categories where product_id = saved_id;
  insert into public.product_categories(product_id, category_id)
    select saved_id, unnest(category_ids);
  return saved_id;
end;
$$;
revoke all on function public.save_catalog_product(jsonb, uuid) from public;
grant execute on function public.save_catalog_product(jsonb, uuid) to authenticated;

notify pgrst, 'reload schema';
