create or replace function public.update_selection_order(p_id uuid, p_version integer, p_data jsonb, p_token uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  old public.orders; revised public.orders; staff boolean := public.can_manage_orders();
  item jsonb; prior jsonb; normalized jsonb := '[]'; pos integer := 0;
  product public.products;
  quantity integer; accepted integer; original bigint; unit bigint;
  subtotal bigint := 0; pieces integer := 0; accepted_pieces integer := 0; priced boolean := true;
begin
  select * into old from public.orders where id = p_id and (staff or access_token = p_token) for update;
  if not found then raise exception 'ORDER:الطلب غير موجود'; end if;
  if old.version <> p_version then raise exception 'ORDER:تم تعديل الطلب. أغلقه وافتحه لتحديث البيانات'; end if;
  if jsonb_typeof(p_data) is distinct from 'object' then raise exception 'ORDER:بيانات غير صحيحة'; end if;
  if exists(select 1 from jsonb_object_keys(p_data) k where k not in
    ('status','items','delivery_cost','final_total','phone','governorate','area','landmark','delivery_notes','customer_name','username','source','is_paid','prime_state_id','prime_district_id')) then
    raise exception 'ORDER:حقول غير مسموحة';
  end if;
  if not staff and exists(select 1 from jsonb_object_keys(p_data) k where k <> 'status'
      and not (old.status = 'shipped' and k = 'items')) then
    raise exception 'ORDER:إكمال بيانات الطلب متاح للموظفين فقط';
  end if;
  if p_data ? 'is_paid' and jsonb_typeof(p_data->'is_paid') is distinct from 'boolean' then
    raise exception 'ORDER:حالة الدفع غير صحيحة';
  end if;
  revised := jsonb_populate_record(old, p_data);
  if revised.is_paid is distinct from old.is_paid and old.status not in ('pending','confirmed') then
    raise exception 'ORDER:لا يمكن تغيير حالة الدفع بعد الرفع إلى برايم';
  end if;
  -- Legacy clients may still edit address text. Do not retain IDs for an old address.
  if not (p_data ? 'prime_state_id' or p_data ? 'prime_district_id') and
    (revised.governorate is distinct from old.governorate or revised.area is distinct from old.area) then
    revised.prime_state_id := null; revised.prime_district_id := null;
  end if;
  if (revised.prime_state_id is null) <> (revised.prime_district_id is null) or
    (revised.prime_state_id is not null and revised.prime_state_id !~ '^[a-zA-Z0-9_-]{1,30}$') or
    revised.prime_district_id <= 0 then
    raise exception 'ORDER:اختر المحافظة والمنطقة من برايم';
  end if;
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
  if jsonb_typeof(revised.items) is distinct from 'array' or jsonb_array_length(revised.items) not between 1 and 100 then
    raise exception 'ORDER:قطع الطلب غير صحيحة';
  end if;
  if (select count(distinct value->>'product_id') from jsonb_array_elements(revised.items)) <> jsonb_array_length(revised.items) then
    raise exception 'ORDER:وشم مكرر أو غير صحيح';
  end if;
  if old.status = 'shipped' and jsonb_array_length(revised.items) <> jsonb_array_length(old.items) then
    raise exception 'ORDER:تم قفل الطلب بعد الشحن';
  end if;
  for item in select value from jsonb_array_elements(revised.items) loop
    if jsonb_typeof(item) is distinct from 'object' then raise exception 'ORDER:قطع الطلب غير صحيحة'; end if;
    if old.status = 'shipped' then
      prior := old.items->pos;
    else
      select value into prior from jsonb_array_elements(old.items)
        where value->>'product_id' = item->>'product_id';
      if prior is null then
        select p.* into product from public.products p
          where p.id = (item->>'product_id')::uuid and public.catalog_product_visible(p.id);
        if not found then raise exception 'ORDER:بعض الوشومات لم تعد متوفرة'; end if;
        prior := jsonb_build_object('product_id', product.id,
          'name', coalesce(nullif(trim(product.name_ar), ''), product.code),
          'code', product.code, 'original_price', product.price);
      end if;
    end if;
    pos := pos + 1;
    if item->>'product_id' is distinct from prior->>'product_id' or
      item->>'name' is distinct from prior->>'name' or
      coalesce(item->>'code', '') is distinct from coalesce(prior->>'code', '') then
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
  -- A complete staff-created manual order is ready to dispatch when saved.
  -- Keep incomplete drafts and customer-created selections pending.
  if staff and old.created_by is not null and old.status = 'pending' and
    revised.status = 'pending' and priced and
    revised.phone ~ '^\+?[0-9][0-9 ()-]{6,24}$' and
    length(trim(revised.governorate)) > 0 and length(trim(revised.area)) > 0 and
    revised.prime_state_id is not null and revised.prime_district_id is not null then
    revised.status := 'confirmed';
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
    is_paid = revised.is_paid, prime_state_id = revised.prime_state_id, prime_district_id = revised.prime_district_id,
    final_total = revised.final_total, phone = trim(revised.phone), governorate = trim(revised.governorate), area = trim(revised.area),
    landmark = trim(revised.landmark), delivery_notes = trim(revised.delivery_notes),
    customer_name = trim(revised.customer_name), username = trim(revised.username), source = revised.source,
    version = old.version + 1, updated_at = now() where id = p_id;
  insert into public.order_events(order_id, from_status, to_status, version, actor_id, actor_kind)
    values (p_id, old.status, revised.status, old.version + 1, auth.uid(), case when public.is_admin() then 'admin' when staff then 'employee' else 'customer' end);
  return public.get_selection_order(p_id, p_token);
end;
$$;

notify pgrst, 'reload schema';
