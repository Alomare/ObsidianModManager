// The problem report: versions, what is on and the end of the game's log, for a bug report.
import { call, errorText } from "./api";
import { t } from "./i18n";
import { notify } from "./notices";

export async function copyReport() {
  try {
    await navigator.clipboard.writeText(await call<string>("support_report"));
    notify("info", t("app.report.copied"));
  } catch (e) {
    notify("error", errorText(e));
  }
}
