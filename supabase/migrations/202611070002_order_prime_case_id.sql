-- Keep the returned carrier ID on the order, as well as the private upload job.
alter table public.orders add column prime_case_id text;

-- Successful historical jobs already hold the authoritative response ID.
update public.orders o set prime_case_id = j.remote_id
from private.prime_upload_jobs j
where j.order_id = o.id and j.state = 'succeeded' and j.remote_id is not null;

create or replace function public.finish_prime_upload(p_id uuid, p_claim uuid, p_outcome text,
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
    update public.orders set status = 'uploaded', prime_case_id = p_remote_id, version = version + 1, updated_at = now() where id = p_id;
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

revoke all on function public.finish_prime_upload(uuid,uuid,text,text,text) from public, anon, authenticated;
grant execute on function public.finish_prime_upload(uuid,uuid,text,text,text) to service_role;
notify pgrst, 'reload schema';
