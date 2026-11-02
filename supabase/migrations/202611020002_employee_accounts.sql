-- Auth owns passwords. This table only holds the linked login identity.
alter table public.employees
  add column user_id uuid unique references auth.users(id) on delete set null,
  add column email text not null default '';
create unique index employees_login_email on public.employees(lower(email)) where email <> '';
revoke insert, update on public.employees from authenticated;
drop policy employees_order_staff_read on public.employees;

-- Only the server Auth Admin API can set raw_app_meta_data. Provisioning in
-- the Auth transaction avoids a login without its employee record/permissions.
create function public.provision_employee_account() returns trigger
language plpgsql security definer set search_path = '' as $$
declare profile jsonb := new.raw_app_meta_data->'employee_profile';
begin
  if profile is null then return new; end if;
  insert into public.employees(id, name, phone, user_id, email)
    values ((profile->>'id')::uuid, trim(profile->>'name'), trim(profile->>'phone'), new.id, lower(new.email))
    on conflict (id) do update set name = excluded.name, phone = excluded.phone,
      user_id = excluded.user_id, email = excluded.email
      where employees.user_id is null;
  if not found then raise exception 'Employee already has a login'; end if;
  insert into public.employee_users(user_id) values (new.id);
  return new;
end;
$$;
revoke all on function public.provision_employee_account() from public;
create trigger provision_employee_account after insert on auth.users
  for each row execute function public.provision_employee_account();

create function public.update_employee_profile(p_id uuid, p_name text, p_phone text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise insufficient_privilege using message = 'Administrator access required'; end if;
  update public.employees set name = trim(p_name), phone = trim(p_phone) where id = p_id;
  if not found then raise exception 'Employee not found'; end if;
end;
$$;
revoke all on function public.update_employee_profile(uuid, text, text) from public;
grant execute on function public.update_employee_profile(uuid, text, text) to authenticated;

alter table public.orders add column created_by uuid,
  add column created_by_name text not null default 'غير معروف (طلب سابق)';
-- Use creation events only. A previous assignment is not proof of authorship.
update public.orders o set created_by = e.actor_id,
  created_by_name = case when e.actor_kind = 'customer' then 'الزبون'
    when e.actor_kind = 'admin' then 'الإدارة'
    else coalesce((select name from public.employees where user_id = e.actor_id), 'موظف') end
from public.order_events e where e.order_id = o.id and e.version = 1;

create function public.stamp_order_creator() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    new.created_by := null;
    new.employee_id := null;
    new.created_by_name := 'الزبون';
    if public.can_manage_orders() then
      new.created_by := auth.uid();
      select id, name into new.employee_id, new.created_by_name
        from public.employees where user_id = auth.uid();
      new.created_by_name := coalesce(new.created_by_name,
        case when public.is_admin() then 'الإدارة' else 'موظف' end);
    end if;
  elsif new.created_by is distinct from old.created_by or
        new.created_by_name is distinct from old.created_by_name or
        new.employee_id is distinct from old.employee_id then
    raise exception 'ORDER:لا يمكن تغيير منشئ الطلب';
  end if;
  return new;
end;
$$;
revoke all on function public.stamp_order_creator() from public;
create trigger stamp_order_creator before insert or update on public.orders
  for each row execute function public.stamp_order_creator();

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
    ('status','items','delivery_cost','final_total','phone','governorate','area','landmark','delivery_notes','customer_name','username','source')) then
    raise exception 'ORDER:حقول غير مسموحة';
  end if;
  if not staff and exists(select 1 from jsonb_object_keys(p_data) k where k <> 'status'
      and not (old.status = 'shipped' and k = 'items')) then
    raise exception 'ORDER:إكمال بيانات الطلب متاح للموظفين فقط';
  end if;
  revised := jsonb_populate_record(old, p_data);
  if revised.status is null or (revised.status <> old.status and not (
    (old.status = 'pending' and revised.status in ('confirmed','cancelled')) or
    (old.status = 'confirmed' and revised.status in ('uploaded','cancelled')) or
    (old.status = 'uploaded' and revised.status in ('packed','cancelled')) or
    (old.status = 'packed' and revised.status in ('shipped','cancelled')) or
    (old.status = 'shipped' and revised.status in ('delivered','partial','rejected')))) then
    raise exception 'ORDER:تغيير الحالة غير مسموح';
  end if;
  if not staff and not ((old.status in ('pending','confirmed','uploaded','packed') and revised.status = 'cancelled') or
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
  if revised.landmark is null or length(revised.landmark) > 300 or
    revised.delivery_notes is null or length(revised.delivery_notes) > 1000 then
    raise exception 'ORDER:النقطة الدالة أو ملاحظات المندوب طويلة جداً';
  end if;
  update public.orders set status = revised.status, items = normalized, delivery_cost = revised.delivery_cost,
    final_total = revised.final_total, phone = trim(revised.phone), governorate = trim(revised.governorate), area = trim(revised.area),
    landmark = trim(revised.landmark), delivery_notes = trim(revised.delivery_notes),
    customer_name = trim(revised.customer_name), username = trim(revised.username), source = revised.source,
    version = old.version + 1, updated_at = now() where id = p_id;
  insert into public.order_events(order_id, from_status, to_status, version, actor_id, actor_kind)
    values (p_id, old.status, revised.status, old.version + 1, auth.uid(), case when public.is_admin() then 'admin' when staff then 'employee' else 'customer' end);
  return public.get_selection_order(p_id, p_token);
end;
$$;

create or replace function public.order_employee_performance() returns setof jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'Administrator access required' using errcode = '42501'; end if;
  return query
  with totals as (
    select o.*, t.accepted_pieces, t.subtotal, t.accepted_subtotal,
      coalesce(o.final_total, t.subtotal + o.delivery_cost) as total
    from public.orders o cross join lateral (
      select sum((i->>'quantity')::bigint * coalesce((i->>'unit_price')::bigint, 0)) as subtotal,
        sum((i->>'accepted_quantity')::integer) as accepted_pieces,
        sum((i->>'accepted_quantity')::bigint * coalesce((i->>'unit_price')::bigint, 0)) as accepted_subtotal
      from jsonb_array_elements(o.items) i
    ) t
  ), people as (select id, user_id, name from public.employees union all select null::uuid, null::uuid, 'الزبون / الإدارة / غير مرتبط')
  select jsonb_build_object('name', p.name, 'orders', count(t.id),
    'fulfilled', count(t.id) filter (where t.status in ('delivered','partial')),
    'accepted_pieces', coalesce(sum(t.accepted_pieces), 0),
    'revenue', coalesce(sum(case when t.accepted_pieces > 0 then least(t.total, t.delivery_cost) +
      coalesce(round((t.total - least(t.total, t.delivery_cost))::numeric * t.accepted_subtotal / nullif(t.subtotal, 0)), 0)
      else 0 end), 0))
    from people p left join totals t on ((p.user_id is not null and t.created_by = p.user_id) or (p.id is null and not exists (select 1 from public.employees e where e.user_id = t.created_by))) group by p.id, p.name;
end;
$$;

notify pgrst, 'reload schema';
