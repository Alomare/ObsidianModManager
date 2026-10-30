// A yes-or-no dialog for the few actions that ask first: Purge, Remove and Delete profile.
// Enter confirms, Esc or a click outside cancels.
import { useEffect, useRef } from "react";
import { t } from "./i18n";

type Props = { title: string; text: string; confirm: string; onConfirm: () => void; onCancel: () => void };

export function Confirm({ title, text, confirm, onConfirm, onCancel }: Props) {
  const ok = useRef<HTMLButtonElement>(null);
  useEffect(() => {
    ok.current?.focus();
    const key = (e: KeyboardEvent) => e.key === "Escape" && onCancel();
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  }, [onCancel]);
  return (
    <div className="modal-back" onPointerDown={(e) => e.target === e.currentTarget && onCancel()}>
      <div className="modal confirm" role="alertdialog" aria-modal="true" aria-label={title}>
        <h2 className="cap">{title}</h2>
        <p>{text}</p>
        <div className="modal-foot">
          <button className="btn" onClick={onCancel}>{t("app.cancel")}</button>
          <button className="btn warn" ref={ok} onClick={onConfirm}>{confirm}</button>
        </div>
      </div>
    </div>
  );
}
