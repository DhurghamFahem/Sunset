-- Auth Admin createUser may INSERT the login before UPDATEing app metadata.
-- Provision on both events; repeated/irrelevant metadata updates must be harmless.
create or replace function public.provision_employee_account() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  profile jsonb := new.raw_app_meta_data->'employee_profile';
  already_linked boolean;
begin
  if profile is null then return new; end if;
  select exists(select 1 from public.employees where user_id = new.id) into already_linked;
  if tg_op = 'UPDATE' and already_linked and
    profile is not distinct from old.raw_app_meta_data->'employee_profile' then
    return new;
  end if;
  insert into public.employees(id, name, phone, user_id, email)
    values ((profile->>'id')::uuid, trim(profile->>'name'), trim(profile->>'phone'), new.id, lower(new.email))
    on conflict (id) do update set name = excluded.name, phone = excluded.phone,
      user_id = excluded.user_id, email = excluded.email
      where employees.user_id is null or employees.user_id = new.id;
  if not found then raise exception 'Employee already has a login'; end if;
  -- Do not reinstate a revoked role when updating an already-linked profile.
  if not already_linked then
    insert into public.employee_users(user_id) values (new.id) on conflict do nothing;
  end if;
  return new;
end;
$$;
drop trigger provision_employee_account on auth.users;
create trigger provision_employee_account after insert or update of raw_app_meta_data on auth.users
  for each row execute function public.provision_employee_account();

-- Repair valid, server-created logins left without employee profiles by the old
-- insert-only trigger. Never claim an occupied employee ID or alter linked users.
update auth.users u set raw_app_meta_data = u.raw_app_meta_data
where jsonb_typeof(u.raw_app_meta_data->'employee_profile') = 'object'
  and u.raw_app_meta_data->'employee_profile'->>'id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  and length(trim(u.raw_app_meta_data->'employee_profile'->>'name')) between 1 and 120
  and trim(u.raw_app_meta_data->'employee_profile'->>'phone') ~ '^\+?[0-9][0-9 ()-]{6,24}$'
  and u.email is not null
  and not exists(select 1 from public.employees e where e.user_id = u.id)
  and not exists(select 1 from public.employees e
    where e.id::text = lower(u.raw_app_meta_data->'employee_profile'->>'id') and e.user_id is not null)
  and not exists(select 1 from public.employees e where lower(e.email) = lower(u.email)
    and e.id::text <> lower(u.raw_app_meta_data->'employee_profile'->>'id'));

notify pgrst, 'reload schema';
