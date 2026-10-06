-- A customer capability may select only a sharing destination while pending.
-- Keep customer details, prices and confirmation restricted to staff.
create function public.set_order_share_source(p_id uuid, p_token uuid, p_source text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare old public.orders;
begin
  select * into old from public.orders
    where id = p_id and access_token = p_token for update;
  if not found then raise exception 'ORDER:الطلب غير موجود'; end if;
  if p_source is null or p_source not in ('instagram', 'whatsapp') then
    raise exception 'ORDER:اختر Instagram أو WhatsApp';
  end if;
  if old.status <> 'pending' then
    raise exception 'ORDER:تم تأكيد الطلب. تغيير المصدر متاح للموظفين فقط';
  end if;
  if old.source is distinct from p_source then
    update public.orders set source = p_source, version = old.version + 1,
      updated_at = now() where id = p_id;
    insert into public.order_events(order_id, from_status, to_status, version, actor_id, actor_kind)
      values (p_id, old.status, old.status, old.version + 1, auth.uid(), 'customer');
  end if;
  return public.get_selection_order(p_id, p_token);
end;
$$;
revoke all on function public.set_order_share_source(uuid, uuid, text) from public;
grant execute on function public.set_order_share_source(uuid, uuid, text) to anon, authenticated;
notify pgrst, 'reload schema';
