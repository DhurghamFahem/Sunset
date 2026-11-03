import { createClient } from "npm:@supabase/supabase-js@2.118.0";
import { PrimeClient } from "./prime.ts";
import { processOne } from "./worker.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return Response.json({ error: "Method not allowed" }, { status: 405 });
  const secret = Deno.env.get("PRIME_WORKER_SECRET");
  if (!secret || req.headers.get("Authorization") !== `Bearer ${secret}`) {
    return Response.json({ error: "Unauthorized" }, { status: 401 });
  }
  try {
    const server = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const result = await processOne(async (name, args) => await server.rpc(name, args), new PrimeClient());
    return Response.json({ result });
  } catch {
    // Never log requests, credential-bearing job data, tokens or provider bodies.
    return Response.json({ error: "Prime worker failed" }, { status: 500 });
  }
});
