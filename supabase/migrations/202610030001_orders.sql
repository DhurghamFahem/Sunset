-- Orders are private. Public customers use an unguessable, device-held UUID
-- capability; the four-character printed code is NEVER an access credential.
create table public.employees (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 1 and 120),
  phone text not null check (phone ~ '^\+?[0-9][0-9 ()-]{6,24}$')
);
create table public.order_settings (
  id boolean primary key default true check (id),
  delivery_cost integer not null default 0 check (delivery_cost between 0 and 100000000)
);
insert into public.order_settings default values;
create table public.order_code_reservations (
  code text primary key check (code ~ '^[A-Z0-9]{4}$'),
  reserved_at timestamptz not null
);
create table public.orders (
  id uuid primary key default gen_random_uuid(),
  access_token uuid not null unique,
  code text not null references public.order_code_reservations(code),
  status text not null default 'pending' check (status in ('pending','confirmed','packed','shipped','delivered','partial','rejected','cancelled')),
  items jsonb not null check (jsonb_typeof(items) = 'array' and jsonb_array_length(items) between 1 and 100),
  delivery_cost integer not null check (delivery_cost between 0 and 100000000),
  final_total bigint check (final_total >= 0),
  phone text not null default '' check (length(phone) <= 26),
  governorate text not null default '' check (length(governorate) <= 120),
  area text not null default '' check (length(area) <= 300),
  customer_name text not null default '' check (length(customer_name) <= 120),
  username text not null default '' check (length(username) <= 120),
  source text not null default 'website' check (source in ('instagram','whatsapp','tiktok','facebook','website','other')),
  employee_id uuid references public.employees(id) on delete restrict,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index orders_recent on public.orders(created_at desc, id);
create index orders_code on public.orders(code, created_at desc);
create index orders_status on public.orders(status, created_at desc);
create index orders_employee on public.orders(employee_id);
create table public.order_events (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.orders(id),
  from_status text,
  to_status text not null,
  version integer not null,
  actor_id uuid,
  actor_kind text not null,
  created_at timestamptz not null default now()
);
alter table public.employees enable row level security;
alter table public.order_settings enable row level security;
alter table public.orders enable row level security;
alter table public.order_code_reservations enable row level security;
alter table public.order_events enable row level security;
revoke all on public.orders, public.order_events, public.order_code_reservations from anon, authenticated;
revoke all on public.employees, public.order_settings from anon, authenticated;
grant select on public.order_events to authenticated;
grant select, insert, update on public.employees to authenticated;
grant select on public.order_settings to anon, authenticated;
grant update on public.order_settings to authenticated;
create policy employees_admin on public.employees for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy settings_read on public.order_settings for select to anon, authenticated using (true);
create policy settings_admin on public.order_settings for update to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy events_admin on public.order_events for select to authenticated using ((select public.is_admin()));

create function public.get_selection_order(p_id uuid, p_token uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare result jsonb;
begin
  select to_jsonb(o) - 'access_token' into result from public.orders o
    where o.id = p_id and (public.is_admin() or o.access_token = p_token);
  if result is null then raise exception 'ORDER:الطلب غير موجود'; end if;
  return result;
end;
$$;

create function public.create_selection_order(p_token uuid, p_items jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  order_id uuid; code_value text; alphabet constant text := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  snapshot jsonb; row_count integer; distinct_count integer; claimed text; bytes bytea;
begin
  if p_token is null or jsonb_typeof(p_items) is distinct from 'array'
    or jsonb_array_length(p_items) not between 1 and 100 then
    raise exception 'ORDER:اختيارات غير صحيحة';
  end if;
  -- A retry on any device is atomic and returns the same order.
  perform pg_advisory_xact_lock(hashtextextended(p_token::text, 0));
  select id into order_id from public.orders where access_token = p_token;
  if found then return public.get_selection_order(order_id, p_token); end if;
  if exists(select 1 from jsonb_array_elements(p_items) i where
    coalesce((i->>'quantity')::numeric, 0) not between 1 and 99 or
    (i->>'quantity')::numeric <> trunc((i->>'quantity')::numeric)) then
    raise exception 'ORDER:الكمية يجب أن تكون من 1 إلى 99';
  end if;
  select count(*), count(distinct i->>'product_id') into row_count, distinct_count from jsonb_array_elements(p_items) i;
  if row_count <> distinct_count then raise exception 'ORDER:وشم مكرر'; end if;
  select jsonb_agg(jsonb_build_object('product_id', p.id, 'name', p.name_ar,
    'quantity', (i->>'quantity')::integer, 'original_price', p.price, 'unit_price', p.price,
    'accepted_quantity', 0) order by ord) into snapshot
    from jsonb_array_elements(p_items) with ordinality as x(i, ord)
    join public.products p on p.id = (i->>'product_id')::uuid
    where public.catalog_product_visible(p.id);
  if coalesce(jsonb_array_length(snapshot), 0) <> row_count then
    raise exception 'ORDER:بعض الوشومات لم تعد متوفرة';
  end if;
  for attempt in 1..200 loop
    bytes := extensions.gen_random_bytes(4);
    code_value := '';
    -- Rejection sampling keeps each of the 36 characters equally likely.
    for n in 0..3 loop
      while get_byte(bytes, n) >= 252 loop bytes := set_byte(bytes, n, get_byte(extensions.gen_random_bytes(1), 0)); end loop;
      code_value := code_value || substr(alphabet, (get_byte(bytes, n) % 36) + 1, 1);
    end loop;
    claimed := null;
    insert into public.order_code_reservations as r(code, reserved_at) values (code_value, clock_timestamp())
      on conflict (code) do update set reserved_at = excluded.reserved_at
      where r.reserved_at <= clock_timestamp() - interval '30 days'
        and not exists (select 1 from public.orders o where o.code = r.code and o.status in ('pending','confirmed','packed','shipped'))
      returning code into claimed;
    exit when claimed is not null;
  end loop;
  if claimed is null then raise exception 'ORDER:تعذر تخصيص رمز. حاول مرة ثانية'; end if;
  insert into public.orders(access_token, code, items, delivery_cost)
    values (p_token, code_value, snapshot, (select delivery_cost from public.order_settings where id)) returning id into order_id;
  insert into public.order_events(order_id, to_status, version, actor_id, actor_kind)
    values (order_id, 'pending', 1, auth.uid(), 'customer');
  return public.get_selection_order(order_id, p_token);
end;
$$;

create function public.update_selection_order(p_id uuid, p_version integer, p_data jsonb, p_token uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  old public.orders; revised public.orders; staff boolean := public.is_admin();
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
  if not staff and exists(select 1 from jsonb_object_keys(p_data) k where k not in
    ('status','phone','governorate','area','customer_name','username','source')
      and not (old.status = 'shipped' and k = 'items')) then
    raise exception 'ORDER:غير مسموح بتعديل الأسعار';
  end if;
  revised := jsonb_populate_record(old, p_data);
  if revised.status is null or (revised.status <> old.status and not (
    (old.status = 'pending' and revised.status in ('confirmed','cancelled')) or
    (old.status = 'confirmed' and revised.status in ('packed','cancelled')) or
    (old.status = 'packed' and revised.status in ('shipped','cancelled')) or
    (old.status = 'shipped' and revised.status in ('delivered','partial','rejected')))) then
    raise exception 'ORDER:تغيير الحالة غير مسموح';
  end if;
  if not staff and not ((old.status = 'pending' and revised.status = 'confirmed') or
    (old.status in ('pending','confirmed','packed') and revised.status = 'cancelled') or
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
    normalized := normalized || jsonb_build_array(jsonb_build_object('product_id', prior->>'product_id', 'name', prior->>'name',
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
    values (p_id, old.status, revised.status, old.version + 1, auth.uid(), case when staff then 'admin' else 'customer' end);
  return public.get_selection_order(p_id, p_token);
end;
$$;

create function public.list_selection_orders(p_search text default '', p_status text default null, p_offset integer default 0)
returns setof jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'Administrator access required' using errcode = '42501'; end if;
  return query select to_jsonb(o) - 'access_token' from public.orders o
    where (p_status is null or o.status = p_status)
    and (coalesce(p_search, '') = '' or position(lower(p_search) in lower(o.code || ' ' || o.phone || ' ' || o.customer_name || ' ' || o.username)) > 0)
    order by o.created_at desc, o.id limit 50 offset greatest(p_offset, 0);
end;
$$;

create function public.order_employee_performance() returns setof jsonb
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
  ), people as (select id, name from public.employees union all select null::uuid, 'بدون موظف')
  select jsonb_build_object('name', p.name, 'orders', count(t.id),
    'fulfilled', count(t.id) filter (where t.status in ('delivered','partial')),
    'accepted_pieces', coalesce(sum(t.accepted_pieces), 0),
    'revenue', coalesce(sum(case when t.accepted_pieces > 0 then least(t.total, t.delivery_cost) +
      coalesce(round((t.total - least(t.total, t.delivery_cost))::numeric * t.accepted_subtotal / nullif(t.subtotal, 0)), 0)
      else 0 end), 0))
    from people p left join totals t on t.employee_id is not distinct from p.id group by p.id, p.name;
end;
$$;

revoke all on function public.get_selection_order(uuid, uuid), public.create_selection_order(uuid, jsonb),
  public.update_selection_order(uuid, integer, jsonb, uuid), public.list_selection_orders(text, text, integer),
  public.order_employee_performance() from public;
grant execute on function public.get_selection_order(uuid, uuid), public.create_selection_order(uuid, jsonb),
  public.update_selection_order(uuid, integer, jsonb, uuid) to anon, authenticated;
grant execute on function public.list_selection_orders(text, text, integer), public.order_employee_performance() to authenticated;
notify pgrst, 'reload schema';
