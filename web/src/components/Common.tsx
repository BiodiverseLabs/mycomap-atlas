import { useEffect, useId, useLayoutEffect, useRef, useState, type ReactNode } from "react";
import { createPortal } from "react-dom";
import { CircleHelp } from "lucide-react";

import { Card, CardContent } from "@/components/ui/card";

/** A figure with its label, as on Vision's and .org's stat panels. */
export function Stat({ label, value, hint }: { label: string; value: ReactNode; hint?: ReactNode }) {
  return (
    <Card>
      <CardContent className="p-4">
        <div className="text-xs uppercase tracking-wider text-muted-foreground">{label}</div>
        <div className="mt-1 text-2xl font-semibold text-[#4a3728] tabular-nums">
          {value}
          {hint && <span className="ml-1 text-sm font-normal text-muted-foreground">{hint}</span>}
        </div>
      </CardContent>
    </Card>
  );
}

/** What to do when the development API is not running. */
export function ApiDown() {
  return (
    <Card>
      <CardContent className="p-6">
        <h2 className="text-lg font-semibold text-[#4a3728]">The API is not answering</h2>
        <p className="mt-2 text-sm text-muted-foreground">
          Start it from the repository root, then reload:
        </p>
        <pre className="mt-3 rounded-md bg-muted p-3 text-sm">./atlas api</pre>
      </CardContent>
    </Card>
  );
}

/** Table header cell, in Vision's style. */
export function Th({ children, right }: { children: ReactNode; right?: boolean }) {
  return (
    <th className={`${right ? "text-right" : "text-left"} font-medium px-4 py-2`}>{children}</th>
  );
}

/** Blocked AUC, coloured by what it means rather than by how high it is. */
export function Auc({ value }: { value?: number | null }) {
  if (value == null || !Number.isFinite(value)) {
    return <span className="text-muted-foreground">—</span>;
  }
  const tone =
    value >= 0.7 ? "text-myco-green font-semibold" : value < 0.55 ? "text-muted-foreground" : "";
  return <span className={`tabular-nums ${tone}`}>{value.toFixed(2)}</span>;
}

export function Loading() {
  return <p className="text-sm text-muted-foreground">Loading…</p>;
}

/**
 * GitHub's mark, drawn here rather than taken from lucide, which drops brand
 * icons in its 1.x releases.
 */
export function GithubMark({ className = "h-4 w-4" }: { className?: string }) {
  return (
    <svg viewBox="0 0 16 16" className={className} fill="currentColor" aria-hidden="true">
      <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z" />
    </svg>
  );
}

/**
 * A question mark that explains the thing next to it. Hover or focus shows the
 * note; a click (or tap) keeps it open until Esc or a click elsewhere. The
 * note is drawn in a portal so a scrolling table cannot clip it.
 */
export function Help({ label, children }: { label: string; children: ReactNode }) {
  const [hovered, setHovered] = useState(false);
  const [pinned, setPinned] = useState(false);
  const [place, setPlace] = useState<{ left: number; top?: number; bottom?: number } | null>(null);
  const button = useRef<HTMLButtonElement>(null);
  const note = useRef<HTMLDivElement>(null);
  const id = useId();
  const shown = hovered || pinned;

  useLayoutEffect(() => {
    if (!shown) return;
    const position = () => {
      const at = button.current?.getBoundingClientRect();
      if (!at) return;
      const width = Math.min(320, window.innerWidth - 32);
      const left = Math.max(16, Math.min(at.left, window.innerWidth - 16 - width));
      // Below the mark when there is room, otherwise above it.
      setPlace(
        window.innerHeight - at.bottom > 220
          ? { left, top: at.bottom + 6 }
          : { left, bottom: window.innerHeight - at.top + 6 },
      );
    };
    position();
    window.addEventListener("scroll", position, true);
    window.addEventListener("resize", position);
    return () => {
      window.removeEventListener("scroll", position, true);
      window.removeEventListener("resize", position);
    };
  }, [shown]);

  useEffect(() => {
    if (!pinned) return;
    const close = (event: Event) => {
      const target = event.target as Node;
      if (button.current?.contains(target) || note.current?.contains(target)) return;
      setPinned(false);
    };
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") setPinned(false);
    };
    document.addEventListener("pointerdown", close);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("pointerdown", close);
      document.removeEventListener("keydown", onKey);
    };
  }, [pinned]);

  return (
    <>
      <button
        ref={button}
        type="button"
        aria-label={`What does ${label} mean?`}
        aria-expanded={shown}
        aria-describedby={shown ? id : undefined}
        onClick={() => setPinned((p) => !p)}
        onMouseEnter={() => setHovered(true)}
        onMouseLeave={() => setHovered(false)}
        onFocus={() => setHovered(true)}
        onBlur={() => setHovered(false)}
        className="ml-1 inline-flex align-middle rounded-full text-muted-foreground hover:text-myco-green focus-visible:outline focus-visible:outline-2 focus-visible:outline-myco-green"
      >
        <CircleHelp className="h-3.5 w-3.5" />
      </button>
      {shown &&
        place &&
        createPortal(
          <div
            ref={note}
            id={id}
            role="tooltip"
            style={{ position: "fixed", left: place.left, top: place.top, bottom: place.bottom }}
            className="z-[2000] w-[min(320px,calc(100vw-32px))] rounded-md border border-[#A87146]/20 bg-white p-3 text-left text-xs font-normal normal-case tracking-normal leading-relaxed text-[#5c4a3a] shadow-lg"
          >
            <div className="mb-1 font-semibold text-[#4a3728]">{label}</div>
            {children}
          </div>,
          document.body,
        )}
    </>
  );
}
