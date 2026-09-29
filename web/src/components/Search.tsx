import { useEffect, useId, useRef, useState } from "react";
import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { useLocation } from "wouter";
import { ArrowRight, CornerDownLeft, Search as SearchIcon, X } from "lucide-react";

import { searchTaxa, type SearchGenus, type SearchSpecies } from "@/lib/api";
import { formatNumber } from "@/lib/utils";

// One search, everywhere: the palette opened from the header (or with / and
// Ctrl+K from any page) and the big box on the home page share the matching,
// the results and the keys. The server does the forgiving part (typos, the
// many spellings of a provisional code); this file is about getting there
// with the fewest keystrokes.

function useDebounced<T>(value: T, ms: number): T {
  const [settled, setSettled] = useState(value);
  useEffect(() => {
    const timer = setTimeout(() => setSettled(value), ms);
    return () => clearTimeout(timer);
  }, [value, ms]);
  return settled;
}

/** A result the keyboard can land on. */
type Item =
  | { kind: "genus"; genus: SearchGenus; href: string }
  | { kind: "species"; species: SearchSpecies; href: string }
  | { kind: "all"; text: string; href: string };

const taxonHref = (name: string) => `/taxa/${encodeURIComponent(name)}`;
const listHref = (text: string) => `/taxa?q=${encodeURIComponent(text)}`;

function useResults(text: string) {
  const search = useDebounced(text.trim(), 150);
  const query = useQuery({
    queryKey: ["search", search],
    enabled: search.length >= 2,
    queryFn: () => searchTaxa(search, 8),
    placeholderData: keepPreviousData,
    staleTime: 60_000,
  });
  const items: Item[] = [];
  if (search.length >= 2 && query.data) {
    for (const genus of query.data.genera) {
      items.push({ kind: "genus", genus, href: listHref(genus.genus) });
    }
    for (const species of query.data.species) {
      items.push({ kind: "species", species, href: taxonHref(species.scientific_name) });
    }
    items.push({ kind: "all", text: search, href: listHref(search) });
  }
  return { search, query, items };
}

function MapCount({ species }: { species: SearchSpecies }) {
  if (species.models.length) {
    return (
      <span className="rounded-full bg-myco-green/15 px-2 py-0.5 text-[11px] font-semibold text-[#2e5a17]">
        {species.models.length === 1 ? "1 map" : `${species.models.length} maps`}
      </span>
    );
  }
  return <span className="text-[11px] text-muted-foreground">no map yet</span>;
}

function ResultRow({ item, active, id }: { item: Item; active: boolean; id: string }) {
  const base = `flex w-full items-center justify-between gap-3 px-4 py-2 text-left text-sm ${
    active ? "bg-myco-green/10" : "hover:bg-myco-green/5"
  }`;
  if (item.kind === "genus") {
    const g = item.genus;
    return (
      <div id={id} className={base}>
        <span className="min-w-0">
          <span className="sci font-semibold text-[#4a3728]">{g.genus}</span>
          <span className="ml-2 text-xs text-muted-foreground">genus</span>
        </span>
        <span className="shrink-0 text-xs text-muted-foreground">
          {formatNumber(g.taxa)} taxa{g.mapped ? ` · ${formatNumber(g.mapped)} mapped` : ""}
        </span>
      </div>
    );
  }
  if (item.kind === "species") {
    const s = item.species;
    return (
      <div id={id} className={base}>
        <span className="min-w-0 truncate">
          {s.match === "similar" && <span className="mr-1 text-xs text-muted-foreground">Did you mean</span>}
          <span className="sci text-[#4a3728]">{s.scientific_name}</span>
        </span>
        <span className="flex shrink-0 items-center gap-2 text-xs text-muted-foreground">
          <span className="hidden sm:inline">{formatNumber(s.localities)} places</span>
          <MapCount species={s} />
        </span>
      </div>
    );
  }
  return (
    <div id={id} className={`${base} border-t border-gray-100 text-muted-foreground`}>
      <span>
        Every taxon matching &ldquo;<span className="text-[#4a3728]">{item.text}</span>&rdquo;
      </span>
      <ArrowRight className="h-4 w-4" />
    </div>
  );
}

/**
 * The input and its results. In the palette the results sit under the box;
 * on the home page they drop down over the page.
 */
export function SearchBox({
  variant,
  autoFocus,
  onDone,
}: {
  variant: "palette" | "hero";
  autoFocus?: boolean;
  onDone?: () => void;
}) {
  const [text, setText] = useState("");
  const [active, setActive] = useState(0);
  const [open, setOpen] = useState(false);
  const [, navigate] = useLocation();
  const { search, query, items } = useResults(text);
  const listId = useId();
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => setActive(0), [search]);
  useEffect(() => {
    if (autoFocus) inputRef.current?.focus();
  }, [autoFocus]);

  const go = (item?: Item) => {
    if (!item) return;
    navigate(item.href);
    setText("");
    setOpen(false);
    onDone?.();
  };

  const showing = variant === "palette" || open;
  const noMatch = search.length >= 2 && query.data && !query.data.species.length && !query.data.genera.length;

  const results = search.length >= 2 && (
    <div
      id={listId}
      role="listbox"
      aria-label="Search results"
      className={
        variant === "palette"
          ? "max-h-[60vh] overflow-y-auto border-t border-gray-100"
          : "absolute z-[1500] mt-1 max-h-[70vh] w-full overflow-y-auto rounded-lg border border-gray-100 bg-white shadow-lg"
      }
    >
      {query.isLoading && <p className="px-4 py-3 text-sm text-muted-foreground">Searching…</p>}
      {query.isError && <p className="px-4 py-3 text-sm text-muted-foreground">Search is unavailable right now.</p>}
      {noMatch && (
        <p className="px-4 py-3 text-sm text-muted-foreground">
          No DNA-validated records under a name like that. Atlas knows scientific names only, not
          common names.
        </p>
      )}
      {!noMatch &&
        items.map((item, index) => (
          <div
            key={`${item.kind}:${item.href}`}
            role="option"
            aria-selected={index === active}
            onMouseEnter={() => setActive(index)}
            onMouseDown={(event) => {
              // Before the input's blur closes the list.
              event.preventDefault();
              go(item);
            }}
            className="cursor-pointer"
          >
            <ResultRow item={item} active={index === active} id={`${listId}-${index}`} />
          </div>
        ))}
    </div>
  );

  return (
    <div className={variant === "hero" ? "relative w-full max-w-xl" : "w-full"}>
      <div className="relative">
        <SearchIcon
          className={`absolute left-4 text-muted-foreground ${variant === "hero" ? "top-3.5 h-5 w-5" : "top-4 h-5 w-5"}`}
        />
        <input
          ref={inputRef}
          value={text}
          onChange={(event) => {
            setText(event.target.value);
            setOpen(true);
          }}
          onFocus={() => setOpen(true)}
          onBlur={() => setOpen(false)}
          onKeyDown={(event) => {
            if (event.key === "ArrowDown") {
              event.preventDefault();
              setActive((i) => Math.min(i + 1, Math.max(items.length - 1, 0)));
            } else if (event.key === "ArrowUp") {
              event.preventDefault();
              setActive((i) => Math.max(i - 1, 0));
            } else if (event.key === "Enter") {
              event.preventDefault();
              go(items[active] ?? (search.length >= 2 ? { kind: "all", text: search, href: listHref(search) } : undefined));
            } else if (event.key === "Escape") {
              if (text) setText("");
              else onDone?.();
            }
          }}
          role="combobox"
          aria-expanded={showing && search.length >= 2}
          aria-controls={listId}
          aria-activedescendant={items.length ? `${listId}-${active}` : undefined}
          aria-autocomplete="list"
          placeholder={
            variant === "hero"
              ? "Find a fungus — try Amanita muscaria"
              : "Search species, genera or provisional codes…"
          }
          className={
            variant === "hero"
              ? "h-12 w-full rounded-lg border border-[#A87146]/25 bg-white pl-11 pr-3 text-base shadow-sm outline-none focus:ring-2 focus:ring-myco-green"
              : "h-14 w-full bg-transparent pl-12 pr-12 text-base outline-none"
          }
          aria-label="Search for a taxon"
          autoComplete="off"
          spellCheck={false}
        />
        {variant === "palette" && (
          <button
            type="button"
            onClick={() => onDone?.()}
            className="absolute right-3 top-3.5 rounded p-1 text-muted-foreground hover:bg-myco-green/5"
            aria-label="Close search"
          >
            <X className="h-5 w-5" />
          </button>
        )}
      </div>
      {showing && results}
    </div>
  );
}

/** Whether a key press is someone typing into a field, where / must stay a slash. */
function typing(target: EventTarget | null): boolean {
  const el = target as HTMLElement | null;
  if (!el) return false;
  return el.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(el.tagName);
}

/** The search palette, and the keys that open it from any page. */
export function useSearchPalette() {
  const [open, setOpen] = useState(false);
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      const combo = (event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "k";
      if (combo || (event.key === "/" && !typing(event.target))) {
        event.preventDefault();
        setOpen(true);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);
  return { open, setOpen };
}

export function SearchPalette({ open, onClose }: { open: boolean; onClose: () => void }) {
  if (!open) return null;
  return (
    <div
      className="fixed inset-0 z-[2000] flex items-start justify-center bg-[#2b211a]/40 px-3 pt-[10vh] backdrop-blur-sm"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
      role="dialog"
      aria-modal="true"
      aria-label="Search"
    >
      <div className="w-full max-w-xl overflow-hidden rounded-xl bg-white shadow-2xl">
        <SearchBox variant="palette" autoFocus onDone={onClose} />
        <div className="flex items-center gap-4 border-t border-gray-100 bg-[#f8f5f0] px-4 py-2 text-[11px] text-muted-foreground">
          <span>
            <kbd className="rounded border bg-white px-1">↑</kbd> <kbd className="rounded border bg-white px-1">↓</kbd> to move
          </span>
          <span className="inline-flex items-center gap-1">
            <kbd className="rounded border bg-white px-1">
              <CornerDownLeft className="inline h-3 w-3" />
            </kbd>{" "}
            to open
          </span>
          <span>
            <kbd className="rounded border bg-white px-1">esc</kbd> to close
          </span>
        </div>
      </div>
    </div>
  );
}

/** The header's way in: a box on wide screens, an icon on narrow ones. */
export function SearchButton({ onOpen }: { onOpen: () => void }) {
  const mac = typeof navigator !== "undefined" && /Mac|iPhone|iPad/.test(navigator.platform);
  return (
    <>
      <button
        type="button"
        onClick={onOpen}
        className="hidden md:inline-flex h-9 w-56 xl:w-44 2xl:w-56 items-center gap-2 rounded-md border border-[#A87146]/20 bg-[#f8f5f0]/60 px-3 text-sm text-muted-foreground hover:border-myco-green/50"
        aria-label="Search"
      >
        <SearchIcon className="h-4 w-4" />
        <span className="flex-1 text-left">Search taxa…</span>
        <kbd className="rounded border bg-white px-1.5 text-[11px]">{mac ? "⌘K" : "Ctrl K"}</kbd>
      </button>
      <button
        type="button"
        onClick={onOpen}
        className="md:hidden p-2 rounded-md text-gray-700 hover:bg-myco-green/5"
        aria-label="Search"
      >
        <SearchIcon className="h-5 w-5" />
      </button>
    </>
  );
}
