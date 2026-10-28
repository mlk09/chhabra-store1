import { assertEquals } from "jsr:@std/assert@1";
import { createHandler } from "./handler.ts";

const SHOP = "10000000-0000-0000-0000-000000000001";
const image = "A".repeat(200);
const cats = [{ id: "c-salt", name: "Salt" }];

/** Fake Supabase + Gemini. */
function fakeFetch(opts: { member?: unknown; quota?: boolean; gemini?: number[] } = {}) {
  const calls: string[] = [];
  const geminiCodes = [...(opts.gemini ?? [200])];
  const f = (input: string | URL | Request, init?: RequestInit) => {
    const url = input.toString();
    calls.push(url);
    const auth = new Headers(init?.headers).get("Authorization");
    if (url.endsWith("/auth/v1/user")) {
      return Promise.resolve(auth === "Bearer good" ? Response.json({ id: "u1" }) : new Response("", { status: 401 }));
    }
    if (url.includes("/rest/v1/shop_members")) {
      return Promise.resolve(Response.json(opts.member === undefined ? [{ role: "owner", permissions: [] }] : opts.member));
    }
    if (url.includes("/rpc/ai_take_quota")) return Promise.resolve(Response.json(opts.quota ?? true));
    if (url.includes("generateContent")) {
      const code = geminiCodes.shift() ?? 200;
      if (code !== 200) return Promise.resolve(new Response("busy", { status: code }));
      const answer = { is_product: true, name: "Tata Salt", unit: "kg", unit_qty: 1, mrp: 30, category_id: "c-salt", confidence: 0.9 };
      return Promise.resolve(Response.json({ candidates: [{ content: { parts: [{ text: JSON.stringify(answer) }] } }] }));
    }
    return Promise.resolve(new Response("not found", { status: 404 }));
  };
  return { f: f as typeof fetch, calls };
}

const req = (token: string | null, body: unknown) =>
  new Request("http://x/", {
    method: "POST",
    headers: token ? { Authorization: `Bearer ${token}` } : {},
    body: JSON.stringify(body),
  });

const handler = (fetch: typeof globalThis.fetch, geminiKey = "k") =>
  createHandler({ supabaseUrl: "http://sb", serviceKey: "svc", geminiKey, dailyLimit: 5, fetch });

const good = { shop_id: SHOP, image_base64: image, categories: cats };

Deno.test("owner gets a cleaned guess", async () => {
  const res = await handler(fakeFetch().f)(req("good", good));
  assertEquals(res.status, 200);
  const { guess } = await res.json();
  assertEquals(guess.name, "Tata Salt");
  assertEquals(guess.category_id, "c-salt");
});

Deno.test("no login / bad login → 401, Gemini never called", async () => {
  const fake = fakeFetch();
  assertEquals((await handler(fake.f)(req(null, good))).status, 401);
  assertEquals((await handler(fake.f)(req("bad", good))).status, 401);
  assertEquals(fake.calls.some((c) => c.includes("generateContent")), false);
});

Deno.test("customer (not staff) → 403", async () => {
  assertEquals((await handler(fakeFetch({ member: [] }).f)(req("good", good))).status, 403);
});

Deno.test("staff without products permission → 403", async () => {
  const fake = fakeFetch({ member: [{ role: "staff", permissions: ["billing"] }] });
  assertEquals((await handler(fake.f)(req("good", good))).status, 403);
});

Deno.test("daily limit reached → 429", async () => {
  assertEquals((await handler(fakeFetch({ quota: false }).f)(req("good", good))).status, 429);
});

Deno.test("bad input → 400", async () => {
  const h = handler(fakeFetch().f);
  assertEquals((await h(req("good", { ...good, shop_id: "x" }))).status, 400);
  assertEquals((await h(req("good", { ...good, image_base64: "short" }))).status, 400);
  assertEquals((await h(req("good", { ...good, categories: "nope" }))).status, 400);
});

Deno.test("no Gemini key → 503 (setup hint)", async () => {
  assertEquals((await handler(fakeFetch().f, "")(req("good", good))).status, 503);
});

Deno.test("busy first model → falls back to the second", async () => {
  const fake = fakeFetch({ gemini: [429, 200] });
  const res = await handler(fake.f)(req("good", good));
  assertEquals(res.status, 200);
  assertEquals(fake.calls.filter((c) => c.includes("generateContent")).length, 2);
});

Deno.test("both models busy → 502 ai_busy", async () => {
  const res = await handler(fakeFetch({ gemini: [429, 429] }).f)(req("good", good));
  assertEquals(res.status, 502);
  assertEquals((await res.json()).error, "ai_busy");
});

Deno.test("CORS preflight works for the web app", async () => {
  const res = await handler(fakeFetch().f)(new Request("http://x/", { method: "OPTIONS" }));
  assertEquals(res.headers.get("Access-Control-Allow-Origin"), "*");
});
