// POST { shop_id, image_base64 (JPEG), categories: [{id,name}] } → { guess }
// Only shop staff with the "products" permission may call it. The Gemini key
// lives in Supabase Secrets (GEMINI_API_KEY) and never reaches the app.
import { createHandler } from "./handler.ts";

Deno.serve(createHandler({
  supabaseUrl: Deno.env.get("SUPABASE_URL")!,
  serviceKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  geminiKey: Deno.env.get("GEMINI_API_KEY") ?? "",
  dailyLimit: Number(Deno.env.get("AI_DAILY_LIMIT") ?? "300"),
  fetch,
}));
