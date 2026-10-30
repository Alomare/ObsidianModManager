// The Wiki's pages: Markdown files in src/wiki, each starting with a short header:
//
//   ---
//   title: How Obsidian works
//   group: Getting started       pages with the same group are listed together, groups in order of first use
//   summary: One line for the list's tooltip and under the title.
//   ---
//
// The file name sets the order and the page id ("10-how-obsidian-works.md" is "how-obsidian-works").
// A translation has the same file name in a folder named after the language (src/wiki/pt-BR/…);
// a page with no translation shows in English.
import { parse, type Doc } from "./Markdown";

export type WikiPage = Doc & { id: string; title: string; group: string; summary: string };

const sources = import.meta.glob("./wiki/*.md", { query: "?raw", import: "default", eager: true }) as Record<string, string>;
const translations = import.meta.glob("./wiki/*/*.md", { query: "?raw", import: "default", eager: true }) as Record<string, string>;

function page(path: string, md: string): WikiPage {
  const name = path.split("/").pop()!.replace(/\.md$/, "");
  const head = /^---\r?\n([\s\S]*?)\r?\n---\r?\n?/.exec(md);
  const about: Record<string, string> = {};
  for (const line of head?.[1].split(/\r?\n/) ?? []) {
    const m = /^(\w+):\s*(.*)$/.exec(line);
    // A value with a colon in it is quoted, as YAML wants.
    if (m) about[m[1]] = m[2].trim().replace(/^"(.*)"$/, "$1");
  }
  const doc = parse(head ? md.slice(head[0].length) : md);
  return { ...doc, id: name.replace(/^\d+-/, ""), title: about.title || name, group: about.group || "Guides", summary: about.summary || "" };
}

const cache = new Map<string, { pages: WikiPage[]; groups: { name: string; pages: WikiPage[] }[] }>();

/** Every page in `lang` (English where a page has no translation), and the pages by group. */
export function wikiPages(lang: string) {
  let hit = cache.get(lang);
  if (!hit) {
    const pages = Object.keys(sources).sort().map((path) => page(path, translations[path.replace("./wiki/", `./wiki/${lang}/`)] ?? sources[path]));
    const groups: { name: string; pages: WikiPage[] }[] = [];
    for (const p of pages) {
      let g = groups.find((x) => x.name === p.group);
      if (!g) groups.push((g = { name: p.group, pages: [] }));
      g.pages.push(p);
    }
    hit = { pages, groups };
    cache.set(lang, hit);
  }
  return hit;
}
