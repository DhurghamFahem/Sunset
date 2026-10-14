-- Keep category originals and lightweight previews independently, like tattoos.
alter table public.categories
  add column thumbnail_url text
    check (thumbnail_url is null or thumbnail_url ~ '^https?://');

-- Both objects use the existing category bucket and its admin-only write policy.
update storage.buckets set file_size_limit = 10485760
where id = 'category-images';

notify pgrst, 'reload schema';
