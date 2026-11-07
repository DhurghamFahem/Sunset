-- Main-account credentials use Vault just like employee credentials.
-- Public settings expose only the username and whether a password is stored.
create table private.main_prime_accounts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  username text not null check (length(trim(username)) between 1 and 254),
  password_id uuid not null references vault.secrets(id)
);
revoke all on private.main_prime_accounts from public, anon, authenticated;

create function public.get_main_prime_account() returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise insufficient_privilege; end if;
  return coalesce((select jsonb_build_object('username', a.username, 'configured', true)
    from private.main_prime_accounts a join auth.users u on u.id = a.user_id
    join public.admin_users adm on adm.user_id = u.id
    where lower(u.email) = 'getoge@gmail.com'),
    '{"username":"","configured":false}'::jsonb);
end;
$$;

create function public.save_main_prime_account(p_username text, p_password text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare main_user uuid; secret_id uuid; old_username text;
begin
  if not public.is_admin() then raise insufficient_privilege; end if;
  -- Lock the identity even on first save so concurrent saves cannot orphan secrets.
  select u.id into main_user from auth.users u
    join public.admin_users adm on adm.user_id = u.id
    where lower(u.email) = 'getoge@gmail.com' for update of u;
  if main_user is null then
    raise exception 'ORDER:الحساب الرئيسي getoge@gmail.com غير موجود أو ليس مسؤولاً';
  end if;
  if p_username is null or length(p_username) > 254 or
    (p_password is not null and length(p_password) not between 1 and 256) or
    (trim(p_username) = '' and p_password is not null) then
    raise exception 'ORDER:راجع اسم المستخدم وكلمة مرور برايم';
  end if;
  select username, password_id into old_username, secret_id
    from private.main_prime_accounts where user_id = main_user;
  if trim(p_username) = '' then
    delete from private.main_prime_accounts where user_id = main_user;
    delete from vault.secrets where id = secret_id;
    return;
  end if;
  if p_password is null and (secret_id is null or old_username <> trim(p_username)) then
    raise exception 'ORDER:أدخل كلمة مرور برايم';
  end if;
  if secret_id is null then
    select vault.create_secret(p_password) into secret_id;
    insert into private.main_prime_accounts(user_id, username, password_id)
      values (main_user, trim(p_username), secret_id);
  else
    if p_password is not null then perform vault.update_secret(secret_id, p_password); end if;
    update private.main_prime_accounts set username = trim(p_username) where user_id = main_user;
  end if;
end;
$$;
revoke all on function public.get_main_prime_account(), public.save_main_prime_account(text,text)
  from public, anon, authenticated;
grant execute on function public.get_main_prime_account(), public.save_main_prime_account(text,text)
  to authenticated;

-- Resolve by the immutable creator. Main-account orders must not use the
-- credentials of an employee who happens to edit/confirm them later.
create function private.prime_order_account(p_order_id uuid, p_user_id uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare ord public.orders; uploader uuid;
begin
  select * into ord from public.orders where id = p_order_id;
  if not found then return null; end if;
  if exists(select 1 from auth.users where id = ord.created_by and lower(email) = 'getoge@gmail.com') then
    return (select jsonb_build_object('username', a.username, 'password', s.decrypted_secret)
      from private.main_prime_accounts a join vault.decrypted_secrets s on s.id = a.password_id
      join public.admin_users adm on adm.user_id = a.user_id
      where a.user_id = ord.created_by);
  end if;
  uploader := coalesce(ord.employee_id,
    (select employee_id from private.prime_upload_jobs where order_id = p_order_id),
    (select id from public.employees where user_id = p_user_id));
  return (select jsonb_build_object('username', e.prime_username, 'password', s.decrypted_secret,
      'shop_id', e.prime_shop_id, 'product_id', e.prime_product_id)
    from public.employees e join private.prime_accounts a on a.employee_id = e.id
    join vault.decrypted_secrets s on s.id = a.password_id where e.id = uploader);
end;
$$;
revoke all on function private.prime_order_account(uuid,uuid) from public, anon, authenticated;

create or replace function public.prime_location_account(p_order_id uuid, p_user_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if not exists(select 1 from public.admin_users where user_id = p_user_id) and
     not exists(select 1 from public.employee_users where user_id = p_user_id) then
    raise insufficient_privilege;
  end if;
  return private.prime_order_account(p_order_id, p_user_id);
end;
$$;

create or replace function public.claim_prime_upload() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare candidate record; job private.prime_upload_jobs; ord public.orders; account jsonb;
begin
  for candidate in select order_id from private.prime_upload_jobs
    where (state = 'queued' and next_attempt_at <= now()) or
      (state in ('working','sending') and lease_until <= now())
    order by next_attempt_at limit 50
  loop
    select * into ord from public.orders where id = candidate.order_id for update skip locked;
    if not found then continue; end if;
    select * into job from private.prime_upload_jobs where order_id = ord.id for update skip locked;
    if not found then continue; end if;
    if job.state = 'sending' and job.lease_until <= now() then
      -- A terminated worker may have already created a shipment. Never blindly
      -- repeat an ambiguous POST until Prime's deduplication contract is known.
      update private.prime_upload_jobs set state = 'review', last_error = 'ambiguous_upload' where order_id = ord.id;
      continue;
    end if;
    if not ((job.state = 'queued' and job.next_attempt_at <= now()) or
      (job.state = 'working' and job.lease_until <= now())) then continue; end if;
    if ord.status <> 'confirmed' then
      update private.prime_upload_jobs set state = 'cancelled' where order_id = ord.id;
      continue;
    end if;
    if job.attempts >= 5 then
      update private.prime_upload_jobs set state = 'failed', last_error = 'attempts_exhausted' where order_id = ord.id;
      continue;
    end if;
    update private.prime_upload_jobs set state = 'working', attempts = attempts + 1,
      claim_token = gen_random_uuid(), lease_until = now() + interval '2 minutes',
      order_version = ord.version where order_id = ord.id returning * into job;
    account := private.prime_order_account(ord.id);
    return jsonb_build_object('order', to_jsonb(ord) - 'access_token',
      'claim_token', job.claim_token, 'attempt', job.attempts,
      'username', account->>'username', 'password', account->>'password',
      'shop_id', account->'shop_id', 'product_id', account->'product_id');
  end loop;
  return null;
end;
$$;


revoke all on function public.prime_location_account(uuid,uuid), public.claim_prime_upload()
  from public, anon, authenticated;
grant execute on function public.prime_location_account(uuid,uuid), public.claim_prime_upload()
  to service_role;
notify pgrst, 'reload schema';
