// Key names as the loader reads them (lowercase, see loader/src/settings.lua). Keys the game's
// keyboard table may name differently are left out rather than guessed.

const NAMED: Record<string, string> = {
  Space: "space", Tab: "tab", Enter: "enter", Backspace: "backspace",
  Insert: "insert", Delete: "delete", Home: "home", End: "end",
};

/** The loader's name for the key pressed, or null for Esc (cancel) and keys it cannot read. */
export function keyName(e: Pick<KeyboardEvent, "code" | "key">): string | null {
  const c = e.code;
  if (/^Key[A-Z]$/.test(c)) return c.slice(3).toLowerCase();
  if (/^Digit[0-9]$/.test(c)) return c.slice(5);
  if (/^F([1-9]|1[0-2])$/.test(c)) return c.toLowerCase();
  return NAMED[c] ?? null;
}
