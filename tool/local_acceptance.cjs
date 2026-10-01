// Local integration checks; never connects to a hosted project.
// Run after `supabase start` and `flutter test`.
const {execSync, execFileSync} = require('node:child_process');
const {readFileSync, writeFileSync, mkdirSync} = require('node:fs');
const {randomBytes} = require('node:crypto');
const assert = require('node:assert/strict');
const status = JSON.parse(execSync('npx --yes supabase status -o json', {stdio: ['pipe','pipe','ignore']}).toString());
const base = status.API_URL;
assert.equal(new URL(base).hostname, '127.0.0.1', 'Local tests must never run against production');
let token = status.SERVICE_ROLE_KEY;
async function request(path, {method = 'GET', body, raw, headers = {}} = {}) {
  const response = await fetch(`${base}${path}`, {method, headers: {
    apikey: status.ANON_KEY, Authorization: `Bearer ${token}`,
    'Content-Type': raw ? 'image/png' : 'application/json', ...headers},
    body: raw || (body ? JSON.stringify(body) : undefined)});
  const text = await response.text();
  let data; try { data = JSON.parse(text); } catch { data = text; }
  return {status: response.status, data, response};
}
function sql(value) {
  return execFileSync('docker', ['exec','-i','supabase_db_Sunset','psql','-U','postgres','-v','ON_ERROR_STOP=1'], {input: value, encoding:'utf8'});
}
(async () => {
  mkdirSync('test-results', {recursive:true});
  const suffix = randomBytes(4).toString('hex');
  const email = `g2g-${suffix}@example.test`, password = randomBytes(24).toString('base64url');
  const created = await request('/auth/v1/admin/users', {method:'POST', body:{email, password, email_confirm:true}});
  assert.equal(created.status, 200, JSON.stringify(created.data));
  const userId = created.data.id;
  assert.match(userId, /^[a-f0-9-]{36}$/);
  sql(`insert into public.admin_users(user_id) values ('${userId}');`);
  token = status.ANON_KEY;
  const auth = await request('/auth/v1/token?grant_type=password', {method:'POST',body:{email,password}});
  assert.equal(auth.status,200, JSON.stringify(auth.data)); token = auth.data.access_token;
  assert.equal((await request('/rest/v1/rpc/is_admin', {method:'POST',body:{}})).data, true);
  const original = readFileSync('test-results/fixture-wide.png');
  const object = `${userId}/qa-${suffix}.png`;
  const upload = await request(`/storage/v1/object/tattoo-images/${object}`, {method:'POST',raw:original});
  assert.equal(upload.status,200, JSON.stringify(upload.data));
  const imageUrl = `${base}/storage/v1/object/public/tattoo-images/${object}`;
  const image = await fetch(imageUrl, {headers:{Origin:'http://localhost:8090'}});
  assert.equal(image.status,200);
  assert.equal(image.headers.get('access-control-allow-origin'), '*');
  assert.deepEqual(Buffer.from(await image.arrayBuffer()), original, 'Storage must preserve original artwork bytes');
  const categories = [];
  for (const name of ['وشومات سوار — اختبار','ورود — اختبار']) {
    const result = await request('/rest/v1/categories',{method:'POST',headers:{Prefer:'return=representation'},body:{name_ar:name,image_url:imageUrl}});
    assert.equal(result.status,201,JSON.stringify(result.data)); categories.push(result.data[0]);
  }
  const payload = Array.from({length:29},(_,i) => ({code:`G2G-${99000+i}`, name_ar:'صورة اختبار فقط',
    category_ids:[categories[i<3?0:1].id], audiences:['men','women'], body_placements:['arm','back'], image_url:imageUrl, thumbnail_url:imageUrl,
    width_cm:28,height_cm:7,price:i===6?null:5000,featured:i%3===0,is_new:i%2===0,sort_order:i}));
  const inserted = {data:[]};
  for (const product of payload) {
    const result = await request('/rest/v1/rpc/save_catalog_product',{method:'POST',body:{p_data:product}});
    assert.equal(result.status,200,JSON.stringify(result.data));
    inserted.data.push({...product,id:result.data});
  }
  const duplicate = await request('/rest/v1/rpc/save_catalog_product',{method:'POST',body:{p_data:payload[0]}});
  assert.equal(duplicate.status,409);
  token = status.ANON_KEY;
  const first = await request('/rest/v1/catalog_products?select=*&order=sort_order.asc,id.asc&offset=0&limit=24');
  const second = await request('/rest/v1/catalog_products?select=*&order=sort_order.asc,id.asc&offset=24&limit=24');
  assert.equal(first.data.length,24); assert.equal(second.data.length,5);
  assert.equal(new Set([...first.data,...second.data].map(x=>x.id)).size,29);
  assert.ok((await request('/rest/v1/categories',{method:'POST',body:{name_ar:'forbidden'}})).status >= 400);
  assert.ok((await request(`/storage/v1/object/tattoo-images/forbidden-${suffix}.png`,{method:'POST',raw:original})).status >= 400);
  token = auth.data.access_token;
  assert.equal((await request(`/rest/v1/categories?id=eq.${categories[0].id}`,{method:'DELETE'})).status,409);
  await request(`/rest/v1/categories?id=eq.${categories[0].id}`,{method:'PATCH',body:{active:false}});
  token = status.ANON_KEY;
  assert.equal((await request(`/rest/v1/products?id=eq.${inserted.data[0].id}&select=*`)).data.length,0);
  token = auth.data.access_token;
  await request(`/rest/v1/categories?id=eq.${categories[0].id}`,{method:'PATCH',body:{active:true}});
  const temporary = `${userId}/delete-${suffix}.png`;
  assert.equal((await request(`/storage/v1/object/tattoo-images/${temporary}`,{method:'POST',raw:original})).status,200);
  assert.equal((await request('/storage/v1/object/tattoo-images',{method:'DELETE',body:{prefixes:[temporary]}})).status,200);
  writeFileSync('test-results/local-session.json',JSON.stringify({email,password,userId,categories,products:inserted.data,object},null,2));
  console.log('PASS: real admin login, original upload, cross-origin image fetch, byte identity, category/product creation, duplicate code rejection, 24+5 pagination, anonymous write/upload denial, category deactivation, safe category delete, Storage API deletion.');
  console.log('Local-only QA records retained for browser tests; credentials are in ignored test-results/local-session.json.');
})().catch(error => { console.error(error.stack); process.exitCode=1; });
