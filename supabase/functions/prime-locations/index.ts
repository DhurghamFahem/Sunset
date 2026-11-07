import { createClient } from "npm:@supabase/supabase-js@2.118.0";
import { PrimeClient } from "../prime-upload/prime.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const reply = (status: number, body: object) => Response.json(body, { status, headers: cors });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply(405, { error: "Method not allowed" });
  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return reply(401, { error: "سجّل الدخول أولاً" });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const caller = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: session, error: authError } = await caller.auth.getUser();
    if (authError || !session.user) return reply(401, { error: "سجّل الدخول أولاً" });
    const { data: allowed, error: roleError } = await caller.rpc("can_manage_orders");
    if (roleError || allowed !== true) return reply(403, { error: "متاح لموظفي الطلبات فقط" });
    let body;
    try { body = await req.json(); } catch { return reply(400, { error: "بيانات غير صحيحة" }); }
    const { orderId, stateId } = body ?? {};
    if (typeof orderId !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(orderId) ||
      (stateId !== undefined && (typeof stateId !== 'string' || !/^[a-zA-Z0-9_-]{1,30}$/.test(stateId)))) {
      return reply(400, { error: "بيانات غير صحيحة" });
    }
    const server = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: account, error } = await server.rpc('prime_location_account', {
      p_order_id: orderId, p_user_id: session.user.id,
    });
    if (error) return reply(503, { error: "تعذر تحميل حساب برايم" });
    if (!account?.username || !account?.password) return reply(409, { error: "أضف حساب برايم لمنشئ الطلب أولاً: الحساب الرئيسي من إعدادات التوصيل، أو الموظف من إعدادات الموظفين" });
    const prime = new PrimeClient();
    const token = await prime.login(account.username, account.password);
    return reply(200, { locations: await prime.locations(token, stateId) });
  } catch {
    // Only sanitized location options cross the browser boundary, never credentials.
    return reply(502, { error: "تعذر تحميل المحافظات أو المناطق من برايم. تحقق من الحساب وأعد المحاولة" });
  }
});
