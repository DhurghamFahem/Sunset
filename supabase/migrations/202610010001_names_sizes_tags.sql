-- Normalize Arabic spelling/diacritics and English case in names and tags.
-- Keep normalization aligned with lib/models/catalog_search.dart.
create function public.normalize_catalog_search(value text) returns text
language sql immutable set search_path = '' as $$
  select trim(regexp_replace(
    translate(regexp_replace(lower(coalesce(value, '')),
      U&'[\064B-\065F\0670\06D6-\06ED\0640]', '', 'g'), 'أإآٱىة', 'اااايه'),
    '[^[:alnum:]]+', ' ', 'g'));
$$;
create function public.catalog_search_document(name text, tags text[]) returns text
language sql immutable set search_path = '' as $$
  select public.normalize_catalog_search(coalesce(name, '') || ' ' || coalesce(array_to_string(tags, ' '), ''));
$$;
create function public.valid_catalog_tags(tags text[]) returns boolean
language sql immutable set search_path = '' as $$
  select cardinality(tags) <= 30 and array_position(tags, null) is null and not exists(
    select 1 from unnest(tags) tag where length(trim(tag)) not between 1 and 64
      or public.normalize_catalog_search(tag) = ''
  );
$$;
revoke all on function public.normalize_catalog_search(text), public.catalog_search_document(text, text[]), public.valid_catalog_tags(text[]) from public;
grant execute on function public.normalize_catalog_search(text), public.catalog_search_document(text, text[]), public.valid_catalog_tags(text[]) to anon, authenticated;

-- Existing unnamed records get a neutral name; the admin can replace it.
update public.products set name_ar = 'وشم عشبي' where nullif(trim(name_ar), '') is null;
alter table public.products
  alter column name_ar set not null,
  add constraint products_name_required check (length(trim(name_ar)) > 0),
  add column tags text[] not null default '{}' check (public.valid_catalog_tags(tags));
alter table public.products
  add column search_text text generated always as (public.catalog_search_document(name_ar, tags)) stored,
  add column admin_search_text text generated always as (public.catalog_search_document(name_ar || ' ' || code, tags)) stored;
create index products_search_text_idx on public.products using gin(search_text extensions.gin_trgm_ops);
create index products_admin_search_text_idx on public.products using gin(admin_search_text extensions.gin_trgm_ops);
create index products_exact_size_idx on public.products(width_cm, height_cm) where active;

create or replace view public.catalog_products with (security_invoker = true) as
select p.id, p.code, p.name_ar, p.name_en, p.image_url, p.thumbnail_url,
  p.width_cm, p.height_cm, p.area_cm2, p.price, p.active, p.featured, p.is_new,
  p.sort_order, p.created_at, p.updated_at, p.audiences, p.body_placements,
  membership.category_ids, membership.public_category_ids,
  (p.active and cardinality(membership.public_category_ids) > 0) as public_visible,
  p.additional_images, p.tags, p.search_text, p.admin_search_text
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
  selected_tags text[];
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
  if nullif(trim(p_data->>'name_ar'), '') is null
    or (p_data->>'width_cm') is null or (p_data->>'height_cm') is null then
    raise exception 'Name and exact width and height are required' using errcode = '23514';
  end if;
  if p_data ? 'tags' then
    if jsonb_typeof(p_data->'tags') <> 'array' then
      raise exception 'Tags must be an array' using errcode = '23514';
    end if;
    if exists(select 1 from jsonb_array_elements(p_data->'tags') tag where jsonb_typeof(tag) <> 'string') then
      raise exception 'Tags must be strings' using errcode = '23514';
    end if;
    select coalesce(array_agg(trim(value) order by ordinal), '{}'::text[]) into selected_tags
      from jsonb_array_elements_text(p_data->'tags') with ordinality as entries(value, ordinal);
  else
    select tags into selected_tags from public.products where id = saved_id;
    selected_tags := coalesce(selected_tags, '{}'::text[]);
  end if;
  if p_id is not null then
    perform 1 from public.products where id = p_id for update;
    if not found then raise exception 'Product not found' using errcode = 'P0002'; end if;
  end if;
  insert into public.products(id, code, name_ar, image_url, thumbnail_url,
    width_cm, height_cm, price, active, featured, is_new, sort_order, audiences, body_placements, additional_images, tags)
  values (saved_id, p_data->>'code', p_data->>'name_ar', p_data->>'image_url', p_data->>'thumbnail_url',
    (p_data->>'width_cm')::numeric, (p_data->>'height_cm')::numeric, (p_data->>'price')::integer,
    coalesce((p_data->>'active')::boolean, true), coalesce((p_data->>'featured')::boolean, false),
    coalesce((p_data->>'is_new')::boolean, false), coalesce((p_data->>'sort_order')::integer, 0),
    selected_audiences, placements, coalesce(p_data->'additional_images',
      (select additional_images from public.products where id = saved_id), '[]'::jsonb), selected_tags)
  on conflict (id) do update set
    code = excluded.code, name_ar = excluded.name_ar, image_url = excluded.image_url,
    thumbnail_url = excluded.thumbnail_url, width_cm = excluded.width_cm, height_cm = excluded.height_cm,
    price = excluded.price, active = excluded.active, featured = excluded.featured,
    is_new = excluded.is_new, sort_order = excluded.sort_order,
    audiences = excluded.audiences, body_placements = excluded.body_placements, additional_images = excluded.additional_images, tags = excluded.tags;
  delete from public.product_categories where product_id = saved_id;
  insert into public.product_categories(product_id, category_id)
    select saved_id, unnest(category_ids);
  return saved_id;
end;
$$;
revoke all on function public.save_catalog_product(jsonb, uuid) from public;
grant execute on function public.save_catalog_product(jsonb, uuid) to authenticated;

notify pgrst, 'reload schema';

-- The same visibility rule applies even for an admin browsing the public site.
create function public.catalog_available_sizes()
returns table(width_cm numeric, height_cm numeric)
language sql stable security invoker set search_path = '' as $$
  select distinct p.width_cm, p.height_cm from public.catalog_products p
  where p.public_visible and p.width_cm is not null and p.height_cm is not null
  order by p.width_cm, p.height_cm;
$$;
revoke all on function public.catalog_available_sizes() from public;
grant execute on function public.catalog_available_sizes() to anon, authenticated;
notify pgrst, 'reload schema';