// Request handling for "product-ai", with fetch + settings passed in so tests
// can run it against fake servers.
import { corsHeaders, json } from "../_shared/cors.ts";
import { buildPrompt, buildSchema, cleanGuess, validCategories, validImage } from "./guess.ts";

export interface Deps {
  supabaseUrl: string;
  serviceKey: string;
  geminiKey: string;
  dailyLimit: number;
  fetch: typeof fetch;
  geminiBase?: string;
}

const MODELS = ["gemini-flash-latest", "gemini-flash-lite-latest"];

export function createHandler(d: Deps) {
  const geminiBase = d.geminiBase ?? "https://generativelanguage.googleapis.com";
  const admin = (path: string, init: RequestInit = {}) =>
    d.fetch(`${d.supabaseUrl}${path}`, {
      ...init,
      headers: {
        apikey: d.serviceKey,
        Authorization: `Bearer ${d.serviceKey}`,
        "Content-Type": "application/json",
        ...init.headers,
      },
    });

  return async (req: Request): Promise<Response> => {
    if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
    if (req.method !== "POST") return json({ error: "POST only" }, 405);
    if (!d.geminiKey) return json({ error: "ai_not_configured" }, 503);

    // 1. Who is calling?
    const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    if (!token) return json({ error: "login_required" }, 401);
    const userRes = await d.fetch(`${d.supabaseUrl}/auth/v1/user`, {
      headers: { apikey: d.serviceKey, Authorization: `Bearer ${token}` },
    });
    if (!userRes.ok) return json({ error: "login_required" }, 401);
    const user = await userRes.json();

    // 2. Valid request?
    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return json({ error: "bad_request" }, 400);
    }
    const shopId = typeof body.shop_id === "string" && /^[0-9a-f-]{36}$/.test(body.shop_id) ? body.shop_id : null;
    if (!shopId || !validImage(body.image_base64) || !validCategories(body.categories)) {
      return json({ error: "bad_request" }, 400);
    }
    const categories = body.categories;

    // 3. Allowed to add products in this shop?
    const memberRes = await admin(
      `/rest/v1/shop_members?select=role,permissions&shop_id=eq.${shopId}&user_id=eq.${user.id}`,
    );
    const member = memberRes.ok ? (await memberRes.json())[0] : null;
    if (!member || !(member.role === "owner" || (member.permissions ?? []).includes("products"))) {
      return json({ error: "forbidden" }, 403);
    }

    // 4. Daily limit (protects the free Gemini quota from abuse).
    const quota = await admin("/rest/v1/rpc/ai_take_quota", {
      method: "POST",
      body: JSON.stringify({ p_user: user.id, p_limit: d.dailyLimit }),
    });
    if (!quota.ok) return json({ error: "server_error" }, 500);
    if ((await quota.json()) !== true) return json({ error: "daily_limit" }, 429);

    // 5. Ask Gemini (fall back to the lighter model when busy).
    const payload = {
      contents: [{
        parts: [
          { inline_data: { mime_type: "image/jpeg", data: body.image_base64 } },
          { text: buildPrompt(categories) },
        ],
      }],
      generationConfig: {
        temperature: 0.1,
        responseMimeType: "application/json",
        responseSchema: buildSchema(categories),
      },
    };
    let lastStatus = 0;
    for (const model of MODELS) {
      const res = await d.fetch(`${geminiBase}/v1beta/models/${model}:generateContent`, {
        method: "POST",
        headers: { "x-goog-api-key": d.geminiKey, "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      lastStatus = res.status;
      if (!res.ok) {
        console.error(`gemini ${model} HTTP ${res.status}: ${(await res.text()).slice(0, 300)}`);
        if (res.status === 429 || res.status >= 500 || res.status === 404) continue;
        break;
      }
      const data = await res.json();
      try {
        return json({ guess: cleanGuess(JSON.parse(data?.candidates?.[0]?.content?.parts?.[0]?.text), categories) });
      } catch {
        console.error(`gemini ${model}: unreadable answer`);
      }
    }
    return json({ error: lastStatus === 429 ? "ai_busy" : "ai_failed" }, 502);
  };
}
