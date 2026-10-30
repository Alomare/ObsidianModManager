// Number options: the value the slider and the number box may hold.

type NumberSpec = { min: number | null; max: number | null; step: number | null };

/** `v` snapped to the step (counted from the minimum) and kept within min and max. */
export function clampNumber(v: number, { min, max, step }: NumberSpec): number {
  const base = min ?? 0;
  if (!Number.isFinite(v)) return base;
  let out = step ? base + Math.round((v - base) / step) * step : v;
  if (min !== null) out = Math.max(min, out);
  if (max !== null) out = Math.min(max, out);
  return parseFloat(out.toFixed(10));
}
