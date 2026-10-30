// Drives the Obsidian dev window through WebView2's DevTools port (9222), without focus or mouse.
//   node cdp.mjs eval "<js expression>"   prints the result (awaited, as JSON)
//   node cdp.mjs shot out.png [x y w h]   saves an image of the page (CSS pixels)
const [, , cmd, ...rest] = process.argv;
const targets = await (await fetch("http://127.0.0.1:9222/json")).json();
const page = targets.find((t) => t.type === "page" && t.url.includes("localhost:1420")) ?? targets.find((t) => t.type === "page");
if (!page) throw new Error("no page on port 9222");
const ws = new WebSocket(page.webSocketDebuggerUrl);
await new Promise((ok, fail) => { ws.onopen = ok; ws.onerror = fail; });
let next = 1;
const pending = new Map();
ws.onmessage = (m) => {
  const msg = JSON.parse(m.data);
  if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); }
};
const send = (method, params = {}) => new Promise((ok) => { const id = next++; pending.set(id, ok); ws.send(JSON.stringify({ id, method, params })); });

if (cmd === "eval") {
  const r = await send("Runtime.evaluate", { expression: rest.join(" "), awaitPromise: true, returnByValue: true });
  if (r.result?.exceptionDetails) console.log("ERROR", r.result.exceptionDetails.exception?.description ?? r.result.exceptionDetails.text);
  else console.log(JSON.stringify(r.result?.result?.value, null, 1));
} else if (cmd === "shot") {
  const [out, x, y, w, h] = rest;
  const clip = x ? { x: +x, y: +y, width: +w, height: +h, scale: 1 } : undefined;
  const r = await send("Page.captureScreenshot", { format: "png", ...(clip ? { clip } : {}) });
  (await import("node:fs")).writeFileSync(out, Buffer.from(r.result.data, "base64"));
  console.log("saved", out);
}
ws.close();
