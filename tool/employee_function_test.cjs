// Execute the real Edge Function handler with mocked Supabase transport.
// Database transaction/permission behavior is tested by employee_accounts.sql.
const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const {stripTypeScriptTypes} = require('node:module');
const vm = require('node:vm');

let handler, state, calls;
const caller = {
  auth: {getUser: async () => ({data: {user: state.validSession ? {id: 'admin'} : null}})},
  rpc: async (name, args) => {
    calls.push({name, args});
    return name === 'is_admin' ? {data: state.admin} : {error: null};
  },
  from: () => ({select: () => ({eq: () => ({maybeSingle: async () => ({data: state.existing})})})}),
};
const server = {auth: {admin: {createUser: async (args) => {
  calls.push({name: 'createUser', args});
  return {error: state.createError};
}}}};
const source = readFileSync('supabase/functions/save-employee/index.ts', 'utf8')
  .replace(/^import [^\r\n]*\r?\n/, '');
vm.runInNewContext(stripTypeScriptTypes(source), {
  createClient: (_, key) => key === 'service' ? server : caller,
  Response,
  Deno: {env: {get: key => key === 'SUPABASE_SERVICE_ROLE_KEY' ? 'service' : 'public'}, serve: fn => {handler = fn;}},
});
const body = {id: '30000000-0000-4000-8000-000000000111', name: 'Employee', phone: '07701234567', email: 'WORKER@example.com', password: 'Employee123!'};
function reset(overrides = {}) { state = {validSession: true, admin: true, ...overrides}; calls = []; }
async function request(data = body, authorization = 'Bearer session') {
  return handler(new Request('https://example.invalid/save-employee', {
    method: 'POST', headers: authorization ? {Authorization: authorization} : {}, body: JSON.stringify(data),
  }));
}
(async () => {
  reset(); assert.equal((await request(body, null)).status, 401); assert.equal(calls.length, 0);
  reset({validSession: false}); assert.equal((await request()).status, 401); assert.equal(calls.length, 0);
  reset({admin: false}); assert.equal((await request()).status, 403); assert.deepEqual(calls.map(c => c.name), ['is_admin']);
  reset(); assert.equal((await request({...body, password: 'short'})).status, 400); assert(!calls.some(c => c.name === 'createUser'));
  reset(); assert.equal((await request({...body, phone: 'invalid'})).status, 400);
  reset(); const result = await request(); assert.equal(result.status, 200);
  const created = calls.find(c => c.name === 'createUser').args;
  assert.equal(created.email, 'worker@example.com'); assert.equal(created.email_confirm, true);
  assert.deepEqual(JSON.parse(JSON.stringify(created.app_metadata)), {employee_profile: {id: body.id, name: body.name, phone: body.phone}});
  assert(!JSON.stringify(created.app_metadata).includes(body.password));
  assert(!JSON.stringify(await result.json()).includes(body.password));
  reset({existing: {user_id: 'linked-user', email: 'worker@example.com'}});
  assert.equal((await request()).status, 200); assert(!calls.some(c => c.name === 'createUser'));
  assert(calls.some(c => c.name === 'update_employee_profile'));
  reset({existing: {user_id: 'linked-user', email: 'someone@example.com'}});
  assert.equal((await request()).status, 409); assert(!calls.some(c => c.name === 'createUser'));
  reset({createError: {code: 'email_exists'}}); assert.equal((await request()).status, 409);
  reset({createError: {code: 'weak_password'}}); assert.equal((await request()).status, 400);
  reset({createError: {code: 'unexpected_failure'}}); assert.equal((await request()).status, 500);
  console.log('PASS: employee function authorization, validation, Auth payload, retries and errors');
})().catch(error => { console.error(error); process.exitCode = 1; });
