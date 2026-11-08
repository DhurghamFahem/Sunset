-- Exact carrier-ID lookup is staff-only and independent of order-list pagination.
create index orders_prime_case_id_idx on public.orders (prime_case_id)
  where prime_case_id is not null;

create function public.get_order_by_prime_case_id(p_case_id text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare matches uuid[];
begin
  if not public.can_manage_orders() then
    raise insufficient_privilege using message = 'Order staff access required';
  end if;
  if nullif(trim(p_case_id), '') is null then
    raise exception 'ORDER:أدخل رقم حالة برايم';
  end if;
  select array_agg(id) into matches from (
    select id from public.orders where prime_case_id = trim(p_case_id) limit 2
  ) found_orders;
  if coalesce(cardinality(matches), 0) = 0 then
    raise exception 'ORDER:لا يوجد طلب بهذا الرقم في برايم';
  end if;
  -- Never choose an arbitrary order if carrier accounts return duplicate IDs.
  if cardinality(matches) > 1 then
    raise exception 'ORDER:رقم برايم مرتبط بأكثر من طلب. راجع الإدارة';
  end if;
  return public.get_selection_order(matches[1]);
end;
$$;

revoke all on function public.get_order_by_prime_case_id(text) from public, anon, authenticated;
grant execute on function public.get_order_by_prime_case_id(text) to authenticated;
notify pgrst, 'reload schema';
