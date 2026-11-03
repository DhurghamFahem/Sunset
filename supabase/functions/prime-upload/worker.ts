import { PrimeFailure, type Order, type PreparedShipment } from "./prime.ts";

type Rpc = (name: string, args?: Record<string, unknown>) => Promise<{ data: unknown; error: unknown }>;
type Api = { login(username: string, password: string): Promise<string>; prepare(order: Order, token: string): Promise<PreparedShipment>; upload(shipment: PreparedShipment, token: string): Promise<string> };
type Job = { order: Order; claim_token: string; username: string | null; password: string | null };

export async function processOne(rpc: Rpc, api: Api): Promise<string> {
  const claimed = await rpc("claim_prime_upload");
  if (claimed.error) throw new Error("Queue unavailable");
  const job = claimed.data as Job | null;
  if (!job) return "idle";
  const args = { p_id: job.order.id, p_claim: job.claim_token };
  let sending = false;
  let remoteId: string;
  try {
    if (!job.username || !job.password) {
      const result = await rpc("finish_prime_upload", { ...args, p_outcome: "retry", p_error: "missing_account" });
      if (result.error || result.data !== true) throw new Error("Completion unavailable");
      return "retry";
    }
    // Reauthenticate on every attempt, so an expired/rejected token is never reused.
    const token = await api.login(job.username, job.password);
    const shipment = await api.prepare(job.order, token);
    const marked = await rpc("mark_prime_sending", args);
    if (marked.error) throw new Error("Queue unavailable");
    if (marked.data !== true) return "stale";
    sending = true;
    remoteId = await api.upload(shipment, token);
  } catch (error) {
    const outcome = error instanceof PrimeFailure ? error.outcome : sending ? "review" : "retry";
    const code = error instanceof PrimeFailure ? error.code : sending ? "ambiguous_upload" : "worker_failed";
    const result = await rpc("finish_prime_upload", { ...args, p_outcome: outcome, p_error: code });
    if (result.error || result.data !== true) throw new Error("Completion unavailable");
    return outcome;
  }
  // Retry the database acknowledgement only. Never POST a second shipment when
  // Prime succeeded but the database/network failed to acknowledge completion.
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const result = await rpc("finish_prime_upload", { ...args, p_outcome: "success", p_remote_id: remoteId });
      if (!result.error && result.data === true) return "uploaded";
    } catch { /* The sending lease preserves uncertainty if all acknowledgements fail. */ }
  }
  throw new Error("Upload acknowledgement unavailable");
}
