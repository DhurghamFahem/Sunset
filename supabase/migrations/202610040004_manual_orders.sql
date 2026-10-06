-- Staff can start an order without a customer browser or image export.
-- Reuse the catalog snapshots, quantity limits and atomic code allocation.
create function public.create_manual_order(p_token uuid, p_items jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare result jsonb; existing_id uuid;
begin
  if not public.is_admin() then
    raise insufficient_privilege using message = 'Admin access required';
  end if;
  if p_token is null then raise exception 'ORDER:اختيارات غير صحيحة'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_token::text, 0));
  select id into existing_id from public.orders where access_token = p_token;
  if found then return public.get_selection_order(existing_id); end if;
  result := public.create_selection_order(p_token, p_items);
  update public.order_events set actor_kind = 'admin', actor_id = auth.uid()
    where order_id = (result->>'id')::uuid and version = 1;
  return result;
end;
$$;
revoke all on function public.create_manual_order(uuid, jsonb) from public, anon;
grant execute on function public.create_manual_order(uuid, jsonb) to authenticated;
notify pgrst, 'reload schema';
