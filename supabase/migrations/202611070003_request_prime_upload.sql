-- Staff can request/retry an upload without access to credentials or the worker secret.
create function public.request_prime_upload(p_id uuid, p_version integer) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare ord public.orders; job private.prime_upload_jobs; uploader uuid;
begin
  if not public.can_manage_orders() then raise insufficient_privilege; end if;
  -- Same lock order as the worker: order first, then its single durable job.
  select * into ord from public.orders where id = p_id for update;
  if not found then raise exception 'ORDER:الطلب غير موجود'; end if;
  if nullif(trim(ord.prime_case_id), '') is not null then
    return to_jsonb(ord) - 'access_token';
  end if;
  if ord.status <> 'confirmed' then raise exception 'ORDER:رفع الطلب إلى برايم متاح للطلبات المؤكدة فقط'; end if;
  if ord.version is distinct from p_version then raise exception 'ORDER:تغيّر الطلب. أعد فتحه قبل الرفع'; end if;
  select * into job from private.prime_upload_jobs where order_id = p_id for update;
  if found then
    -- An absent response ID is not proof that a timed-out POST failed.
    if job.state in ('sending','review','succeeded') or job.remote_id is not null or
        job.last_error = 'ambiguous_upload' then
      raise exception 'ORDER:نتيجة الرفع قيد التحقق. راجع الطلب في برايم قبل إعادة المحاولة لتجنب التكرار';
    end if;
    if job.state = 'working' and job.lease_until > now() then
      raise exception 'ORDER:جارٍ رفع الطلب إلى برايم. انتظر تحديث الحالة';
    end if;
    update private.prime_upload_jobs set state = 'queued',
      attempts = case when job.state in ('failed','cancelled','working') then 0 else attempts end,
      next_attempt_at = now(), lease_until = null, claim_token = null, last_error = null
      where order_id = p_id;
  else
    uploader := coalesce(ord.employee_id, (select id from public.employees where user_id = auth.uid()));
    insert into private.prime_upload_jobs(order_id, employee_id) values (p_id, uploader);
  end if;
  return to_jsonb(ord) - 'access_token';
end;
$$;
revoke all on function public.request_prime_upload(uuid,integer) from public, anon, authenticated;
grant execute on function public.request_prime_upload(uuid,integer) to authenticated;
notify pgrst, 'reload schema';
