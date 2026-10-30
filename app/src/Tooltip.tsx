// One tooltip for the whole window: any element with `data-tip` (the explanation) and/or
// `data-tip-title` (the name, in bold above it) shows it on hover after a short wait and on keyboard
// focus. Mounted once in App. `data-tip-side="bottom"` puts it below.
import { useEffect, useRef, useState } from "react";

const WAIT_MS = 450;
const GAP_PX = 8;

type Tip = { title?: string; text?: string; x: number; y: number; below: boolean };

export function Tooltip() {
  const [tip, setTip] = useState<Tip | null>(null);
  const box = useRef<HTMLDivElement>(null);
  const [shift, setShift] = useState(0);

  useEffect(() => {
    let timer = 0;
    let target: HTMLElement | null = null;
    const show = (el: HTMLElement) => {
      const { tip: text, tipTitle: title } = el.dataset;
      if (!text && !title) return;
      const r = el.getBoundingClientRect();
      const below = el.dataset.tipSide === "bottom" || r.top < 48;
      setTip({ title, text, x: r.left + r.width / 2, y: below ? r.bottom + GAP_PX : r.top - GAP_PX, below });
    };
    const hide = () => {
      clearTimeout(timer);
      target = null;
      setTip(null);
    };
    const over = (e: Event) => {
      const el = (e.target as Element).closest?.<HTMLElement>("[data-tip], [data-tip-title]") ?? null;
      if (el === target) return;
      // A click also focuses the button; only keyboard focus shows the tooltip.
      if (e.type === "focusin" && el && !el.matches(":focus-visible")) return;
      hide();
      if (!el) return;
      target = el;
      timer = window.setTimeout(() => show(el), e.type === "focusin" ? 0 : WAIT_MS);
    };
    document.addEventListener("pointerover", over);
    document.addEventListener("focusin", over);
    document.addEventListener("pointerdown", hide, true);
    document.addEventListener("keydown", hide, true);
    window.addEventListener("blur", hide);
    return () => {
      document.removeEventListener("pointerover", over);
      document.removeEventListener("focusin", over);
      document.removeEventListener("pointerdown", hide, true);
      document.removeEventListener("keydown", hide, true);
      window.removeEventListener("blur", hide);
    };
  }, []);

  // Keep the tooltip inside the window.
  useEffect(() => {
    const el = box.current;
    if (!el || !tip) return setShift(0);
    const r = el.getBoundingClientRect();
    const margin = 8;
    setShift(r.left < margin ? margin - r.left : r.right > innerWidth - margin ? innerWidth - margin - r.right : 0);
  }, [tip]);

  if (!tip) return null;
  return (
    <div ref={box} role="tooltip" className={tip.below ? "tip below" : "tip"}
      style={{ left: tip.x + shift, top: tip.y }}>
      {tip.title && <b className="tip-title">{tip.title}</b>}
      {tip.text && <span>{tip.text}</span>}
    </div>
  );
}
