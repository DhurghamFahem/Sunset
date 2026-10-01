-- Tag choices come only from publicly visible inventory, including when an
-- administrator is browsing the customer site. The array filter matches any
-- selected tag and combines with all other catalog filters.
create index products_tags_idx on public.products using gin(tags);
create function public.catalog_available_tags() returns setof text
language sql stable security invoker set search_path = '' as $$
  select distinct tag
  from public.catalog_products p cross join lateral unnest(p.tags) tag
  where p.public_visible
  order by tag;
$$;
revoke all on function public.catalog_available_tags() from public;
grant execute on function public.catalog_available_tags() to anon, authenticated;
notify pgrst, 'reload schema';
