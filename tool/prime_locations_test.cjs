const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const {stripTypeScriptTypes} = require('node:module');
const vm = require('node:vm');
let handler, state, calls;
const source = readFileSync('supabase/functions/prime-locations/index.ts','utf8').replace(/^import .*\r?\n/gm,'');
const caller = {
  auth: {getUser: async () => ({data: {user: state.session ? {id: 'verified-user'} : null}})},
  rpc: async () => ({data: state.staff}),
};
const server = {rpc: async (name,args) => {calls.push({name,args}); return {data: state.account};}};
class PrimeClient {
  async login(username,password) {calls.push({name: 'login',username,password}); if (state.fail) throw Error('private error secret'); return 'private-token';}
  async locations(token,stateId) {calls.push({name:'locations',token,stateId}); return [{id:stateId ? '17' : 'BGD',name:stateId ? 'المنصور' : 'بغداد'}];}
}
vm.runInNewContext(stripTypeScriptTypes(source), {
  Response, PrimeClient, createClient: (_,key) => key === 'service' ? server : caller,
  Deno: {env: {get: key => key === 'SUPABASE_SERVICE_ROLE_KEY' ? 'service' : 'public'},serve: fn => handler=fn},
});
const orderId='40000000-0000-4000-8000-000000000121';
function reset(extra={}) {state={session:true,staff:true,account:{username:'prime-user',password:'private-password'},...extra}; calls=[];}
function request(body={orderId},token='session') {return handler(new Request('https://local/prime-locations',{
  method:'POST',headers: token ? {Authorization:`Bearer ${token}`} : {},body:JSON.stringify(body),
}));}
(async()=>{
  reset(); assert.equal((await request({orderId},null)).status,401); assert.equal(calls.length,0);
  reset({session:false}); assert.equal((await request()).status,401); assert.equal(calls.length,0);
  reset({staff:false}); assert.equal((await request()).status,403); assert.equal(calls.length,0);
  reset(); assert.equal((await request({orderId,stateId:'../auth/login'})).status,400); assert.equal(calls.length,0);
  reset(); assert.equal((await request({orderId:'invalid'})).status,400);
  reset({account:null}); assert.equal((await request()).status,409); assert(!calls.some(c=>c.name==='login'));
  reset(); let result=await request({orderId,userId:'attacker',employeeId:'other'});
  assert.equal(result.status,200); assert.equal(calls[0].name,'prime_location_account');
  assert.equal(calls[0].args.p_user_id,'verified-user'); assert.equal(calls[0].args.p_order_id,orderId);
  assert.deepEqual(await result.json(),{locations:[{id:'BGD',name:'بغداد'}]});
  reset(); result=await request({orderId,stateId:'BGD'});
  assert.deepEqual(await result.json(),{locations:[{id:'17',name:'المنصور'}]});
  assert.equal(calls.at(-1).stateId,'BGD');
  reset({fail:true}); result=await request(); assert.equal(result.status,502);
  assert(!(await result.text()).includes('private'));
  console.log('PASS: Prime locations session/role validation, credential isolation, state validation, sanitized responses and errors');
})().catch(e=>{console.error(e);process.exitCode=1;});
