-- Enforce digits on new and edited products without rewriting legacy codes.
-- NOT VALID skips existing rows but still checks every insert and update.
alter table public.products
  add constraint products_numeric_code_check
  check (code <> '' and code !~ '[^0-9]') not valid;
