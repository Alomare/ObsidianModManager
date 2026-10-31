// The parts every Settings subtab is made of.
import type { ReactNode } from "react";

export function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="set-section">
      <h2 className="cap">{title}</h2>
      {children}
    </section>
  );
}

/** One row: what it is (and a line about it) on the left, the control on the right. */
export function Row({ label, hint, children }: { label: string; hint?: string; children: ReactNode }) {
  return (
    <div className="set-row">
      <div className="set-text">
        <div className="l">{label}</div>
        {hint && <div className="d">{hint}</div>}
      </div>
      <div className="set-ctl">{children}</div>
    </div>
  );
}
