// Run with local Supabase and `supabase functions serve save-employee` running.
// Exercises the real HTTP handler, Auth provisioning, permissions and Vault.
// No Prime request is made. All temporary accounts are removed in finally.
const assert = require('node:assert/strict');
const {execSync, execFileSync} = require('node:child_process');
const {randomUUID} = require('node:crypto');
const {readFileSync} = require('node:fs');
const config = JSON.parse(execSync('npx --yes supabase status --output json', {
  encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
}));
const base = config.API_URL;
assert(['127.0.0.1', 'localhost'].includes(new URL(base).hostname), 'Local test only');
const ids = [randomUUID(), randomUUID()];
const adminEmail = `employee-test-admin-${randomUUID()}@example.com`;
const password = `Test-${randomUUID()}!`;
let adminId;
function sql(query) {
  return execFileSync('docker', ['exec', '-i', 'supabase_db_Sunset', 'psql',
    '-U', 'postgres', '-d', 'postgres', '-At', '-v', 'ON_ERROR_STOP=1'], {
    input: query, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'],
  }).trim();
}
async function call(path, body, token = config.SERVICE_ROLE_KEY, method = 'POST') {
  const response = await fetch(`${base}${path}`, {
    method, headers: {apikey: config.ANON_KEY, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json'},
    ...(body === undefined ? {} : {body: JSON.stringify(body)}),
    signal: AbortSignal.timeout(30000),
  });
  const json = await response.json();
  assert(response.ok, `${path}: HTTP ${response.status}; ${json.code ?? json.error_code ?? json.error ?? 'request failed'}; ${json.message ?? ''}`);
  return json;
}
async function login(email) {
  return (await call('/auth/v1/token?grant_type=password', {email, password}, config.ANON_KEY)).access_token;
}
(async () => {
  // Re-run the recovery migration in a rolled-back transaction against the
  // exact orphan shape produced by the old insert-only trigger.
  const orphanUser = randomUUID(), orphanEmployee = randomUUID();
  const migration = readFileSync('supabase/migrations/202611040001_employee_auth_metadata.sql', 'utf8');
  sql(`begin;
    drop trigger provision_employee_account on auth.users;
    create trigger provision_employee_account after insert on auth.users
      for each row execute function public.provision_employee_account();
    insert into auth.users(id,email) values ('${orphanUser}','recovery-${orphanUser}@example.com');
    update auth.users set raw_app_meta_data =
      '{"employee_profile":{"id":"${orphanEmployee}","name":"Recovery test","phone":"07701234567"}}'
      where id='${orphanUser}';
    ${migration}
    do $$ begin
      if not exists(select 1 from public.employees where id='${orphanEmployee}' and user_id='${orphanUser}') or
        not exists(select 1 from public.employee_users where user_id='${orphanUser}') then
        raise exception 'Orphan account was not repaired';
      end if;
    end $$;
    rollback;`);
  try {
    const admin = await call('/auth/v1/admin/users', {email: adminEmail, password, email_confirm: true});
    adminId = admin.id;
    assert.match(adminId, /^[0-9a-f-]{36}$/);
    sql(`insert into public.admin_users(user_id) values ('${adminId}');`);
    const token = await login(adminEmail);
    for (const [index, id] of ids.entries()) {
      const email = `employee-test-${id}@example.com`;
      const body = {id, name: 'Employee integration test', phone: '07701234567', email, password,
        primeUsername: index === 0 ? '' : 'test-prime-user',
        ...(index === 0 ? {} : {primePassword: 'test-prime-secret'}),
      };
      let saved;
      try { saved = await call('/functions/v1/save-employee', body, token); }
      catch (error) {
        await call('/rest/v1/rpc/save_employee_prime_account', {
          p_id: id, p_username: body.primeUsername, p_password: body.primePassword ?? null,
          p_shop_id: null, p_product_id: null,
        }, token);
        throw error;
      }
      assert.equal(saved.id, id);
      // Retrying creation must update the same employee, not duplicate Auth users.
      assert.equal((await call('/functions/v1/save-employee', body, token)).id, id);
      const rows = await call(`/rest/v1/employees?id=eq.${id}&select=id,user_id,email,prime_configured,prime_username`, undefined, token, 'GET');
      assert.equal(rows.length, 1); assert.equal(rows[0].email, email);
      assert.equal(rows[0].prime_configured, index === 1);
      const employeeToken = await login(email);
      assert.equal(await call('/rest/v1/rpc/can_manage_orders', {}, employeeToken), true);
      assert.equal(await call('/rest/v1/rpc/is_admin', {}, employeeToken), false);
      if (index === 1) {
        delete body.primePassword;
        await call('/functions/v1/save-employee', body, token);
        assert.equal(sql(`select count(*) from private.prime_accounts a join vault.decrypted_secrets s on s.id=a.password_id
          where a.employee_id='${id}' and s.decrypted_secret='test-prime-secret';`), '1');
      }
    }
    console.log('PASS: orphan recovery, real employee creation with blank/filled Prime fields, idempotent retry, sign-in, employee access and encrypted password preservation');
  } finally {
    const employeeIds = ids.map(id => `'${id}'`).join(',');
    sql(`begin;
      with removed as (delete from private.prime_accounts where employee_id in (${employeeIds}) returning password_id)
        delete from vault.secrets where id in (select password_id from removed);
      delete from public.employees where id in (${employeeIds});
      delete from auth.users where raw_app_meta_data->'employee_profile'->>'id' in (${employeeIds})
        ${adminId ? `or id='${adminId}'` : ''};
      commit;`);
  }
})().catch(error => {console.error(error.message); process.exitCode = 1;});
