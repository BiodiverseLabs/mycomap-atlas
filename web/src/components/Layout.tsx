import { useState, type ReactNode } from "react";
import { Link, useLocation } from "wouter";
import { ArrowUpRight, LogIn, Menu, X } from "lucide-react";

import { GithubMark } from "@/components/Common";
import { SearchButton, SearchPalette, useSearchPalette } from "@/components/Search";
import { GITHUB_URL } from "@/lib/contract";
import { signInHere, useMe, useSignOut } from "@/lib/session";

// Header and footer follow mycomap.org's PublicLayout and MainNavigation, the
// same way MycoMap Vision does, so someone moving between the three sites feels
// they never left: sticky white header, logo with "MycoMap" in brown, grey
// links that turn myco-green, brown gradient footer, cream page-title band.

const NAV = [
  { href: "/maps", label: "Maps" },
  { href: "/here", label: "Explore" },
  { href: "/models", label: "Models" },
  { href: "/taxa", label: "Taxa" },
  { href: "/methods", label: "Methods" },
  { href: "/data", label: "Data" },
  { href: "/sources", label: "Sources" },
  { href: "/developers", label: "Developers" },
];

export default function Layout({ children }: { children: ReactNode }) {
  return (
    <div className="relative min-h-screen flex flex-col bg-white">
      <Header />
      <main className="flex-1 relative bg-white">{children}</main>
      <Footer />
    </div>
  );
}

function Header() {
  const [location] = useLocation();
  const [open, setOpen] = useState(false);
  // Search opens from here, or with / or Ctrl+K on any page.
  const palette = useSearchPalette();
  const isActive = (href: string) => (href === "/" ? location === "/" : location.startsWith(href));
  const cls = (href: string) =>
    `px-3 xl:px-2 2xl:px-3 py-2 rounded-md text-sm font-medium transition-colors ${
      isActive(href)
        ? "bg-myco-green/10 text-myco-green"
        : "text-gray-700 hover:text-myco-green hover:bg-myco-green/5"
    }`;
  return (
    <>
    <header className="sticky top-0 z-50 w-full border-b border-myco-brown/10 bg-white/95 backdrop-blur supports-[backdrop-filter]:bg-white/80">
      <div className="container mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex h-16 items-center justify-between">
          <div className="flex items-center gap-8">
            <Link href="/" className="flex items-center gap-3">
              <img src="/mycomap-logo.png" alt="MycoMap Logo" className="h-10 w-auto" />
              <span className="hidden sm:flex items-baseline gap-2">
                <span className="text-xl font-semibold text-myco-brown">MycoMap</span>
                <span className="text-xl font-semibold text-myco-green">Atlas</span>
              </span>
            </Link>
            <nav className="hidden xl:flex items-center gap-1">
              {NAV.map((n) => (
                <Link key={n.href} href={n.href} className={cls(n.href)}>
                  {n.label}
                </Link>
              ))}
            </nav>
          </div>
          <div className="flex items-center gap-2">
            <SearchButton onOpen={() => palette.setOpen(true)} />
            <a
              href={GITHUB_URL}
              className="p-2 rounded-md text-gray-700 hover:text-myco-green hover:bg-myco-green/5"
              aria-label="Source code on GitHub"
              title="Source code on GitHub"
            >
              <GithubMark className="h-5 w-5" />
            </a>
            <a
              href="https://mycomap.org"
              // Room for the search box: this link is in the menu and footer too.
              className="hidden 2xl:inline-flex items-center gap-1 px-3 py-2 rounded-md text-sm font-medium text-gray-700 hover:text-myco-green hover:bg-myco-green/5"
            >
              mycomap.org <ArrowUpRight className="h-3.5 w-3.5" />
            </a>
            <Account />
            <button
              className="xl:hidden p-2 rounded-md text-gray-700 hover:bg-myco-green/5"
              onClick={() => setOpen(!open)}
              aria-label="Menu"
            >
              {open ? <X className="h-5 w-5" /> : <Menu className="h-5 w-5" />}
            </button>
          </div>
        </div>
        {open && (
          <nav className="xl:hidden pb-3 flex flex-col gap-1" onClick={() => setOpen(false)}>
            {NAV.map((n) => (
              <Link key={n.href} href={n.href} className={cls(n.href)}>
                {n.label}
              </Link>
            ))}
            <a href="https://mycomap.org" className={cls("#")}>
              mycomap.org
            </a>
          </nav>
        )}
      </div>
    </header>
    {/* Outside the header: its backdrop blur would pin a fixed overlay inside it. */}
    <SearchPalette open={palette.open} onClose={() => palette.setOpen(false)} />
    </>
  );
}

/**
 * Sign in with a mycomap.org account, or who is signed in and a way out.
 * Hidden on a copy of Atlas that cannot sign anyone in.
 */
function Account() {
  const me = useMe();
  const signOut = useSignOut();
  // Re-read on every navigation, so the link comes back to the current page.
  useLocation();
  if (me.signedIn && me.via === "session") {
    return (
      <div className="flex items-center gap-1">
        <span className="hidden md:inline max-w-[12rem] truncate px-2 text-sm text-[#4a3728]" title={me.name}>
          {me.name ?? "Signed in"}
        </span>
        <button
          onClick={() => void signOut()}
          className="px-3 py-2 rounded-md text-sm font-medium text-gray-700 hover:text-myco-green hover:bg-myco-green/5"
        >
          Sign out
        </button>
      </div>
    );
  }
  if (!me.signInAvailable) return null;
  return (
    <a
      href={signInHere()}
      className="inline-flex items-center gap-1.5 px-3 py-2 rounded-md text-sm font-medium text-myco-green hover:bg-myco-green/5"
      title="Sign in with your mycomap.org account"
    >
      <LogIn className="h-4 w-4" /> Sign in
    </a>
  );
}

function Footer() {
  return (
    <footer className="relative overflow-hidden mt-16">
      <div className="absolute top-0 left-0 right-0 h-1 bg-gradient-to-r from-transparent via-myco-green to-transparent" />
      <div className="absolute inset-0 bg-gradient-to-b from-[#8a5c3a] to-myco-brown" />
      <div className="relative z-10 container mx-auto px-4 sm:px-6 lg:px-8 py-10">
        <div className="flex flex-col md:flex-row justify-between gap-6">
          <div className="max-w-md">
            <div className="flex items-center gap-3 mb-3">
              <img src="/mycomap-logo.png" alt="" className="h-9 w-auto brightness-0 invert" />
              <span className="text-lg font-bold text-white">MycoMap Atlas</span>
            </div>
            <p className="text-white/70 text-sm leading-relaxed">
              An open habitat atlas for North America&rsquo;s fungi, modelled only from
              DNA-validated MycoMap records. Early development: maps are provisional and drawn at
              5 km.
            </p>
          </div>
          <ul className="space-y-2 text-sm">
            {[
              ["https://mycomap.org", "MycoMap.org"],
              ["https://mycomap.org/network", "Free sequencing"],
              ["https://mycomap.org/protocols", "Participation protocols"],
              ["/methods", "Methods"],
              ["/sources", "Data and sources"],
              ["/developers", "API for developers"],
              [GITHUB_URL, "Source code (GPL-3.0)"],
            ].map(([href, label]) => (
              <li key={href}>
                <a href={href} className="text-white/70 hover:text-myco-green transition-colors">
                  {label}
                </a>
              </li>
            ))}
          </ul>
        </div>
        <div className="border-t border-white/10 mt-8 pt-4 text-white/50 text-sm space-y-1">
          <p>
            Maps and model outputs:{" "}
            <a href="https://creativecommons.org/licenses/by-sa/4.0/" className="underline hover:text-myco-green">
              CC BY-SA 4.0
            </a>
            , as they derive from WorldClim. Code: GPL-3.0-or-later.
          </p>
          <p>
            Data: WorldClim 2.1 (CC BY-SA 4.0); SoilGrids 2.0, ESA WorldCover, NALCMS Land Cover
            2020 and Copernicus Global Land Cover (CC BY 4.0); USFS FIA BIGMAP (public domain).
            Contains information licensed under the Open Government Licence – Canada (National
            Forest Inventory). Basemap © OpenStreetMap contributors (ODbL).{" "}
            <a href="/sources" className="underline hover:text-myco-green">Every source</a>.
          </p>
          <p>Collection locations are shown only as 0.1° cells. &copy; {new Date().getFullYear()} MycoMap.org.</p>
        </div>
      </div>
    </footer>
  );
}

export function PageHeader({ title, children }: { title: ReactNode; children?: ReactNode }) {
  return (
    <div className="bg-[#f8f5f0] border-b border-[#A87146]/10">
      <div className="container mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <h1 className="font-display text-3xl md:text-4xl text-[#4a3728]">{title}</h1>
        {children && <div className="mt-2 text-[#5c4a3a] max-w-3xl">{children}</div>}
      </div>
    </div>
  );
}

/** The page body under a PageHeader, on the same container. */
export function Page({ children }: { children: ReactNode }) {
  return (
    <div className="container mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-8">{children}</div>
  );
}

/** A section heading, as on Vision's pages. */
export function SectionTitle({ children }: { children: ReactNode }) {
  return <h2 className="font-display text-2xl text-[#4a3728] mb-3">{children}</h2>;
}
