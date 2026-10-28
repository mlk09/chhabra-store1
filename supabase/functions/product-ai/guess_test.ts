import { assertEquals } from "jsr:@std/assert@1";
import { buildPrompt, buildSchema, cleanGuess, validCategories, validImage } from "./guess.ts";

const cats = [{ id: "c-oil", name: "Oil & Ghee" }, { id: "c-salt", name: "Sugar, Salt & Jaggery" }];

Deno.test("good answer passes through, trimmed", () => {
  const g = cleanGuess({
    is_product: true, name: "  Tata   Salt ", name_hi: "टाटा नमक", brand: "Tata", size_label: "1 kg",
    unit: "kg", unit_qty: 1, mrp: 30, is_loose: false, category_id: "c-salt",
    synonyms: ["Namak", "namak", "salt"], confidence: 0.93,
  }, cats);
  assertEquals(g.name, "Tata Salt");
  assertEquals(g.category_id, "c-salt");
  assertEquals(g.mrp, 30);
  assertEquals(g.synonyms, ["namak", "salt"]);
  assertEquals(g.is_product, true);
});

Deno.test("invented category, bad unit, absurd numbers are cleaned", () => {
  const g = cleanGuess({ name: "X", unit: "litres", unit_qty: -4, mrp: 9e9, category_id: "hack", confidence: 7 }, cats);
  assertEquals(g.category_id, null);
  assertEquals(g.unit, "pc");
  assertEquals(g.unit_qty, 1);
  assertEquals(g.mrp, null);
  assertEquals(g.confidence, 1);
});

Deno.test("garbage or empty answer is 'not a product'", () => {
  assertEquals(cleanGuess(null, cats).is_product, false);
  assertEquals(cleanGuess({ name: "   " }, cats).is_product, false);
  assertEquals(cleanGuess({ name: "Soap", is_product: false }, cats).is_product, false);
});

Deno.test("long text is cut to database limits", () => {
  const g = cleanGuess({ name: "a".repeat(500), brand: "b".repeat(500) }, cats);
  assertEquals(g.name.length, 100);
  assertEquals(g.brand?.length, 60);
});

Deno.test("schema only allows real category ids", () => {
  const s = buildSchema(cats);
  assertEquals(s.properties.category_id.enum, ["c-oil", "c-salt", "none"]);
  assertEquals(buildPrompt(cats).includes("c-oil: Oil & Ghee"), true);
});

Deno.test("input validation", () => {
  assertEquals(validImage("abc"), false);
  assertEquals(validImage("A".repeat(200)), true);
  assertEquals(validImage("<script>".repeat(50)), false);
  assertEquals(validCategories(cats), true);
  assertEquals(validCategories([{ id: 1 }]), false);
  assertEquals(validCategories("x"), false);
});
