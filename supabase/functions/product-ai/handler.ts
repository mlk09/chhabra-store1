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
  /** Start the second model if the first hasn't answered by then (default 10 s). */
  hedgeAfterMs?: number;
  /** Give up on everything after this long (default 50 s). */
  totalTimeoutMs?: number;
}

// Lite first: usually the quickest; the bigger model is often "high demand".
const MODELS = ["gemini-flash-lite-latest", "gemini-flash-latest"];

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

    // 5. Ask Gemini.
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
    const tried: { model: string; status: number; ms: number }[] = [];
    const bytes = (body.image_base64 as string).length;
    // Best-effort record of each try (never blocks or breaks the answer).
    const log = (model: string, status: number, ms: number, note?: string) => {
      tried.push({ model, status, ms });
      admin("/rest/v1/ai_log", {
        method: "POST",
        headers: { Prefer: "return=minimal" },
        body: JSON.stringify({ user_id: user.id, model, status, ms, bytes, note: note?.slice(0, 300) }),
      }).catch(() => {});
    };

    // Gemini's speed swings a lot (1 s one hour, 20 s the next). Start the
    // fast model; if it hasn't answered after hedgeAfterMs (or failed), also
    // start the other one. First good answer wins; everything stops at the deadline.
    const stop = new AbortController();
    const deadline = setTimeout(() => stop.abort(), d.totalTimeoutMs ?? 50_000);
    let winner: ReturnType<typeof cleanGuess> | null = null;

    const attempt = async (model: string): Promise<boolean> => {
      const started = Date.now();
      let res: Response;
      try {
        res = await d.fetch(`${geminiBase}/v1beta/models/${model}:generateContent`, {
          method: "POST",
          headers: { "x-goog-api-key": d.geminiKey, "Content-Type": "application/json" },
          body: JSON.stringify(payload),
          signal: stop.signal,
        });
      } catch (e) {
        if (winner) return false; // stopped because the other model already answered
        lastStatus = 504;
        log(model, 504, Date.now() - started, e instanceof Error ? e.name : String(e));
        return false;
      }
      if (!res.ok) {
        lastStatus = res.status;
        const text = (await res.text()).slice(0, 300);
        console.error(`gemini ${model} HTTP ${res.status}: ${text}`);
        log(model, res.status, Date.now() - started, text);
        return false;
      }
      try {
        const data = await res.json();
        const guess = cleanGuess(JSON.parse(data?.candidates?.[0]?.content?.parts?.[0]?.text), categories);
        if (winner) return false;
        winner = guess;
        log(model, 200, Date.now() - started, guess.name);
        stop.abort(); // cancel the other model
        return true;
      } catch {
        log(model, 200, Date.now() - started, "unreadable answer");
        return false;
      }
    };

    const first = attempt(MODELS[0]);
    const second = (async () => {
      // Wait for the hedge delay — or less, if the first model already failed.
      await new Promise<void>((resolve) => {
        const t = setTimeout(resolve, d.hedgeAfterMs ?? 10_000);
        const done = () => {
          clearTimeout(t);
          resolve();
        };
        first.then(done);
        stop.signal.addEventListener("abort", done, { once: true });
      });
      if (winner || stop.signal.aborted) return false;
      return attempt(MODELS[1]);
    })();
    await Promise.allSettled([first, second]);
    clearTimeout(deadline);
    stop.abort();

    if (winner) return json({ guess: winner, tried });
    return json(
      { error: lastStatus === 429 || lastStatus === 503 || lastStatus === 504 ? "ai_busy" : "ai_failed", tried },
      502,
    );
  };
}
