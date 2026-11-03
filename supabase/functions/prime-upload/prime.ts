// Wire contract ported from Pigeon/prime_carrier.dart and prime_upload_test.dart:
// PascalCase login, camelCase logistics, three logistics calls, numeric case ID.
export type Order = Record<string, unknown> & { id: string };
type Row = Record<string, unknown>;
export type PreparedShipment = Record<string, unknown>;
export class PrimeFailure extends Error {
  constructor(
    public code: "login_failed" | "upload_rejected" | "ambiguous_upload" | "mapping_required",
    public outcome: "retry" | "failed" | "review",
  ) { super(code); }
}
const normalize = (value: unknown) => String(value ?? '').trim().normalize('NFKC').replace(/\s+/g, ' ').toLowerCase();
const rows = (value: unknown): Row[] => {
  if (!Array.isArray(value)) throw new PrimeFailure("upload_rejected", "retry");
  return value.filter((row): row is Row => !!row && typeof row === 'object' && !Array.isArray(row));
};
function unique(values: Row[]): Row {
  if (values.length !== 1) throw new PrimeFailure("mapping_required", "retry");
  return values[0];
}
function positive(value: unknown): number {
  const number = Number(value);
  if (!Number.isSafeInteger(number) || number <= 0) throw new PrimeFailure("mapping_required", "retry");
  return number;
}

export class PrimeClient {
  constructor(private transport: typeof fetch = fetch) {}

  private async call(path: string, token?: string, body?: unknown, creates = false): Promise<unknown> {
    try {
      const response = await this.transport(`https://prime-iq.com/myp/webapi/${path}`, {
        method: body === undefined ? "GET" : "POST", redirect: "error", signal: AbortSignal.timeout(10_000),
        headers: { "Content-Type": "application/json", Accept: "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      });
      if (!response.ok) {
        if (creates && (response.status >= 500 || response.status === 408)) throw new PrimeFailure("ambiguous_upload", "review");
        // Explicit rejections did not create a shipment. Each next attempt logs in again.
        throw new PrimeFailure("upload_rejected", "retry");
      }
      const text = await response.text();
      return text.trim() ? JSON.parse(text) : null;
    } catch (error) {
      if (error instanceof PrimeFailure) throw error;
      throw new PrimeFailure(creates ? "ambiguous_upload" : "upload_rejected", creates ? "review" : "retry");
    }
  }

  async login(username: string, password: string): Promise<string> {
    try {
      const body = await this.call("auth/login", undefined, {
        Login: username, Password: password, WhichSystem: "CUSTOMER_MOBILEAPP",
      }) as Row;
      for (const key of ['accessToken', 'AccessToken', 'access_token', 'token']) {
        if (typeof body?.[key] === 'string' && (body[key] as string).trim()) return (body[key] as string).trim();
      }
    } catch { /* Do not expose credentials or provider responses. */ }
    throw new PrimeFailure("login_failed", "retry");
  }

  async locations(token: string, stateKey?: string): Promise<{ id: string; name: string }[]> {
    if (stateKey !== undefined && !/^[a-zA-Z0-9_-]{1,30}$/.test(stateKey)) throw new PrimeFailure('mapping_required', 'failed');
    const result = rows(await this.call(stateKey === undefined ? 'general/states' : `general/state-districts/${stateKey}`, token));
    return result.map(row => ({
      id: String(stateKey === undefined ? row.key ?? '' : row.districtId ?? ''),
      name: String(stateKey === undefined ? row.val ?? '' : row.districtName ?? ''),
    })).filter(row => row.id.length > 0 && row.name.length > 0);
  }

  async prepare(order: Order, token: string): Promise<PreparedShipment> {
    const shops = rows(await this.call('merchant/list-of-shops', token));
    const shop = unique(shops.slice(0, 1));
    const senderId = positive(shop.id);
    const states = rows(await this.call('general/states', token));
    const state = unique(states.filter(s => order.prime_state_id
      ? String(s.key) === String(order.prime_state_id)
      : [s.key, s.val].some(v => normalize(v) === normalize(order.governorate))));
    const stateKey = String(state.key);
    if (!/^[a-zA-Z0-9_-]+$/.test(stateKey)) throw new PrimeFailure('mapping_required', 'retry');
    const districts = rows(await this.call(`general/state-districts/${stateKey}`, token));
    const district = unique(districts.filter(d => order.prime_district_id
      ? Number(d.districtId) === Number(order.prime_district_id)
      : [d.districtId, d.districtName].some(v => normalize(v) === normalize(order.area))));
    const districtId = String(positive(district.districtId));
    const products = rows(await this.call(`merchant/shop-products/${senderId}`, token));
    const product = unique(products.slice(0, 1));
    const lines = rows(order.items);
    if (!lines.length) throw new PrimeFailure('mapping_required', 'retry');
    const grouped = new Map<number, { qty: number; value: number; heightCm: number; lengthCm: number; widthCm: number }>();
    let subtotal = 0;
    for (const line of lines) {
      // All tattoos use the first product returned for the first Prime store.
      const id = positive(product.id), qty = positive(line.quantity), price = Number(line.unit_price);
      if (!Number.isSafeInteger(price) || price < 0) throw new PrimeFailure('mapping_required', 'retry');
      const value = qty * price;
      subtotal += value;
      const held = grouped.get(id);
      if (held) { held.qty += qty; held.value += value; }
      else grouped.set(id, { qty, value, heightCm: positive(product.heightCm), lengthCm: positive(product.lengthCm), widthCm: positive(product.widthCm) });
    }
    let volume = 0, largest = 0, dominant = { heightCm: 0, lengthCm: 0, widthCm: 0 };
    const productsList = [...grouped.entries()].map(([id, p]) => {
      const each = p.heightCm * p.lengthCm * p.widthCm;
      volume += each * p.qty;
      if (each > largest) { largest = each; dominant = p; }
      return { id, qty: p.qty, itemSellPrice: String(Math.round(p.value / p.qty)), heightCm: p.heightCm, lengthCm: p.lengthCm, widthCm: p.widthCm };
    });
    const scale = Math.cbrt(volume / largest);
    const dimensions = { heightCm: Math.round(dominant.heightCm * scale), lengthCm: Math.round(dominant.lengthCm * scale), widthCm: Math.round(dominant.widthCm * scale) };
    const total = Number(order.final_total ?? subtotal + Number(order.delivery_cost));
    if (!Number.isSafeInteger(total) || total < 0) throw new PrimeFailure('mapping_required', 'retry');
    // Product value excludes delivery, including any final order discount.
    const goodsTotal = Math.max(0, total - Number(order.delivery_cost));
    const pieces = productsList.reduce((sum, product) => sum + product.qty, 0);
    for (const product of productsList) product.itemSellPrice = String(Math.round(goodsTotal / pieces));
    // Prime's receipt amount is what the driver collects, not the order value.
    const common = { state: stateKey, district: districtId, senderId, receiptAmtIqd: String(order.is_paid === true ? 0 : total) };
    await this.call('logistics/check-shipment-cost-within-range', token, { ...common, productsList });
    await this.call('logistics/calculate-shipment-charges', token, {
      ...common, heightCm: String(dimensions.heightCm), lengthCm: String(dimensions.lengthCm), widthCm: String(dimensions.widthCm),
    });
    const recipient = String(order.code ?? '').trim();
    if (!recipient || !order.phone) throw new PrimeFailure('mapping_required', 'retry');
    return {
      ...common, ...dimensions, productsList, receiptAmtUsd: '0',
      receiverName: recipient, receiverHp1: order.phone,
      // Full UUID supports reconciliation; short order codes are reused.
      locationDetails: `${order.code} [${order.id}] - ${order.governorate} - ${order.area}${order.landmark ? ` - ${order.landmark}` : ''}`,
      rmk: String(order.delivery_notes ?? ''),
    };
  }

  async upload(shipment: PreparedShipment, token: string): Promise<string> {
    const body = await this.call('logistics/create-new-case', token, shipment, true);
    const candidates = body && typeof body === 'object' ?
      ['caseId', 'CaseId', 'caseid', 'Id', 'id', 'case_id'].map(key => (body as Row)[key]) : [body];
    for (const value of candidates) {
      if ((typeof value === 'number' && Number.isSafeInteger(value) && value > 0) ||
        (typeof value === 'string' && /^[1-9][0-9]*$/.test(value.trim()))) return String(value).trim();
    }
    throw new PrimeFailure('ambiguous_upload', 'review');
  }
}
