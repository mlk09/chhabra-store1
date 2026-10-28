// Pure helpers for "product-ai": the prompt, the JSON schema Gemini must
// follow, and cleaning its answer. No network here, so it is easy to test.

export const UNITS = ["kg", "g", "l", "ml", "pc", "pack", "dozen"] as const;
export type Unit = typeof UNITS[number];

export interface CategoryRef {
  id: string;
  name: string;
}

export interface ProductGuess {
  is_product: boolean;
  name: string;
  name_hi: string | null;
  brand: string | null;
  size_label: string | null;
  unit: Unit;
  unit_qty: number;
  mrp: number | null;
  is_loose: boolean;
  category_id: string | null;
  synonyms: string[];
  confidence: number;
}

export function buildPrompt(categories: CategoryRef[]): string {
  const list = categories.map((c) => `- ${c.id}: ${c.name}`).join("\n");
  return `You help an Indian kirana (grocery) shopkeeper add products from a photo.
Look at the photo and identify the ONE main product.
Rules:
- name: English product name as printed on the pack, with brand, without size (e.g. "Tata Salt", "Aashirvaad Whole Wheat Atta").
  Loose vegetables/grains: a simple English name (e.g. "Potato", "Moong Dal").
- name_hi: the common Hindi name in Devanagari (e.g. "टाटा नमक", "आलू").
- size_label: net quantity exactly as printed (e.g. "1 kg", "500 ml", "4 x 100 g"). Empty if not visible.
- unit + unit_qty: the net quantity as a number and unit (500 ml → unit "ml", unit_qty 500; 1 kg → "kg", 1). Use "pc" for single items, "pack" for multipacks.
- mrp: the printed MRP in rupees as a number, ONLY if you can read it clearly. Otherwise null. Never guess a price.
- is_loose: true only for unpacked items sold by weight (vegetables, loose grains).
- category_id: the best matching id from this list, or "none":
${list}
- synonyms: up to 5 other words Indian customers may search (Hinglish like "cheeni", "aloo"), lowercase.
- confidence: 0 to 1, how sure you are about the name.
- is_product: false if the photo does not show a sellable product.`;
}

/** Gemini "responseSchema" (OpenAPI subset). Category ids are an enum so it can't invent one. */
export function buildSchema(categories: CategoryRef[]) {
  return {
    type: "OBJECT",
    properties: {
      is_product: { type: "BOOLEAN" },
      name: { type: "STRING" },
      name_hi: { type: "STRING" },
      brand: { type: "STRING" },
      size_label: { type: "STRING" },
      unit: { type: "STRING", enum: [...UNITS] },
      unit_qty: { type: "NUMBER" },
      mrp: { type: "NUMBER", nullable: true },
      is_loose: { type: "BOOLEAN" },
      category_id: { type: "STRING", enum: [...categories.map((c) => c.id), "none"] },
      synonyms: { type: "ARRAY", items: { type: "STRING" } },
      confidence: { type: "NUMBER" },
    },
    required: ["is_product", "name", "unit", "unit_qty", "is_loose", "category_id", "confidence"],
  };
}

const text = (v: unknown, max: number): string | null => {
  if (typeof v !== "string") return null;
  const t = v.replace(/\s+/g, " ").trim();
  return t.length === 0 ? null : t.slice(0, max);
};

const num = (v: unknown): number | null => {
  const n = typeof v === "number" ? v : typeof v === "string" ? Number(v) : NaN;
  return Number.isFinite(n) ? n : null;
};

/** Never trust the model: clamp every field to what the database accepts. */
export function cleanGuess(raw: unknown, categories: CategoryRef[]): ProductGuess {
  const r = (raw && typeof raw === "object" ? raw : {}) as Record<string, unknown>;
  const unit = UNITS.includes(r.unit as Unit) ? (r.unit as Unit) : "pc";
  const qty = num(r.unit_qty);
  const mrp = num(r.mrp);
  const cat = typeof r.category_id === "string" && categories.some((c) => c.id === r.category_id)
    ? r.category_id
    : null;
  const conf = num(r.confidence) ?? 0;
  const synonyms = Array.isArray(r.synonyms)
    ? [...new Set(r.synonyms.map((s) => text(s, 30)?.toLowerCase()).filter((s): s is string => !!s))].slice(0, 5)
    : [];
  return {
    is_product: r.is_product !== false && !!text(r.name, 100),
    name: text(r.name, 100) ?? "",
    name_hi: text(r.name_hi, 100),
    brand: text(r.brand, 60),
    size_label: text(r.size_label, 40),
    unit,
    unit_qty: qty !== null && qty > 0 && qty < 100000 ? Math.round(qty * 1000) / 1000 : 1,
    mrp: mrp !== null && mrp > 0 && mrp <= 100000 ? Math.round(mrp * 100) / 100 : null,
    is_loose: r.is_loose === true,
    category_id: cat,
    synonyms,
    confidence: Math.min(1, Math.max(0, conf)),
  };
}

/** Base64 JPEG/PNG/WebP only, max ~1.5 MB of data. */
export function validImage(b64: unknown): b64 is string {
  return typeof b64 === "string" && b64.length > 100 && b64.length <= 2_000_000 && /^[A-Za-z0-9+/=]+$/.test(b64);
}

export function validCategories(v: unknown): v is CategoryRef[] {
  return Array.isArray(v) && v.length <= 100 &&
    v.every((c) => c && typeof c.id === "string" && c.id.length <= 64 && typeof c.name === "string" && c.name.length <= 80);
}
