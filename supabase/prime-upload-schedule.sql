-- Run after deploying prime-upload.
-- Create Vault secrets prime_project_url (your Supabase URL) and
-- prime_worker_secret (same random value as Edge secret PRIME_WORKER_SECRET).
create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;
do $$ begin
  if not exists (select 1 from vault.decrypted_secrets where name = 'prime_project_url') or
     not exists (select 1 from vault.decrypted_secrets where name = 'prime_worker_secret') then
    raise exception 'Configure prime_project_url and prime_worker_secret in Vault first';
  end if;
end $$;
select cron.schedule('prime-order-uploads', '* * * * *', $job$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'prime_project_url') || '/functions/v1/prime-upload',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization',
      'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'prime_worker_secret')),
    body := '{}'::jsonb,
    timeout_milliseconds := 110000
  );
$job$);
