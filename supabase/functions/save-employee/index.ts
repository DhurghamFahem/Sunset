import { createClient } from "npm:@supabase/supabase-js@2.118.0";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const reply = (status: number, body: object) =>
  Response.json(body, { status, headers: cors });

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
    // Validate the session with Auth, then check the live administrator allowlist.
    const { data: session, error: authError } = await caller.auth.getUser();
    if (authError || !session.user) return reply(401, { error: "سجّل الدخول أولاً" });
    const { data: isAdmin, error: roleError } = await caller.rpc("is_admin");
    if (roleError || isAdmin !== true) return reply(403, { error: "إضافة الموظفين متاحة للإدارة فقط" });

    let body;
    try { body = await req.json(); } catch { return reply(400, { error: "بيانات غير صحيحة" }); }
    const { id, name, phone, email, password } = body ?? {};
    if (typeof id !== "string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id) ||
      typeof name !== "string" || name.trim().length < 1 || name.trim().length > 120 ||
      typeof phone !== "string" || !/^\+?[0-9][0-9 ()-]{6,24}$/.test(phone.trim()) ||
      typeof email !== "string" || email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())) {
      return reply(400, { error: "راجع الاسم والهاتف والبريد الإلكتروني" });
    }
    const normalizedEmail = email.trim().toLowerCase();
    const { data: existing, error: lookupError } = await caller.from("employees")
      .select("user_id,email").eq("id", id).maybeSingle();
    if (lookupError) return reply(500, { error: "تعذر تحميل الموظف. تأكد من تحديث قاعدة البيانات" });
    if (existing?.user_id) {
      if (existing.email !== normalizedEmail) return reply(409, { error: "لا يمكن تغيير بريد حساب الدخول من هذه الشاشة" });
      // Also makes a retry after a lost successful create response safe.
      const { error } = await caller.rpc("update_employee_profile", {
        p_id: id, p_name: name.trim(), p_phone: phone.trim(),
      });
      return error ? reply(500, { error: "تعذر حفظ الموظف. حاول مرة ثانية" }) : reply(200, { id });
    }
    if (typeof password !== "string" || password.length < 8 || password.length > 128) {
      return reply(400, { error: "أدخل كلمة مرور من 8 إلى 128 حرفاً" });
    }

    // This key and the password never enter public employee records or logs.
    const server = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { error } = await server.auth.admin.createUser({
      email: normalizedEmail, password, email_confirm: true,
      app_metadata: { employee_profile: { id, name: name.trim(), phone: phone.trim() } },
    });
    if (error) {
      if (["email_exists", "user_already_exists"].includes(error.code ?? "")) {
        return reply(409, { error: "البريد الإلكتروني مستخدم بالفعل. استخدم بريداً آخر" });
      }
      if (error.code === "weak_password") return reply(400, { error: "اختر كلمة مرور أقوى وفق إعدادات الحساب" });
      return reply(500, { error: "تعذر إنشاء حساب الموظف. تحقق من البيانات ثم حاول مرة ثانية" });
    }
    return reply(200, { id });
  } catch {
    return reply(500, { error: "تعذر حفظ الموظف. حاول مرة ثانية" });
  }
});
