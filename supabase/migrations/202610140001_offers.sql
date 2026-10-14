-- Offers refer to existing tattoos; saving the price and membership is atomic.
create table public.offers (
  id uuid primary key default gen_random_uuid(),
  name_ar text not null check (length(btrim(name_ar)) between 1 and 120),
  price integer not null check (price >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.offer_products (
  offer_id uuid not null references public.offers(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  position integer not null check (position between 0 and 99),
  primary key (offer_id, product_id),
  unique (offer_id, position)
);
create index offer_products_product_idx on public.offer_products(product_id);
create index offers_created_idx on public.offers(created_at desc, id);
create trigger offers_updated before update on public.offers
  for each row execute function public.touch_updated_at();

-- Evaluate complete membership as owner so RLS cannot hide one member and
-- accidentally expose the remaining tattoos as a smaller, full-price offer.
create function public.offer_is_public(p_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.offers o where o.id = p_id and o.active
      and exists (select 1 from public.offer_products op where op.offer_id = o.id)
      and not exists (
        select 1 from public.offer_products op
        join public.catalog_products p on p.id = op.product_id
        where op.offer_id = o.id and not p.public_visible
      )
  );
$$;
revoke all on function public.offer_is_public(uuid) from public;
grant execute on function public.offer_is_public(uuid) to anon, authenticated;

alter table public.offers enable row level security;
alter table public.offer_products enable row level security;
revoke all on public.offers, public.offer_products from anon, authenticated;
grant select on public.offers, public.offer_products to anon, authenticated;
create policy offers_read on public.offers for select to anon, authenticated
  using ((select public.is_admin()) or public.offer_is_public(id));
create policy offer_products_read on public.offer_products for select to anon, authenticated
  using ((select public.is_admin()) or public.offer_is_public(offer_id));

create view public.catalog_offers with (security_invoker = true) as
select o.*, public.offer_is_public(o.id) as public_visible,
  coalesce((
    select jsonb_agg(to_jsonb(p) order by op.position)
    from public.offer_products op join public.catalog_products p on p.id = op.product_id
    where op.offer_id = o.id
  ), '[]'::jsonb) as products
from public.offers o;
grant select on public.catalog_offers to anon, authenticated;

-- Client-generated IDs make a retried creation update the same offer.
-- Direct writes are revoked; only these checked functions can mutate offers.
create function public.save_catalog_offer(
  p_id uuid, p_name text, p_price integer, p_product_ids uuid[], p_active boolean
) returns uuid language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  if p_id is null or p_name is null or length(btrim(p_name)) not between 1 and 120
    or p_price is null or p_price < 0 or p_active is null
    or coalesce(cardinality(p_product_ids), 0) not between 1 and 100
    or array_position(p_product_ids, null) is not null
    or (select count(distinct id) from unnest(p_product_ids) id) <> cardinality(p_product_ids) then
    raise exception 'Invalid offer' using errcode = '23514';
  end if;
  -- Lock selected records against deletion until the FK memberships are saved.
  perform 1 from public.products where id = any(p_product_ids) order by id for key share;
  if (select count(*) from public.products where id = any(p_product_ids)) <> cardinality(p_product_ids) then
    raise exception 'Tattoo not found' using errcode = '23503';
  end if;
  insert into public.offers(id, name_ar, price, active)
    values (p_id, btrim(p_name), p_price, p_active)
    on conflict (id) do update set name_ar = excluded.name_ar,
      price = excluded.price, active = excluded.active;
  delete from public.offer_products where offer_id = p_id;
  insert into public.offer_products(offer_id, product_id, position)
    select p_id, id, ordinal - 1 from unnest(p_product_ids) with ordinality as entries(id, ordinal);
  return p_id;
end;
$$;
create function public.delete_catalog_offer(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  delete from public.offers where id = p_id;
end;
$$;
revoke all on function public.save_catalog_offer(uuid, text, integer, uuid[], boolean),
  public.delete_catalog_offer(uuid) from public;
grant execute on function public.save_catalog_offer(uuid, text, integer, uuid[], boolean),
  public.delete_catalog_offer(uuid) to authenticated;
