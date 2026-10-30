// The square image of a mod or profile, or the first letter of the name when there is none. With `pick`, a click
// chooses a new image and a small button removes the player's own.
import { convertFileSrc } from "@tauri-apps/api/core";
import { open } from "@tauri-apps/plugin-dialog";
import { run } from "./api";
import { CloseIcon } from "./Icons";
import { t } from "./i18n";
import type { ImageRef } from "./types";

const TYPES = ["png", "jpg", "jpeg", "webp"];

export const imageSrc = (img: ImageRef) => `${convertFileSrc(img.path)}?v=${img.v}`;

type Pick = { owner: "mod" | "profile"; key: string; custom: boolean };

export function Thumb({ image, name, size = "md", pick }: { image: ImageRef | null; name: string; size?: "sm" | "md" | "lg"; pick?: Pick }) {
  const face = image ? <img src={imageSrc(image)} alt="" draggable={false} /> : <span aria-hidden="true">{[...name.trim()][0]?.toUpperCase() ?? "?"}</span>;
  if (!pick) return <span className={`thumb ${size}`}>{face}</span>;
  const choose = async () => {
    const path = await open({ multiple: false, directory: false, title: t("app.image.choose"), filters: [{ name: t("app.image.files"), extensions: TYPES }] });
    if (typeof path === "string") run("set_image", { owner: pick.owner, key: pick.key, path });
  };
  return (
    <span className="thumb-wrap">
      <button className={`thumb ${size}`} onClick={choose} aria-label={t("app.image.choose")} data-tip-title={t("app.image.choose")} data-tip={t("app.image.chooseHint")}>
        {face}
      </button>
      {pick.custom && (
        <button className="thumb-x" onClick={() => run("set_image", { owner: pick.owner, key: pick.key, path: null })}
          aria-label={t("app.image.remove")} data-tip={t("app.image.remove")}><CloseIcon /></button>
      )}
    </span>
  );
}
