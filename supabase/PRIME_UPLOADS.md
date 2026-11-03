# Prime background uploads

Orders enter the durable queue when they become **confirmed**. Pending selections
do not contain a deliverable address yet. Each order has one job; refreshing the
browser or retrying confirmation cannot enqueue another shipment. The worker runs
on the server, independently of Flutter. Existing confirmed orders are not
backfilled automatically.

The wire format is ported from the local Pigeon project's
`lib/features/delivery/integration/prime_carrier.dart` and
`test/prime_upload_test.dart`. It logs in with `Login`, `Password` and
`WhichSystem: CUSTOMER_MOBILEAPP`, resolves Prime IDs, checks the shipment range,
calculates charges, and posts to `logistics/create-new-case`. Only a positive case
number advances the order to **uploaded**, increments its version and writes a
system audit event. Tokens live only for one attempt.

## Configure and deploy

1. Apply all migrations, including `202611030001_prime_uploads.sql`.
2. Deploy both functions:
   ```sh
   npx supabase functions deploy save-employee
   npx supabase functions deploy prime-upload
   ```
3. Generate a random server-only `PRIME_WORKER_SECRET` (at least 32 random bytes)
   and set it in Supabase Edge Function secrets. Never put it in Flutter config.
4. In Supabase Vault, create `prime_project_url` containing your project's HTTPS
   URL and `prime_worker_secret` containing the same worker secret.
5. Execute `supabase/prime-upload-schedule.sql`. It installs a once-per-minute
   invocation using pg_cron and pg_net. Each invocation processes one order.
   Scheduling follows [Supabase's Edge Function scheduling documentation](https://supabase.com/docs/guides/functions/schedule-functions).
6. In the employee editor, enter that employee's **Prime username/password**.
   Passwords are encrypted in Vault; only username/configured status and optional
   mapping IDs appear in employee records. Leaving a saved password blank retains
   it; changing the username requires a new password. Clearing the username
   disconnects the Prime account.

The order creator's employee account is used. For a customer-created order, the
employee who confirms it is used. An administrator without a linked employee
account has no implicit Prime identity: confirm through a configured employee
account. Missing credentials consume retries and leave the order confirmed.

## Address, shop and product mapping

- Governorate must match a Prime state name or key, e.g. `بغداد` or `BGD`.
- Area must match a district name or numeric district ID within that state.
  The landmark remains free text and is included in `locationDetails`.
- A single active shop is automatic. If there are multiple, set the optional
  **Prime shop number** in the employee editor.
- A single active Prime product is automatic. With multiple products, exact
  names are matched. Alternatively, set the employee's **Prime tattoo product
  number** to represent every tattoo with the selected Prime product.
- Dimensions come from Prime's product catalog. Missing/invalid dimensions or
  ambiguous mappings stop the attempt; the worker never guesses an ID. Multiple
  local tattoos mapped to one Prime product are aggregated by quantity and
  weighted unit price. Parcel dimensions use Pigeon's volume-based calculation.
- Collection amount is the saved final total, or item subtotal plus delivery.
  The short order code and full UUID are included in the address for tracing.

Changes made after a successful upload are not synchronized to Prime by this
integration. Make corresponding corrections in Prime before packing/shipping.

## Retry and recovery

Five attempts total, with delays of 1, 2, 4 and 8 minutes after failures, plus the
scheduler's one-minute granularity and time spent behind other queued orders.
Every attempt signs in afresh. Missing credentials, mapping failures, preflight
failures and explicit create-request rejections are retried. No failure changes
the order's confirmed status. Workers use a two-minute lease and a unique claim
token; stale workers cannot complete another worker's claim.

A create-request timeout, server error, unreadable success response, or worker
termination after dispatch may mean Prime accepted the order. These jobs are held
in **review**, still confirmed, without another POST. Prime's reference integration
does not establish an idempotency-key contract. Automatically repeating those
requests could create duplicate deliveries. Order edits are blocked while sending
or awaiting that reconciliation. Pre-dispatch expired leases are safe to reclaim.

Inspect jobs from the trusted SQL editor (not from a client):
```sql
select j.order_id, o.code, j.state, j.attempts, j.next_attempt_at,
       j.last_error, j.remote_id
from private.prime_upload_jobs j join public.orders o on o.id = j.order_id
order by j.created_at desc;
```

For a reviewed job, search Prime using the full order UUID in the address. If a
shipment exists, acknowledge its verified case number through
`finish_prime_upload(order_id, claim_token, 'success', case_number)` as a database
administrator. If Prime confirms that no shipment exists, set the job to `queued`
with `next_attempt_at = now()` and clear `lease_until`/`claim_token`; reset attempts
to zero only when deliberately granting another five-attempt budget. Do not reset
a `sending` job while its worker is active. For an exhausted `failed` job, correct
the account/address/mapping first and then deliberately requeue it in the same way.

## Verification

```sh
node tool/prime_upload_test.cjs
node tool/employee_function_test.cjs
flutter test test/employee_account_test.dart test/order_ui_test.dart test/order_repository_test.dart
flutter analyze
```

Run `supabase/tests/prime_uploads.sql` on a migrated test database. Fixtures roll
back. It checks Vault permissions, account preservation, enqueueing, claim fencing,
five-attempt exhaustion/backoff, cancellation, crash recovery, successful status
updates and audit idempotence. `orders.sql` and `edit_order_tattoos.sql` use mock
carrier receipts for their later-stage fixtures. No verification creates live
Prime shipments.
