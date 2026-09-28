import type { ReactNode } from "react";
import { Link, useLocation } from "wouter";
import { ExternalLink, Map as MapIcon } from "lucide-react";

import { cn } from "@/lib/utils";

const NAV = [
  { href: "/", label: "Overview" },
  { href: "/taxa", label: "Taxa" },
  { href: "/layers", label: "Layers" },
];

export default function Layout({ children }: { children: ReactNode }) {
  const [location] = useLocation();

  return (
    <div className="flex min-h-screen flex-col bg-background">
      <header className="sticky top-0 z-50 border-b border-border bg-card">
        <div className="mx-auto flex h-14 max-w-6xl items-center gap-6 px-4">
          <Link href="/" className="flex items-center gap-2">
            <MapIcon className="h-5 w-5 text-primary" />
            <span className="text-lg font-semibold tracking-tight">
              MycoMap <span className="text-primary">Atlas</span>
            </span>
          </Link>

          <nav className="flex items-center gap-1">
            {NAV.map((item) => {
              const active =
                item.href === "/" ? location === "/" : location.startsWith(item.href);
              return (
                <Link
                  key={item.href}
                  href={item.href}
                  className={cn(
                    "rounded-md px-3 py-1.5 text-sm font-medium transition-colors",
                    active
                      ? "bg-accent text-accent-foreground"
                      : "text-muted-foreground hover:text-foreground",
                  )}
                >
                  {item.label}
                </Link>
              );
            })}
          </nav>

          <a
            href="https://mycomap.org"
            target="_blank"
            rel="noreferrer"
            className="ml-auto flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground"
          >
            mycomap.org
            <ExternalLink className="h-3.5 w-3.5" />
          </a>
        </div>
      </header>

      <main className="mx-auto w-full max-w-6xl flex-1 px-4 py-8">{children}</main>

      <footer className="border-t border-border">
        <div className="mx-auto max-w-6xl px-4 py-6 text-xs text-muted-foreground">
          Phase 1 — models are trained only on DNA-validated MycoMap records.
          Maps here are aggregated to 0.1°; exact collection coordinates are
          never published.
        </div>
      </footer>
    </div>
  );
}
