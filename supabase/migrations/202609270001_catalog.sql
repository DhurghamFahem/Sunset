-- G2G catalog. Customer selections never leave the customer's device.
create extension if not exists pg_trgm with schema extensions;

create table public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.admin_users enable row level security;
-- No client can grant itself administrator privileges.
revoke all on public.admin_users from anon, authenticated;

create function public.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.admin_users where user_id = (select auth.uid()));
$$;
revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to anon, authenticated;

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  name_ar text not null check (length(trim(name_ar)) between 1 and 120),
  name_en text,
  image_url text check (image_url is null or image_url ~ '^https?://'),
  sort_order integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.products (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^G2G-[0-9]{3,}$'),
  name_ar text check (name_ar is null or length(name_ar) <= 160),
  name_en text,
  category_id uuid not null references public.categories(id) on delete restrict,
  image_url text not null check (image_url ~ '^https?://'),
  thumbnail_url text check (thumbnail_url is null or thumbnail_url ~ '^https?://'),
  width_cm numeric(8,2) check (width_cm > 0),
  height_cm numeric(8,2) check (height_cm > 0),
  area_cm2 numeric generated always as (width_cm * height_cm) stored,
  price integer check (price >= 0),
  active boolean not null default true,
  featured boolean not null default false,
  is_new boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
-- code's UNIQUE constraint already creates its btree index.
create index products_category_id_idx on public.products(category_id);
create index products_active_idx on public.products(active);
create index products_featured_idx on public.products(featured);
create index products_is_new_idx on public.products(is_new);
create index products_sort_order_idx on public.products(sort_order, id);
create index products_catalog_idx on public.products(category_id, sort_order, id) where active;
create index products_created_at_idx on public.products(created_at desc, id) where active;
create index products_price_idx on public.products(price, id) where active;
create index products_area_idx on public.products(area_cm2, id) where active;
create index products_code_search_idx on public.products using gin(code extensions.gin_trgm_ops);
create index products_name_search_idx on public.products using gin(name_ar extensions.gin_trgm_ops);
create index categories_active_idx on public.categories(active);
create index categories_sort_order_idx on public.categories(sort_order, id);

create function public.touch_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin new.updated_at = now(); return new; end;
$$;
create trigger categories_updated before update on public.categories for each row execute function public.touch_updated_at();
create trigger products_updated before update on public.products for each row execute function public.touch_updated_at();

alter table public.categories enable row level security;
alter table public.products enable row level security;
grant select on public.categories, public.products to anon;
grant select, insert, update, delete on public.categories, public.products to authenticated;

create policy categories_public_read on public.categories for select to anon, authenticated using (active);
create policy categories_admin on public.categories for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));
create policy products_public_read on public.products for select to anon, authenticated using (
  active and exists(select 1 from public.categories c where c.id = category_id and c.active)
);
create policy products_admin on public.products for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types) values
  ('tattoo-images', 'tattoo-images', true, 10485760, array['image/png','image/jpeg','image/webp']),
  ('tattoo-thumbnails', 'tattoo-thumbnails', true, 2097152, array['image/png','image/jpeg','image/webp']),
  ('category-images', 'category-images', true, 2097152, array['image/png','image/jpeg','image/webp']);
-- Public buckets serve image bytes; database availability controls discovery.
create policy catalog_images_read on storage.objects for select to anon, authenticated
  using (bucket_id in ('tattoo-images','tattoo-thumbnails','category-images'));
create policy catalog_images_insert on storage.objects for insert to authenticated
  with check (bucket_id in ('tattoo-images','tattoo-thumbnails','category-images') and (select public.is_admin()));
create policy catalog_images_update on storage.objects for update to authenticated
  using (bucket_id in ('tattoo-images','tattoo-thumbnails','category-images') and (select public.is_admin()))
  with check (bucket_id in ('tattoo-images','tattoo-thumbnails','category-images') and (select public.is_admin()));
create policy catalog_images_delete on storage.objects for delete to authenticated
  using (bucket_id in ('tattoo-images','tattoo-thumbnails','category-images') and (select public.is_admin()));
