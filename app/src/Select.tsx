// A styled dropdown in place of the native <select>: a button that opens a list. Arrow keys move,
// Enter or Space picks, Esc or a click outside closes.
import { useEffect, useId, useRef, useState, type KeyboardEvent } from "react";
import { ChevronIcon } from "./Icons";

type Props<T extends string> = {
  value: T;
  options: { value: T; label: string }[];
  onChange: (v: T) => void;
  /** Shown before the value inside the button, muted. */
  prefix?: string;
  label: string;
  tip?: string;
};

export function Select<T extends string>({ value, options, onChange, prefix, label, tip }: Props<T>) {
  const [open, setOpen] = useState(false);
  const [hi, setHi] = useState(0);
  const root = useRef<HTMLDivElement>(null);
  const list = useId();
  const current = options.find((o) => o.value === value);

  useEffect(() => {
    if (!open) return;
    setHi(Math.max(0, options.findIndex((o) => o.value === value)));
    const away = (e: PointerEvent) => !root.current?.contains(e.target as Node) && setOpen(false);
    document.addEventListener("pointerdown", away, true);
    return () => document.removeEventListener("pointerdown", away, true);
  }, [open, options, value]);

  const pick = (v: T) => {
    setOpen(false);
    if (v !== value) onChange(v);
  };
  const key = (e: KeyboardEvent) => {
    if (e.key === "Escape" && open) {
      e.stopPropagation();
      setOpen(false);
    } else if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      if (!open) return setOpen(true);
      setHi((h) => (h + (e.key === "ArrowDown" ? 1 : -1) + options.length) % options.length);
    } else if ((e.key === "Enter" || e.key === " ") && open) {
      e.preventDefault();
      pick(options[hi].value);
    }
  };

  return (
    <div className={open ? "select open" : "select"} ref={root} onKeyDown={key}>
      <button type="button" className="select-btn" aria-haspopup="listbox" aria-expanded={open} aria-controls={list}
        aria-label={`${label}: ${current?.label ?? ""}`} data-tip-title={open || !tip ? undefined : label} data-tip={open ? undefined : tip} onClick={() => setOpen((o) => !o)}>
        {prefix && <span className="select-prefix">{prefix}</span>}
        <span className="select-value">{current?.label}</span>
        <ChevronIcon />
      </button>
      {open && (
        <ul className="select-list" role="listbox" id={list} aria-label={label}>
          {options.map((o, i) => (
            <li key={o.value} role="option" aria-selected={o.value === value} className={i === hi ? "hi" : undefined}
              onPointerEnter={() => setHi(i)} onClick={() => pick(o.value)}>
              {o.label}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
