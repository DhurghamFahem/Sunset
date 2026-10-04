-- Remove the former G2G prefix requirement.
alter table public.products drop constraint if exists products_code_check;
