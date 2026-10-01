-- Preserve existing category assignments while moving to many-to-many links.
create table public.product_categories (
  product_id uuid not null references public.products(id) on delete cascade,
  category_id uuid not null references public.categories(id) on delete restrict,
  primary key (product_id, category_id)
);
create index product_categories_category_idx on public.product_categories(category_id, product_id);
insert into public.product_categories(product_id, category_id)
  select id, category_id from public.products;

alter table public.products
  add column audiences text[] not null default array['men', 'women']
    check (cardinality(audiences) > 0 and audiences <@ array['men', 'women']
      and array_position(audiences, null) is null),
  add column body_placements text[] not null default '{}'
    check (body_placements <@ array['arm','back','shoulder','wrist','hand','chest','neck','leg','ankle','foot']
      and array_position(body_placements, null) is null);
create index products_audiences_idx on public.products using gin(audiences);
create index products_body_placements_idx on public.products using gin(body_placements);

drop policy products_public_read on public.products;
alter table public.products drop column category_id;

-- A security-definer visibility predicate avoids recursive RLS between products
-- and memberships. It exposes only whether a publicly available product exists.
create function public.catalog_product_visible(product_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.products p
    join public.product_categories pc on pc.product_id = p.id
    join public.categories c on c.id = pc.category_id
    where p.id = $1 and p.active and c.active
  );
$$;
revoke all on function public.catalog_product_visible(uuid) from public;
grant execute on function public.catalog_product_visible(uuid) to anon, authenticated;

alter table public.product_categories enable row level security;
grant select on public.product_categories to anon;
grant select, insert, update, delete on public.product_categories to authenticated;
create policy products_public_read on public.products for select to anon, authenticated
  using (public.catalog_product_visible(id));
create policy product_categories_public_read on public.product_categories for select to anon, authenticated
  using (public.catalog_product_visible(product_id) and exists (
    select 1 from public.categories c where c.id = category_id and c.active
  ));
create policy product_categories_admin on public.product_categories for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

-- One result per tattoo, with RLS applied as the caller. Public category IDs are
-- separate so an admin browsing a hidden category cannot bypass public filters.
create view public.catalog_products with (security_invoker = true) as
select p.*, membership.category_ids, membership.public_category_ids,
  (p.active and cardinality(membership.public_category_ids) > 0) as public_visible
from public.products p
cross join lateral (
  select coalesce(array_agg(c.id order by c.sort_order, c.id), '{}'::uuid[]) as category_ids,
    coalesce(array_agg(c.id order by c.sort_order, c.id) filter (where c.active), '{}'::uuid[]) as public_category_ids
  from public.product_categories pc join public.categories c on c.id = pc.category_id
  where pc.product_id = p.id
) membership;
grant select on public.catalog_products to anon, authenticated;

-- Atomic replacement: failed validation or membership inserts roll back the
-- product changes too. Concurrent edits serialize on the product row.
create function public.save_catalog_product(p_data jsonb, p_id uuid default null)
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
    width_cm, height_cm, price, active, featured, is_new, sort_order, audiences, body_placements)
  values (saved_id, p_data->>'code', p_data->>'name_ar', p_data->>'image_url', p_data->>'thumbnail_url',
    (p_data->>'width_cm')::numeric, (p_data->>'height_cm')::numeric, (p_data->>'price')::integer,
    coalesce((p_data->>'active')::boolean, true), coalesce((p_data->>'featured')::boolean, false),
    coalesce((p_data->>'is_new')::boolean, false), coalesce((p_data->>'sort_order')::integer, 0),
    selected_audiences, placements)
  on conflict (id) do update set
    code = excluded.code, name_ar = excluded.name_ar, image_url = excluded.image_url,
    thumbnail_url = excluded.thumbnail_url, width_cm = excluded.width_cm, height_cm = excluded.height_cm,
    price = excluded.price, active = excluded.active, featured = excluded.featured,
    is_new = excluded.is_new, sort_order = excluded.sort_order,
    audiences = excluded.audiences, body_placements = excluded.body_placements;
  delete from public.product_categories where product_id = saved_id;
  insert into public.product_categories(product_id, category_id)
    select saved_id, unnest(category_ids);
  return saved_id;
end;
$$;
revoke all on function public.save_catalog_product(jsonb, uuid) from public;
grant execute on function public.save_catalog_product(jsonb, uuid) to authenticated;

notify pgrst, 'reload schema';
