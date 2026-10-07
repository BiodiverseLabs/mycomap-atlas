import type { ComponentType, ReactNode } from "react";
import { useQuery } from "@tanstack/react-query";
import { Link } from "wouter";
import {
  ArrowRight,
  Crosshair,
  Braces,
  Database,
  Dna,
  FlaskConical,
  Layers,
  Map as MapIcon,
  Mountain,
  SquareDashed,
  Users,
} from "lucide-react";

import { GithubMark } from "@/components/Common";
import { ImageOverlay, MapContainer, TileLayer } from "@/components/Leaflet";
import { Page } from "@/components/Layout";
import { SearchBox } from "@/components/Search";
import { Card, CardContent } from "@/components/ui/card";
import {
  ALGORITHM_LABELS,
  getModel,
  getModels,
  getStatus,
  mapUrl,
  type Model,
  type ModelSummary,
} from "@/lib/api";
import { GITHUB_URL } from "@/lib/contract";
import { formatNumber } from "@/lib/utils";
import { DevHint } from "@/components/DevHint";

type Icon = ComponentType<{ className?: string }>;

/** Bounds a map can be laid over: a map wrapped past 180° comes back unusable. */
function drawable(model: Model | null): boolean {
  const b = model?.bounds;
  return !!b && b.east - b.west > 1 && b.east - b.west < 180;
}

/** One of the best-supported forest maps, as a live preview of what Atlas makes. */
function FeaturedMap({ models }: { models?: ModelSummary[] }) {
  const candidates = (models ?? [])
    .filter((m) => m.map && m.algorithm === "rf")
    .sort((a, b) => (b.presences ?? 0) - (a.presences ?? 0))
    .slice(0, 5)
    .map((m) => m.taxon);
  const model = useQuery({
    queryKey: ["featured", candidates],
    enabled: candidates.length > 0,
    queryFn: async () => {
      for (const taxon of candidates) {
        const found = await getModel(taxon, "rf");
        if (drawable(found)) return found;
      }
      return null;
    },
  });
  const featured = model.data ? (models ?? []).find((m) => m.taxon === model.data!.taxon && m.algorithm === "rf") : undefined;
  const b = model.data?.bounds;

  return (
    <Card className="overflow-hidden shadow-lg">
      <div className="relative h-[320px] bg-[#f8f5f0]">
        {featured && b ? (
          <MapContainer
            bounds={[[b.south, b.west], [b.north, b.east]]}
            className="h-full w-full"
            zoomControl={false}
            scrollWheelZoom={false}
            dragging={false}
            doubleClickZoom={false}
          >
            <TileLayer
              attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
              url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
            />
            <ImageOverlay
              url={mapUrl(featured.taxon, "rf", model.data?.map_drawn_at ?? model.data?.built_at)}
              bounds={[[b.south, b.west], [b.north, b.east]]}
              opacity={0.8}
            />
          </MapContainer>
        ) : (
          <div className="flex h-full items-center justify-center text-sm text-muted-foreground">
            <MapIcon className="mr-2 h-5 w-5" /> Habitat map
          </div>
        )}
      </div>
      {featured && (
        <Link
          href={`/taxa/${encodeURIComponent(featured.taxon)}`}
          className="flex items-center justify-between gap-3 border-t border-[#A87146]/10 px-4 py-3 text-sm hover:bg-myco-green/5"
        >
          <span>
            <span className="sci font-semibold text-[#4a3728]">{featured.taxon}</span>
            <span className="block text-xs text-muted-foreground">
              {ALGORITHM_LABELS.rf} · {formatNumber(featured.presences)} presence cells
            </span>
          </span>
          <ArrowRight className="h-4 w-4 text-myco-green" />
        </Link>
      )}
    </Card>
  );
}

function BigStat({ value, label }: { value: ReactNode; label: string }) {
  return (
    <div>
      <div className="font-display text-3xl text-[#4a3728] tabular-nums md:text-4xl">{value}</div>
      <div className="mt-1 text-sm text-[#5c4a3a]">{label}</div>
    </div>
  );
}

const PRINCIPLES: { icon: Icon; title: string; text: string }[] = [
  {
    icon: Dna,
    title: "DNA-confirmed names only",
    text: "Every map is trained on collections whose identity was confirmed by sequencing. No photo IDs, no herbarium names that may carry an old species concept.",
  },
  {
    icon: SquareDashed,
    title: "Corrected for where people look",
    text: "Each species is compared with every other sequenced collection, so a map learns the fungus's habitat rather than where MycoMap members happen to live.",
  },
  {
    icon: Mountain,
    title: "Tested on regions it never saw",
    text: "Scores come from holding out whole 200 km blocks of the continent. A model cannot pass by memorising one wood.",
  },
  {
    icon: Layers,
    title: "Three models, side by side",
    text: "Maxent, boosted trees and a random forest, fitted to the same records. Where they agree, trust the pattern; where they part, the map says so.",
  },
];

const USES: { icon: Icon; title: string; text: string; href: string; cta: string; external?: boolean }[] = [
  {
    icon: MapIcon,
    title: "Explore the maps",
    text: "Search any fungus and compare its habitat maps, scores and collection cells.",
    href: "/maps",
    cta: "Browse maps",
  },
  {
    icon: Braces,
    title: "Build on the API",
    text: "Every map, score and count as JSON, with an OpenAPI description and examples in R, Python and JavaScript.",
    href: "/developers",
    cta: "API reference",
  },
  {
    icon: Database,
    title: "Take the data",
    text: "Each stage of the pipeline, from predictor layers to suitability rasters, with its source and licence.",
    href: "/sources",
    cta: "Data and sources",
  },
  {
    icon: Crosshair,
    title: "What could grow here?",
    text: "Pick any place and see every mapped fungus its habitat suits, and which have been collected nearby.",
    href: "/here",
    cta: "Explore a place",
  },
  {
    icon: GithubMark,
    title: "Reproduce or improve it",
    text: "GPL code, a pinned container and tests for every rule. Fork it, run it for your region, send a pull request.",
    href: GITHUB_URL,
    cta: "View on GitHub",
    external: true,
  },
  {
    icon: FlaskConical,
    title: "Add the records",
    text: "The fastest way to improve a map is a sequenced collection from somewhere new. MycoMap sequences for free.",
    href: "https://mycomap.org/network",
    cta: "Free sequencing",
    external: true,
  },
];

const AUDIENCES: { icon: Icon; title: string; text: string }[] = [
  {
    icon: Users,
    title: "For conservation",
    text: "Where could a rare species still be found, and which records extend its known habitat? mycomap.org's conservation metrics will come from here.",
  },
  {
    icon: MapIcon,
    title: "For surveys and forays",
    text: "Point sampling at ground a species should like but where nobody has collected — the records that improve its map the most.",
  },
  {
    icon: FlaskConical,
    title: "For research and apps",
    text: "A reproducible, citable baseline with its data and scores, and an API to plug into identification tools as a geographic prior.",
  },
];

export default function Home() {
  const status = useQuery({ queryKey: ["status"], queryFn: getStatus });
  const models = useQuery({ queryKey: ["models"], queryFn: getModels });
  const mappedModels = (models.data ?? []).filter((m) => m.map);
  const mapped = new Set(mappedModels.map((m) => m.taxon));

  return (
    <>
      <section className="relative overflow-hidden border-b border-[#A87146]/10 bg-gradient-to-b from-[#f8f5f0] to-white">
        <div className="container mx-auto grid items-center gap-10 px-4 py-12 sm:px-6 lg:grid-cols-[1.1fr_1fr] lg:px-8 lg:py-16">
          <div className="min-w-0 space-y-6">
            <div className="flex flex-wrap gap-2 text-xs font-semibold uppercase tracking-wider text-[#7a4e2c]">
              {["Open source", "DNA-validated", "North America"].map((tag) => (
                <span key={tag} className="rounded-full border border-[#A87146]/30 bg-white px-3 py-1">
                  {tag}
                </span>
              ))}
            </div>
            <h1 className="font-display text-4xl leading-tight text-[#4a3728] md:text-5xl">
              An open habitat atlas for North America&rsquo;s fungi
            </h1>
            <p className="max-w-xl text-lg text-[#5c4a3a] leading-relaxed">
              Atlas maps where every well-recorded fungus can grow, trained only on collections whose
              names were confirmed by DNA. The maps, the method, the code and the data are open — a
              shared foundation anyone can use, check and build on.
            </p>
            <SearchBox variant="hero" />
            <div className="flex flex-wrap gap-3 text-sm">
              <Link
                href="/maps"
                className="inline-flex items-center gap-2 rounded-md bg-myco-green px-4 py-2 font-semibold text-white hover:bg-myco-green/90"
              >
                Explore the maps <ArrowRight className="h-4 w-4" />
              </Link>
              <Link
                href="/here"
                className="inline-flex items-center gap-2 rounded-md border border-[#A87146]/30 bg-white px-4 py-2 font-semibold text-[#4a3728] hover:border-myco-green"
              >
                <Crosshair className="h-4 w-4 text-myco-green" /> What could grow here?
              </Link>
              <Link
                href="/methods"
                className="inline-flex items-center gap-2 rounded-md border border-[#A87146]/30 bg-white px-4 py-2 font-semibold text-[#4a3728] hover:border-myco-green"
              >
                How it works
              </Link>
              <a
                href={GITHUB_URL}
                className="inline-flex items-center gap-2 rounded-md border border-[#A87146]/30 bg-white px-4 py-2 font-semibold text-[#4a3728] hover:border-myco-green"
              >
                <GithubMark /> GitHub
              </a>
            </div>
          </div>
          <FeaturedMap models={models.data} />
        </div>
      </section>

      <Page>
        <section className="grid grid-cols-2 gap-6 border-b border-[#A87146]/10 pb-8 md:grid-cols-4">
          <BigStat value={formatNumber(status.data?.records)} label="DNA-validated collections" />
          <BigStat value={formatNumber(status.data?.taxa)} label="taxa recorded" />
          <BigStat value={models.data ? formatNumber(mapped.size) : "—"} label="taxa with habitat maps" />
          <BigStat value={models.data ? formatNumber(mappedModels.length) : "—"} label="fitted models" />
        </section>

        <section>
          <h2 className="font-display text-3xl text-[#4a3728]">Built to be trusted</h2>
          <p className="mt-2 max-w-3xl text-[#5c4a3a] leading-relaxed">
            Most distribution maps for fungi inherit two problems: names that may be wrong, and
            records that show where mycologists live. Atlas is designed around both.
          </p>
          <div className="mt-6 grid gap-4 md:grid-cols-2 lg:grid-cols-4">
            {PRINCIPLES.map(({ icon: Icon, title, text }) => (
              <Card key={title}>
                <CardContent className="p-5">
                  <Icon className="h-6 w-6 text-myco-green" />
                  <h3 className="mt-3 font-semibold text-[#4a3728]">{title}</h3>
                  <p className="mt-1 text-sm text-[#5c4a3a] leading-relaxed">{text}</p>
                </CardContent>
              </Card>
            ))}
          </div>
        </section>

        <section>
          <h2 className="font-display text-3xl text-[#4a3728]">A foundation to build on</h2>
          <p className="mt-2 max-w-3xl text-[#5c4a3a] leading-relaxed">
            Atlas is meant to be the base layer other fungal work stands on: conservation
            assessments, survey planning, identification apps, research. Take what you need.
          </p>
          <div className="mt-6 grid gap-4 md:grid-cols-2 lg:grid-cols-3">
            {USES.map(({ icon: Icon, title, text, href, cta, external }) => {
              const body = (
                <Card className="h-full transition-colors group-hover:border-myco-green/50">
                  <CardContent className="flex h-full flex-col p-5">
                    <Icon className="h-6 w-6 text-myco-green" />
                    <h3 className="mt-3 font-semibold text-[#4a3728]">{title}</h3>
                    <p className="mt-1 flex-1 text-sm text-[#5c4a3a] leading-relaxed">{text}</p>
                    <span className="mt-3 inline-flex items-center gap-1 text-sm font-semibold text-myco-green">
                      {cta} <ArrowRight className="h-4 w-4" />
                    </span>
                  </CardContent>
                </Card>
              );
              return external ? (
                <a key={title} href={href} className="group">
                  {body}
                </a>
              ) : (
                <Link key={title} href={href} className="group">
                  {body}
                </Link>
              );
            })}
          </div>
        </section>

        <section className="overflow-hidden rounded-xl bg-gradient-to-br from-[#8a5c3a] to-myco-brown p-8 text-white md:p-10">
          <div className="grid gap-8 md:grid-cols-[1.4fr_1fr]">
            <div>
              <h2 className="font-display text-3xl">Open by design</h2>
              <p className="mt-3 text-white/85 leading-relaxed">
                The code is GPL-3.0. The API is described in OpenAPI and tested against the server,
                so its documentation cannot drift. Every package and dataset is credited with a link.
                Each release records the exact code, packages, layers and records behind every map,
                so any map can be rebuilt.
              </p>
              <p className="mt-3 text-white/85 leading-relaxed">
                One thing stays private: exactly where a collection was made. Collections are shown
                only as 0.1° cells, and nothing published is finer than 1 km.
              </p>
            </div>
            <div className="flex flex-col justify-center gap-3">
              <a
                href={GITHUB_URL}
                className="inline-flex items-center justify-center gap-2 rounded-md bg-white px-4 py-3 font-semibold text-[#4a3728] hover:bg-[#f8f5f0]"
              >
                <GithubMark /> Star or fork on GitHub
              </a>
              <Link
                href="/developers"
                className="inline-flex items-center justify-center gap-2 rounded-md border border-white/40 px-4 py-3 font-semibold text-white hover:bg-white/10"
              >
                <Braces className="h-4 w-4" /> Use the API
              </Link>
            </div>
          </div>
        </section>

        <section className="grid gap-6 md:grid-cols-3">
          {AUDIENCES.map(({ icon: Icon, title, text }) => (
            <div key={title} className="flex gap-3">
              <Icon className="mt-1 h-5 w-5 shrink-0 text-myco-green" />
              <div>
                <h3 className="font-semibold text-[#4a3728]">{title}</h3>
                <p className="mt-1 text-sm text-[#5c4a3a] leading-relaxed">{text}</p>
              </div>
            </div>
          ))}
        </section>

        {status.isError && (
          <p className="text-sm text-muted-foreground">
            Live figures are unavailable right now: the map service is not answering.
            <DevHint command="./atlas api" />
          </p>
        )}
      </Page>
    </>
  );
}
