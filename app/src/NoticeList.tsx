import { CloseIcon } from "./Icons";
import { dismiss, useNotices } from "./notices";

export function Notices() {
  const list = useNotices();
  return (
    <div className="notices" role="status" aria-live="polite">
      {list.map((n) => (
        <div key={n.id} className={`notice ${n.kind}`}>
          <span>{n.text}</span>
          <button className="bare" onClick={() => dismiss(n.id)} aria-label="Close"><CloseIcon /></button>
        </div>
      ))}
    </div>
  );
}
