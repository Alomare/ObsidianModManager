import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { Markdown, parse } from "../Markdown";

describe("Markdown callouts", () => {
  // `.tip` is the tooltip: fixed, and moved off the page's flow.
  it("don't share a class with the tooltip", () => {
    const html = renderToStaticMarkup(<Markdown tokens={parse("> [!TIP]\n> Mind the gap").tokens} />);
    expect(html).toContain('class="callout callout-tip"');
    expect(html).toContain("Mind the gap");
    expect(html).not.toContain("[!TIP]");
  });
});
