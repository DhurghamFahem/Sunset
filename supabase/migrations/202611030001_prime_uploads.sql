-- Credentials are encrypted by Vault and never returned by employee/order APIs.
create extension if not exists supabase_vault with schema vault;
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
alter table public.employees add column prime_username text not null default '',
  add column prime_configured boolean not null default false,
  add column prime_shop_id integer check (prime_shop_id > 0),
  add column prime_product_id integer check (prime_product_id > 0);
create table private.prime_accounts (
  employee_id uuid primary key references public.employees(id) on delete cascade,
  password_id uuid not null references vault.secrets(id)
);
create table private.prime_upload_jobs (
  order_id uuid primary key references public.orders(id),
  employee_id uuid references public.employees(id),
  state text not null default 'queued' check (state in
    ('queued','working','sending','succeeded','failed','review','cancelled')),
  attempts integer not null default 0 check (attempts between 0 and 5),
  next_attempt_at timestamptz not null default now(),
  lease_until timestamptz,
  claim_token uuid,
  order_version integer,
  remote_id text,
  last_error text,
  created_at timestamptz not null default now()
);
revoke all on all tables in schema private from public, anon, authenticated;
create index prime_upload_due on private.prime_upload_jobs(next_attempt_at) where state = 'queued';

create function public.save_employee_prime_account(p_id uuid, p_username text, p_password text default null,
  p_shop_id integer default null, p_product_id integer default null)
returns void language plpgsql security definer set search_path = '' as $$
declare secret_id uuid; employee public.employees;
begin
  if not public.is_admin() then raise insufficient_privilege; end if;
  select * into employee from public.employees where id = p_id for update;
  if not found then raise exception 'Employee not found'; end if;
  if p_username is null or length(p_username) > 254 or
    (p_password is not null and length(p_password) not between 1 and 256) then
    raise exception 'Invalid Prime account';
  end if;
  select password_id into secret_id from private.prime_accounts where employee_id = p_id;
  if trim(p_username) = '' then
    delete from private.prime_accounts where employee_id = p_id;
    delete from vault.secrets where id = secret_id;
    update public.employees set prime_username = '', prime_configured = false where id = p_id;
    return;
  end if;
  if p_password is null and (secret_id is null or employee.prime_username <> trim(p_username)) then
    raise exception 'Prime password required';
  end if;
  if p_password is not null then
    if secret_id is null then
      select vault.create_secret(p_password) into secret_id;
      insert into private.prime_accounts values (p_id, secret_id);
    else
      perform vault.update_secret(secret_id, p_password);
    end if;
  end if;
  update public.employees set prime_username = trim(p_username), prime_configured = true,
    prime_shop_id = p_shop_id, prime_product_id = p_product_id where id = p_id;
end;
$$;
revoke all on function public.save_employee_prime_account(uuid,text,text,integer,integer) from public, anon, authenticated;
grant execute on function public.save_employee_prime_account(uuid,text,text,integer,integer) to authenticated;

create function private.queue_prime_upload() returns trigger
language plpgsql security definer set search_path = '' as $$
declare uploader uuid;
begin
  if new.status = 'confirmed' and (tg_op = 'INSERT' or old.status <> 'confirmed') then
    -- Use the creator's account, or the employee confirming a customer order.
    uploader := coalesce(new.employee_id, (select id from public.employees where user_id = auth.uid()));
    insert into private.prime_upload_jobs(order_id, employee_id) values (new.id, uploader)
      on conflict (order_id) do nothing;
  end if;
  return new;
end;
$$;
create trigger queue_prime_upload after insert or update on public.orders
  for each row execute function private.queue_prime_upload();

create function private.guard_prime_upload() returns trigger
language plpgsql security definer set search_path = '' as $$
declare job private.prime_upload_jobs;
begin
  select * into job from private.prime_upload_jobs where order_id = old.id;
  if job.state in ('working','sending','review') and old.status = 'confirmed' then
    raise exception 'ORDER:جارٍ رفع الطلب إلى برايم أو التحقق من نتيجة الرفع. حاول لاحقاً';
  end if;
  if old.status = 'confirmed' and new.status = 'uploaded' and
    (job.state is distinct from 'succeeded' or job.remote_id is null) then
    raise exception 'ORDER:تتغير الحالة تلقائياً بعد نجاح الرفع إلى برايم';
  end if;
  return new;
end;
$$;
create trigger guard_prime_upload before update on public.orders
  for each row execute function private.guard_prime_upload();

-- Only service_role can claim jobs or read decrypted credentials. One job per
-- invocation bounds execution time. Lock orders before jobs everywhere.
create function public.claim_prime_upload() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare candidate record; job private.prime_upload_jobs; ord public.orders;
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
    return jsonb_build_object('order', to_jsonb(ord) - 'access_token',
      'claim_token', job.claim_token, 'attempt', job.attempts,
      'username', (select prime_username from public.employees where id = job.employee_id),
      'shop_id', (select prime_shop_id from public.employees where id = job.employee_id),
      'product_id', (select prime_product_id from public.employees where id = job.employee_id),
      'password', (select s.decrypted_secret from private.prime_accounts a
        join vault.decrypted_secrets s on s.id = a.password_id where a.employee_id = job.employee_id));
  end loop;
  return null;
end;
$$;

create function public.mark_prime_sending(p_id uuid, p_claim uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  perform 1 from public.orders where id = p_id for update;
  update private.prime_upload_jobs set state = 'sending'
    where order_id = p_id and claim_token = p_claim and state = 'working' and lease_until > now();
  return found;
end;
$$;

create function public.finish_prime_upload(p_id uuid, p_claim uuid, p_outcome text,
  p_remote_id text default null, p_error text default null) returns boolean
language plpgsql security definer set search_path = '' as $$
declare job private.prime_upload_jobs; ord public.orders;
begin
  select * into ord from public.orders where id = p_id for update;
  select * into job from private.prime_upload_jobs where order_id = p_id for update;
  if not found or job.claim_token is distinct from p_claim then return false; end if;
  if job.state = 'succeeded' and p_outcome = 'success' and job.remote_id = p_remote_id then return true; end if;
  if job.state not in ('working','sending','review') then return false; end if;
  if p_outcome not in ('success','retry','failed','review') or p_outcome is null then raise exception 'Invalid outcome'; end if;
  if p_outcome = 'success' then
    if job.state not in ('sending','review') or nullif(trim(p_remote_id), '') is null or
      ord.status <> 'confirmed' or ord.version <> job.order_version then raise exception 'Invalid upload completion'; end if;
    update private.prime_upload_jobs set state = 'succeeded', remote_id = p_remote_id,
      last_error = null, lease_until = null where order_id = p_id;
    update public.orders set status = 'uploaded', version = version + 1, updated_at = now() where id = p_id;
    insert into public.order_events(order_id, from_status, to_status, version, actor_kind)
      values (p_id, 'confirmed', 'uploaded', ord.version + 1, 'system');
  else
    update private.prime_upload_jobs set state = case
        when p_outcome = 'review' then 'review'
        when p_outcome = 'retry' and attempts < 5 then 'queued' else 'failed' end,
      next_attempt_at = now() + make_interval(secs => (60 * power(2, attempts - 1))::integer),
      lease_until = null,
      -- Store only fixed error codes, never provider bodies or credentials.
      last_error = case when p_error in ('login_failed','missing_account','upload_rejected','ambiguous_upload','worker_failed','mapping_required')
        then p_error else 'worker_failed' end where order_id = p_id;
  end if;
  return true;
end;
$$;
revoke all on function public.claim_prime_upload(), public.mark_prime_sending(uuid,uuid),
  public.finish_prime_upload(uuid,uuid,text,text,text) from public, anon, authenticated;
grant execute on function public.claim_prime_upload(), public.mark_prime_sending(uuid,uuid),
  public.finish_prime_upload(uuid,uuid,text,text,text) to service_role;
revoke all on all functions in schema private from public, anon, authenticated;
notify pgrst, 'reload schema';
