import { useId } from "react";

/**
 * How strongly a map is drawn over the basemap. A map that beat its null
 * models starts at STANDARD; one that could not starts FAINT, so it reads as
 * a weak claim. The viewer can move either way, and a click on a mark goes
 * straight back to it.
 */
export const STANDARD = 80;
export const FAINT = 25;

const MARKS = [
  { value: FAINT, label: "Faint", title: "How a map that failed its null test is drawn" },
  { value: STANDARD, label: "Standard", title: "How a map that beat its null models is drawn" },
];

// Within this many points of a mark, the slider settles on the mark.
const SNAP = 3;

/**
 * Where a map starts. With a measured strength (0 for a map that failed its
 * null test, up to 1 for one far above its nulls) it starts between FAINT and
 * STANDARD in proportion; without one, faint when it failed and standard
 * otherwise.
 */
export function defaultStrength(failed: boolean, strength?: number): number {
  if (strength != null && Number.isFinite(strength)) {
    const share = Math.min(1, Math.max(0, strength));
    return Math.round(FAINT + (STANDARD - FAINT) * share);
  }
  return failed ? FAINT : STANDARD;
}

/** A dragged value, pulled onto a mark when it lands close to one. */
export function snapStrength(value: number): number {
  const near = MARKS.find((mark) => Math.abs(mark.value - value) <= SNAP);
  return near ? near.value : Math.round(value);
}

export function MapStrength({
  value,
  onChange,
  algorithm,
}: {
  value: number;
  onChange: (value: number) => void;
  algorithm: string;
}) {
  const id = useId();
  // The slider's thumb is 16 px wide and stops half a thumb from each end,
  // so a mark sits where the thumb's centre would be at that value.
  const at = (v: number) => `calc(${v}% + ${8 - (v * 16) / 100}px)`;
  return (
    <div className="flex items-center gap-3 border-t border-[#A87146]/10 bg-[#f8f5f0] px-4 pb-4 pt-2">
      <label htmlFor={id} className="shrink-0 text-xs text-muted-foreground">
        Map strength
      </label>
      <div className="relative flex-1">
        <input
          id={id}
          type="range"
          min={0}
          max={100}
          step={1}
          value={value}
          onChange={(event) => onChange(snapStrength(Number(event.target.value)))}
          className="block h-4 w-full cursor-pointer accent-myco-green"
          aria-valuetext={`${value}%`}
          aria-label={`How strongly the ${algorithm} map is drawn`}
        />
        {MARKS.map((mark) => (
          <button
            key={mark.value}
            type="button"
            onClick={() => onChange(mark.value)}
            title={mark.title}
            aria-pressed={value === mark.value}
            className={`absolute top-4 -translate-x-1/2 whitespace-nowrap rounded px-1 text-[10px] leading-4 hover:bg-[#A87146]/10 ${
              value === mark.value ? "font-semibold text-[#4a3728]" : "text-muted-foreground"
            }`}
            style={{ left: at(mark.value) }}
          >
            <span aria-hidden className="absolute -top-1.5 left-1/2 h-1.5 w-px -translate-x-1/2 bg-current" />
            {mark.label} {mark.value}%
          </button>
        ))}
      </div>
      <span className="w-9 shrink-0 text-right text-xs tabular-nums text-muted-foreground">{value}%</span>
    </div>
  );
}
