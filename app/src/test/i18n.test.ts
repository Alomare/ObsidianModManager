import { describe, expect, it } from "vitest";
import { pickLanguage, translate } from "../i18n";

const catalogs = { en: { hi: "Hello %s, %s", only: "English only" }, "pt-BR": { hi: "Olá %s, %s" } };

describe("translate", () => {
  it("placeholders_fill_in_order", () => expect(translate(catalogs, "pt-BR", "hi", ["a", 2])).toBe("Olá a, 2"));
  it("missing_key_falls_back_to_english", () => expect(translate(catalogs, "pt-BR", "only", [])).toBe("English only"));
  it("missing_everywhere_returns_key", () => expect(translate(catalogs, "pt-BR", "nope", [])).toBe("nope"));
});

describe("pickLanguage", () => {
  it("prefers_the_saved_choice", () => expect(pickLanguage("zh-CN", ["pt-BR"])).toBe("zh-CN"));
  it("matches_the_system_language_by_its_first_part", () => expect(pickLanguage(null, ["pt-PT", "en-US"])).toBe("pt-BR"));
  it("falls_back_to_english", () => expect(pickLanguage("xx", ["de-DE"])).toBe("en"));
});
