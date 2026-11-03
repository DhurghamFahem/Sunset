const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const {stripTypeScriptTypes} = require('node:module');
const vm = require('node:vm');
function load(file, names, extra = {}) {
  const source = readFileSync(`supabase/functions/prime-upload/${file}.ts`, 'utf8')
    .replace(/^import .*\r?\n/gm, '').replace(/^export /gm, '');
  return vm.runInNewContext(stripTypeScriptTypes(source, {mode: 'transform'}) + `\n;({${names}})`, {
    Response, AbortSignal, fetch, ...extra,
  });
}
const {PrimeClient, PrimeFailure} = load('prime', 'PrimeClient, PrimeFailure');
const {processOne} = load('worker', 'processOne', {PrimeFailure});
const order = {id: 'order-uuid', code: 'AB12', governorate: 'بغداد', area: 'المنصور',
  phone: '07701234567', customer_name: 'Customer', landmark: 'landmark', delivery_notes: 'Call first',
  delivery_cost: 5000, final_total: 17000,
  items: [{name: 'Tattoo A', quantity: 2, unit_price: 5000}, {name: 'Tattoo B', quantity: 1, unit_price: 4000}]};
let requests, overrides;
const transport = async (url, options) => {
  const path = url.replace('https://prime-iq.com/myp/webapi/', '');
  requests.push({path, ...options, body: options.body && JSON.parse(options.body)});
  if (overrides[path]) return overrides[path]();
  const bodies = {
    'auth/login': {accessToken: 'token'}, 'merchant/list-of-shops': [{id: 7, active: true}],
    'general/states': [{key: 'BGD', val: 'بغداد'}],
    'general/state-districts/BGD': [{districtId: 17, districtName: 'المنصور'}],
    'merchant/shop-products/7': [{id: 44, name: 'Tattoos', active: true, heightCm: 10, lengthCm: 5, widthCm: 3}],
    'logistics/check-shipment-cost-within-range': {},
    'logistics/calculate-shipment-charges': {shipmentCharge: 5000},
    'logistics/create-new-case': 987654,
  };
  assert(path in bodies, path);
  return Response.json(bodies[path]);
};
function reset() {requests = []; overrides = {};}
async function runApi() {
  const api = new PrimeClient(transport);
  const token = await api.login('employee', 'secret');
  return api.upload(await api.prepare(order, token), token);
}
(async () => {
  reset(); assert.equal(await runApi(), '987654');
  assert.deepEqual(requests[0].body, {Login: 'employee', Password: 'secret', WhichSystem: 'CUSTOMER_MOBILEAPP'});
  assert(requests.slice(1).every(r => r.headers.Authorization === 'Bearer token'));
  assert.deepEqual(requests.slice(-3).map(r => r.path.split('/').pop()), [
    'check-shipment-cost-within-range', 'calculate-shipment-charges', 'create-new-case']);
  const create = requests.at(-1).body, charge = requests.at(-2).body;
  assert.equal(create.receiverName, 'AB12 - Customer');
  assert(create.locationDetails.includes(order.id));
  assert.equal(create.receiptAmtIqd, '17000'); assert.equal(create.receiptAmtUsd, '0');
  assert.equal(create.rmk, 'Call first'); assert.equal(create.productsList.length, 1);
  assert.equal(create.productsList[0].qty, 3); assert.equal(create.productsList[0].itemSellPrice, '4667');
  assert.equal(typeof create.heightCm, 'number'); assert.equal(typeof charge.heightCm, 'string');
  assert(!('productsList' in charge)); assert.equal(create.district, '17'); assert.equal(create.senderId, 7);
  reset(); overrides['logistics/check-shipment-cost-within-range'] = () => Response.json({}, {status: 422});
  await assert.rejects(runApi, e => e.outcome === 'retry'); assert(!requests.some(r => r.path.endsWith('create-new-case')));
  reset(); overrides['merchant/list-of-shops'] = () => Response.json([{id: 7}, {id: 8}]);
  await assert.rejects(runApi, e => e.code === 'mapping_required');
  reset(); overrides['general/state-districts/BGD'] = () => Response.json([{districtId: 18, districtName: 'Other'}]);
  await assert.rejects(runApi, e => e.code === 'mapping_required');
  for (const body of [987654, {caseId: 987654}, '987654']) {
    reset(); overrides['logistics/create-new-case'] = () => Response.json(body);
    assert.equal(await runApi(), '987654');
  }
  for (const body of [{ok: true}, 0, 'error']) {
    reset(); overrides['logistics/create-new-case'] = () => Response.json(body);
    await assert.rejects(runApi, e => e.outcome === 'review');
  }
  reset(); overrides['logistics/create-new-case'] = () => { throw new Error('timeout'); };
  await assert.rejects(runApi, e => e.outcome === 'review');
  reset(); overrides['logistics/create-new-case'] = () => Response.json({}, {status: 401});
  await assert.rejects(runApi, e => e.outcome === 'retry');

  let calls, sends, logins, job, finishFailures, mark, prepareFailure, uploadFailure;
  const api = {
    login: async () => {logins++; return 'fresh';},
    prepare: async () => {if (prepareFailure) throw prepareFailure; return {};},
    upload: async () => {sends++; if (uploadFailure) throw uploadFailure; return '987654';},
  };
  const rpc = async (name, args) => {
    calls.push({name, args});
    if (name === 'claim_prime_upload') return {data: job};
    if (name === 'mark_prime_sending') return {data: mark};
    if (finishFailures-- > 0) return {error: 'db unavailable'};
    return {data: true};
  };
  function workerReset() {
    calls = []; sends = 0; logins = 0; finishFailures = 0; mark = true; prepareFailure = uploadFailure = null;
    job = {order, claim_token: 'claim', username: 'employee', password: 'secret'};
  }
  workerReset(); assert.equal(await processOne(rpc, api), 'uploaded'); assert.equal(sends, 1);
  assert.equal(calls.at(-1).args.p_remote_id, '987654');
  workerReset(); finishFailures = 2; assert.equal(await processOne(rpc, api), 'uploaded'); assert.equal(sends, 1);
  workerReset(); finishFailures = 3; await assert.rejects(() => processOne(rpc, api)); assert.equal(sends, 1);
  assert(calls.filter(c => c.name === 'finish_prime_upload').every(c => c.args.p_outcome === 'success'));
  workerReset(); job.password = null; assert.equal(await processOne(rpc, api), 'retry'); assert.equal(logins, 0);
  workerReset(); mark = false; assert.equal(await processOne(rpc, api), 'stale'); assert.equal(sends, 0);
  workerReset(); prepareFailure = new PrimeFailure('upload_rejected', 'retry');
  assert.equal(await processOne(rpc, api), 'retry'); assert.equal(sends, 0);
  workerReset(); uploadFailure = new PrimeFailure('ambiguous_upload', 'review');
  assert.equal(await processOne(rpc, api), 'review'); assert.equal(calls.at(-1).args.p_outcome, 'review');
  workerReset(); job = null; assert.equal(await processOne(rpc, api), 'idle'); assert.equal(logins, 0);

  const source = readFileSync('supabase/functions/prime-upload/index.ts', 'utf8').replace(/^import .*\r?\n/gm, '');
  let handler, claimed = 0;
  vm.runInNewContext(stripTypeScriptTypes(source), {Response, PrimeClient,
    processOne: async () => {claimed++; return 'idle';}, createClient: () => ({}),
    Deno: {serve: fn => handler = fn, env: {get: key => key === 'PRIME_WORKER_SECRET' ? 'worker-secret' : 'env'}}});
  for (const token of ['', 'anon-key', 'employee-session']) {
    assert.equal((await handler(new Request('https://local/', {method: 'POST', headers: {Authorization: `Bearer ${token}`}}))).status, 401);
  }
  assert.equal(claimed, 0);
  assert.equal((await handler(new Request('https://local/', {method: 'POST', headers: {Authorization: 'Bearer worker-secret'}}))).status, 200);
  assert.equal(claimed, 1);
  console.log('PASS: Prime wire contract, mapping, totals, preflights, retries, uncertain uploads, acknowledgement recovery and worker authentication');
})().catch(error => { console.error(error); process.exitCode = 1; });
