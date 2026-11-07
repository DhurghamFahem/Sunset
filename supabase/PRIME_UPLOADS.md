# Prime background uploads

Orders enter the durable queue when they become **confirmed**. Saving a completed
manual order automatically confirms it once pricing, phone, address and Prime
state/district IDs are present. Incomplete manual drafts and customer selections
remain pending until completed or explicitly confirmed. Each order has one job; refreshing the
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

1. Apply all migrations, including `202611030001_prime_uploads.sql`, `202611030002_prime_order_options.sql`, `202611040001_employee_auth_metadata.sql`, and `202611040002_manual_order_upload_on_save.sql`.
2. Deploy all three functions:
   ```sh
   npx supabase functions deploy save-employee
   npx supabase functions deploy prime-upload
   npx supabase functions deploy prime-locations
   ```
3. Generate a random server-only `PRIME_WORKER_SECRET` (at least 32 random bytes)
   and set it in Supabase Edge Function secrets. Never put it in Flutter config.
4. In Supabase Vault, create `prime_project_url` containing your project's HTTPS
   URL and `prime_worker_secret` containing the same worker secret.
5. Execute `supabase/prime-upload-schedule.sql`. It installs a once-per-minute
   invocation using pg_cron and pg_net. Each invocation processes one order.
   Scheduling follows [Supabase's Edge Function scheduling documentation](https://supabase.com/docs/guides/functions/schedule-functions).
6. In the employee editor, enter that employee's **Prime username/password**.
   Passwords are encrypted in Vault; only username/configured status appear in the employee editor. Leaving a saved password blank retains
   it; changing the username requires a new password. Clearing the username
   disconnects the Prime account.

The order creator's employee account is used. For a customer-created order, the
employee who confirms it is used. An administrator without a linked employee
account has no implicit Prime identity: confirm through a configured employee
account. Missing credentials consume retries and leave the order confirmed.

## Address, shop and product mapping

- State and district selectors load their options from Prime through the
  authenticated `prime-locations` Edge Function. They save both Prime IDs and
  human-readable labels. Changing state clears the district; failed requests
  offer retry. Browser clients never receive Prime credentials or tokens.
- Existing text-only addresses are matched to Prime names/IDs for compatibility.
  Newly saved selections use explicit IDs, and the worker verifies that the
  district belongs to the selected state before creating the shipment.
- The first store returned by Prime is selected, followed by the first product
  returned for that store. All tattoos use that product. Legacy employee mapping
  columns are retained for compatibility but no longer affect selection.
- Dimensions come from that Prime product. Missing dimensions or empty lists stop
  the attempt. Quantities are aggregated; parcel dimensions use Pigeon's
  volume-based calculation.
- The customer name sent to Prime is exactly the order code. `locationDetails`
  contains the nearest point (trimmed), or the selected Prime district name when
  the nearest point is blank. Delivery notes are sent separately in `rmk`.
- The original merchandise price excludes delivery. Order total includes delivery
  and honors saved discounts. Prime's per-item selling price is the merchandise
  portion (total minus delivery, floored at zero), divided by quantity and rounded
  to whole dinars as required by the existing Prime contract.
- The create-order body also sends `undeclaredShipmentValue` as the exact
  merchandise portion before per-item rounding, encoded as a string like the
  other monetary fields. This merchant-only amount is preserved for paid orders.
- **Paid** means goods AND delivery have already been paid. `is_paid` is saved on
  the order; Prime receives `receiptAmtIqd: "0"` for paid orders and the total
  including delivery for unpaid orders. The merchandise value and local total
  are preserved. Payment status can be changed only before upload; customers
  cannot set it. The form shows the amount the driver should collect.

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

Employee creation requires the deployed `save-employee` function as well as the
database migrations. Auth can attach employee app metadata after inserting the
login. `202611040001_employee_auth_metadata.sql` provisions on metadata updates
too, and repairs valid incomplete accounts created by the previous trigger.
It preserves already-linked accounts and revoked employee access.

For an end-to-end local creation/sign-in check, start local Supabase, run
`npx supabase functions serve save-employee`, then run
`node tool/employee_integration_test.cjs`. It verifies creation with and without
Prime credentials, retry safety, employee permissions, Vault password preservation
and recovery of incomplete accounts. Temporary test accounts are cleaned up.
The test refuses non-local API URLs and never contacts Prime.

```sh
node tool/prime_upload_test.cjs
node tool/prime_locations_test.cjs
node tool/employee_function_test.cjs
flutter test test/prime_address_fields_test.dart test/employee_account_test.dart test/order_ui_test.dart test/order_repository_test.dart
flutter analyze
```

Run `supabase/tests/prime_uploads.sql` on a migrated test database. Fixtures roll
back. It checks Vault permissions, account preservation, enqueueing, claim fencing,
five-attempt exhaustion/backoff, cancellation, crash recovery, successful status
updates and audit idempotence. `orders.sql` and `edit_order_tattoos.sql` use mock
carrier receipts for their later-stage fixtures. No verification creates live
Prime shipments.
