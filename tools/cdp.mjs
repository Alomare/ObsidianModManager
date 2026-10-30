// Drives the Obsidian dev window through WebView2's DevTools port (9222), without focus or mouse.
//   node cdp.mjs eval "<js expression>"   prints the result (awaited, as JSON)
//   node cdp.mjs shot out.png [x y w h]   saves an image of the page (CSS pixels)
//   node cdp.mjs drag x1 y1 x2 y2 [out.png] drags with the mouse (image taken before release)
//   node cdp.mjs wait [after-ms]          returns once the window is up and the app has rendered;
//                                         with after-ms, first waits for a page newer than that
//                                         (a restart), and reloads a page that stays blank
const [, , cmd, ...rest] = process.argv;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function page() {
  const all = await (await fetch("http://127.0.0.1:9222/json")).json();
  return all.find((t) => t.type === "page" && t.url.includes("localhost:1420")) ?? all.find((t) => t.type === "page");
}
async function evalOn(t, expression) {
  const ws = new WebSocket(t.webSocketDebuggerUrl);
  await new Promise((ok, fail) => { ws.onopen = ok; ws.onerror = fail; });
  const r = await new Promise((ok) => { ws.onmessage = (m) => ok(JSON.parse(m.data)); ws.send(JSON.stringify({ id: 1, method: "Runtime.evaluate", params: { expression, returnByValue: true } })); });
  ws.close();
  return r.result?.result?.value;
}
if (cmd === "wait") {
  const since = +(rest[0] ?? 0);
  const start = Date.now();
  let blankSince = 0;
  while (Date.now() - start < 180000) {
    try {
      const t = await page();
      const state = t && (await evalOn(t, "JSON.stringify({ up: performance.timeOrigin, app: !!document.querySelector('.app .nav') })"));
      const s = state && JSON.parse(state);
      if (s && s.up > since) {
        if (s.app) { console.log(`ready in ${((Date.now() - start) / 1000).toFixed(1)} s`); process.exit(0); }
        blankSince ||= Date.now();
        if (Date.now() - blankSince > 4000) { await evalOn(t, "location.reload()"); blankSince = 0; }
      }
    } catch { /* not up yet */ }
    await sleep(500);
  }
  console.log("timed out");
  process.exit(1);
}

const target = await page();
if (!target) throw new Error("no page on port 9222");
const ws = new WebSocket(target.webSocketDebuggerUrl);
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
} else if (cmd === "drag") {
  // drag x1 y1 x2 y2 [shot.png]: a real mouse drag in 12 steps; the image is taken before release.
  const [x1, y1, x2, y2, out] = rest.map((v, i) => (i < 4 ? +v : v));
  const mouse = (type, x, y) => send("Input.dispatchMouseEvent", { type, x, y, button: "left", buttons: type === "mouseReleased" ? 0 : 1, clickCount: 1 });
  await mouse("mousePressed", x1, y1);
  for (let i = 1; i <= 12; i++) {
    await mouse("mouseMoved", x1 + ((x2 - x1) * i) / 12, y1 + ((y2 - y1) * i) / 12);
    await sleep(16);
  }
  if (out) {
    await sleep(80);
    const r = await send("Page.captureScreenshot", { format: "png" });
    (await import("node:fs")).writeFileSync(out, Buffer.from(r.result.data, "base64"));
  }
  await mouse("mouseReleased", x2, y2);
  console.log("dragged");
}
ws.close();
