-- Employee logins are separate from fulfillment assignees and administrators.
-- Only trusted database administration may change this allowlist.
create table public.employee_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.employee_users enable row level security;
revoke all on public.employee_users from public, anon, authenticated;

create function public.can_manage_orders() returns boolean
language sql stable security definer set search_path = '' as $$
  select public.is_admin() or exists (
    select 1 from public.employee_users where user_id = (select auth.uid())
  );
$$;
revoke all on function public.can_manage_orders() from public;
grant execute on function public.can_manage_orders() to anon, authenticated;

-- Order assignment requires the existing employee picker, never team writes.
create policy employees_order_staff_read on public.employees
  for select to authenticated using ((select public.can_manage_orders()));
create policy events_order_staff_read on public.order_events
  for select to authenticated using ((select public.can_manage_orders()));

create or replace function public.get_selection_order(p_id uuid, p_token uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare result jsonb;
begin
  select to_jsonb(o) - 'access_token' into result from public.orders o
    where o.id = p_id and (public.can_manage_orders() or o.access_token = p_token);
  if result is null then raise exception 'ORDER:الطلب غير موجود'; end if;
  return result;
end;
$$;

create or replace function public.list_selection_orders(p_search text default '', p_status text default null, p_offset integer default 0)
returns setof jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.can_manage_orders() then raise exception 'Order staff access required' using errcode = '42501'; end if;
  return query select to_jsonb(o) - 'access_token' from public.orders o
    where (p_status is null or o.status = p_status)
    and (coalesce(p_search, '') = '' or position(lower(p_search) in lower(o.code || ' ' || o.phone || ' ' || o.customer_name || ' ' || o.username)) > 0)
    order by o.created_at desc, o.id limit 50 offset greatest(p_offset, 0);
end;
$$;

create or replace function public.update_selection_order(p_id uuid, p_version integer, p_data jsonb, p_token uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  old public.orders; revised public.orders; staff boolean := public.can_manage_orders();
  item jsonb; prior jsonb; normalized jsonb := '[]'; pos integer := 0;
  quantity integer; accepted integer; original bigint; unit bigint;
  subtotal bigint := 0; pieces integer := 0; accepted_pieces integer := 0; priced boolean := true;
begin
  select * into old from public.orders where id = p_id and (staff or access_token = p_token) for update;
  if not found then raise exception 'ORDER:الطلب غير موجود'; end if;
  if old.version <> p_version then raise exception 'ORDER:تم تعديل الطلب. أغلقه وافتحه لتحديث البيانات'; end if;
  if jsonb_typeof(p_data) is distinct from 'object' then raise exception 'ORDER:بيانات غير صحيحة'; end if;
  if exists(select 1 from jsonb_object_keys(p_data) k where k not in
    ('status','items','delivery_cost','final_total','phone','governorate','area','customer_name','username','source','employee_id')) then
    raise exception 'ORDER:حقول غير مسموحة';
  end if;
  if not staff and exists(select 1 from jsonb_object_keys(p_data) k where k <> 'status'
      and not (old.status = 'shipped' and k = 'items')) then
    raise exception 'ORDER:إكمال بيانات الطلب متاح للموظفين فقط';
  end if;
  revised := jsonb_populate_record(old, p_data);
  if revised.status is null or (revised.status <> old.status and not (
    (old.status = 'pending' and revised.status in ('confirmed','cancelled')) or
    (old.status = 'confirmed' and revised.status in ('packed','cancelled')) or
    (old.status = 'packed' and revised.status in ('shipped','cancelled')) or
    (old.status = 'shipped' and revised.status in ('delivered','partial','rejected')))) then
    raise exception 'ORDER:تغيير الحالة غير مسموح';
  end if;
  if not staff and not ((old.status in ('pending','confirmed','packed') and revised.status = 'cancelled') or
    (old.status = 'shipped' and revised.status in ('delivered','partial','rejected'))) then
    raise exception 'ORDER:تغيير الحالة غير مسموح';
  end if;
  if old.status in ('delivered','partial','rejected','cancelled') then raise exception 'ORDER:الطلب مغلق'; end if;
  if old.status = 'shipped' and exists(select 1 from jsonb_object_keys(p_data) k where k not in ('status','items')) then
    raise exception 'ORDER:تم قفل الطلب بعد الشحن';
  end if;
  if jsonb_typeof(revised.items) is distinct from 'array' or jsonb_array_length(revised.items) <> jsonb_array_length(old.items) then
    raise exception 'ORDER:قطع الطلب غير صحيحة';
  end if;
  for item in select value from jsonb_array_elements(revised.items) loop
    prior := old.items->pos; pos := pos + 1;
    if item->>'product_id' is distinct from prior->>'product_id' or item->>'name' is distinct from prior->>'name' then
      raise exception 'ORDER:قطع الطلب غير صحيحة';
    end if;
    -- All currency and counts use whole units. Reject fractional JSON values.
    if exists(select 1 from jsonb_each(item) e where e.key in ('quantity','accepted_quantity','original_price','unit_price')
      and e.value <> 'null'::jsonb and (e.value #>> '{}')::numeric <> trunc((e.value #>> '{}')::numeric)) then
      raise exception 'ORDER:استخدم أرقاماً صحيحة للكميات والأسعار';
    end if;
    quantity := (item->>'quantity')::integer;
    accepted := coalesce((item->>'accepted_quantity')::integer, 0);
    original := (item->>'original_price')::bigint; unit := (item->>'unit_price')::bigint;
    if quantity is null or quantity not between 1 and 99 or accepted not between 0 and quantity or
      (original is not null and original not between 0 and 100000000) or
      (unit is not null and (original is null or unit not between 0 and original)) then
      raise exception 'ORDER:راجع الكميات والأسعار';
    end if;
    if prior->>'original_price' is not null and item->>'original_price' is distinct from prior->>'original_price' then
      raise exception 'ORDER:السعر الأصلي محفوظ ولا يمكن تغييره';
    end if;
    if old.status = 'shipped' and (quantity <> (prior->>'quantity')::integer or
      unit is distinct from (prior->>'unit_price')::bigint or original is distinct from (prior->>'original_price')::bigint) then
      raise exception 'ORDER:تم قفل الأسعار والكميات بعد الشحن';
    end if;
    if revised.status = 'delivered' then accepted := quantity;
    elsif revised.status = 'rejected' then accepted := 0;
    elsif revised.status <> 'partial' and accepted <> 0 then raise exception 'ORDER:سجل الاستلام بعد الشحن فقط'; end if;
    priced := priced and original is not null and unit is not null;
    subtotal := subtotal + coalesce(unit, 0) * quantity;
    pieces := pieces + quantity; accepted_pieces := accepted_pieces + accepted;
    normalized := normalized || jsonb_build_array(jsonb_build_object('product_id', prior->>'product_id', 'name', prior->>'name', 'code', prior->>'code',
      'quantity', quantity, 'original_price', original, 'unit_price', unit, 'accepted_quantity', accepted));
  end loop;
  if revised.status = 'partial' and (accepted_pieces <= 0 or accepted_pieces >= pieces) then
    raise exception 'ORDER:حدد القطع المستلمة: أكثر من صفر وأقل من كامل الطلب';
  end if;
  if revised.delivery_cost is null or revised.delivery_cost not between 0 and 100000000 or
    revised.final_total is not null and revised.final_total not between 0 and subtotal + revised.delivery_cost then
    raise exception 'ORDER:المبلغ النهائي يجب ألا يتجاوز المجموع بعد خصم القطع';
  end if;
  if revised.status not in ('pending','cancelled') and (not priced or
    revised.phone is null or revised.phone !~ '^\+?[0-9][0-9 ()-]{6,24}$' or
    coalesce(length(trim(revised.governorate)), 0) = 0 or coalesce(length(trim(revised.area)), 0) = 0) then
    raise exception 'ORDER:أكمل الهاتف والمحافظة والمنطقة وأسعار القطع قبل التأكيد';
  end if;
  update public.orders set status = revised.status, items = normalized, delivery_cost = revised.delivery_cost,
    final_total = revised.final_total, phone = trim(revised.phone), governorate = trim(revised.governorate), area = trim(revised.area),
    customer_name = trim(revised.customer_name), username = trim(revised.username), source = revised.source,
    employee_id = revised.employee_id, version = old.version + 1, updated_at = now() where id = p_id;
  insert into public.order_events(order_id, from_status, to_status, version, actor_id, actor_kind)
    values (p_id, old.status, revised.status, old.version + 1, auth.uid(), case when public.is_admin() then 'admin' when staff then 'employee' else 'customer' end);
  return public.get_selection_order(p_id, p_token);
end;
$$;

create or replace function public.create_manual_order(p_token uuid, p_items jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare result jsonb; existing_id uuid;
begin
  if not public.can_manage_orders() then
    raise insufficient_privilege using message = 'Order staff access required';
  end if;
  if p_token is null then raise exception 'ORDER:اختيارات غير صحيحة'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_token::text, 0));
  select id into existing_id from public.orders where access_token = p_token;
  if found then return public.get_selection_order(existing_id); end if;
  result := public.create_selection_order(p_token, p_items);
  update public.order_events set actor_kind = case when public.is_admin() then 'admin' else 'employee' end, actor_id = auth.uid()
    where order_id = (result->>'id')::uuid and version = 1;
  return result;
end;
$$;

notify pgrst, 'reload schema';
