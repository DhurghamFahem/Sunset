-- Tattoo codes accept arbitrary text but must contain a non-whitespace character.
-- Keep the existing NOT NULL and UNIQUE code constraints.
alter table public.products
  drop constraint if exists products_code_check,
  drop constraint if exists products_numeric_code_check,
  add constraint products_code_required check (code ~ '[^[:space:]]'),
  drop constraint if exists products_name_required,
  alter column name_ar drop not null;

-- Rebuild the generated admin search column so a missing name cannot erase the code.
drop view public.catalog_products;
alter table public.products drop column admin_search_text;
alter table public.products add column admin_search_text text generated always as
  (public.catalog_search_document(coalesce(name_ar, '') || ' ' || code, tags)) stored;
create index products_admin_search_text_idx on public.products using gin(admin_search_text extensions.gin_trgm_ops);

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

grant select on public.catalog_products to anon, authenticated;

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
  if (p_data->>'width_cm') is null or (p_data->>'height_cm') is null then
    raise exception 'Exact width and height are required' using errcode = '23514';
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

-- Orders retain the same neutral display name used by the customer catalog.
create or replace function public.create_selection_order(p_token uuid, p_items jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  order_id uuid; code_value text; alphabet constant text := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  snapshot jsonb; row_count integer; distinct_count integer; claimed text; bytes bytea;
begin
  if p_token is null or jsonb_typeof(p_items) is distinct from 'array'
    or jsonb_array_length(p_items) not between 1 and 100 then
    raise exception 'ORDER:اختيارات غير صحيحة';
  end if;
  -- A retry on any device is atomic and returns the same order.
  perform pg_advisory_xact_lock(hashtextextended(p_token::text, 0));
  select id into order_id from public.orders where access_token = p_token;
  if found then return public.get_selection_order(order_id, p_token); end if;
  if exists(select 1 from jsonb_array_elements(p_items) i where
    coalesce((i->>'quantity')::numeric, 0) not between 1 and 99 or
    (i->>'quantity')::numeric <> trunc((i->>'quantity')::numeric)) then
    raise exception 'ORDER:الكمية يجب أن تكون من 1 إلى 99';
  end if;
  select count(*), count(distinct i->>'product_id') into row_count, distinct_count from jsonb_array_elements(p_items) i;
  if row_count <> distinct_count then raise exception 'ORDER:وشم مكرر'; end if;
  select jsonb_agg(jsonb_build_object('product_id', p.id, 'name', coalesce(nullif(trim(p.name_ar), ''), 'وشم عشبي'), 'code', p.code,
    'quantity', (i->>'quantity')::integer, 'original_price', p.price, 'unit_price', p.price,
    'accepted_quantity', 0) order by ord) into snapshot
    from jsonb_array_elements(p_items) with ordinality as x(i, ord)
    join public.products p on p.id = (i->>'product_id')::uuid
    where public.catalog_product_visible(p.id);
  if coalesce(jsonb_array_length(snapshot), 0) <> row_count then
    raise exception 'ORDER:بعض الوشومات لم تعد متوفرة';
  end if;
  for attempt in 1..200 loop
    bytes := extensions.gen_random_bytes(4);
    code_value := '';
    -- Rejection sampling keeps each of the 36 characters equally likely.
    for n in 0..3 loop
      while get_byte(bytes, n) >= 252 loop bytes := set_byte(bytes, n, get_byte(extensions.gen_random_bytes(1), 0)); end loop;
      code_value := code_value || substr(alphabet, (get_byte(bytes, n) % 36) + 1, 1);
    end loop;
    claimed := null;
    insert into public.order_code_reservations as r(code, reserved_at) values (code_value, clock_timestamp())
      on conflict (code) do update set reserved_at = excluded.reserved_at
      where r.reserved_at <= clock_timestamp() - interval '30 days'
        and not exists (select 1 from public.orders o where o.code = r.code and o.status in ('pending','confirmed','packed','shipped'))
      returning code into claimed;
    exit when claimed is not null;
  end loop;
  if claimed is null then raise exception 'ORDER:تعذر تخصيص رمز. حاول مرة ثانية'; end if;
  insert into public.orders(access_token, code, items, delivery_cost)
    values (p_token, code_value, snapshot, (select delivery_cost from public.order_settings where id)) returning id into order_id;
  insert into public.order_events(order_id, to_status, version, actor_id, actor_kind)
    values (order_id, 'pending', 1, auth.uid(), 'customer');
  return public.get_selection_order(order_id, p_token);
end;
$$;

notify pgrst, 'reload schema';
