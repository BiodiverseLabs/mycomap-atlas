import { useEffect, useLayoutEffect, useRef, useState, type MutableRefObject } from "react";
import { useQueries, useQuery } from "@tanstack/react-query";
import { Link, useLocation, useParams, useSearch } from "wouter";
import type { LatLng, Map as LeafletMap } from "leaflet";
import { ArrowDown, ArrowUpRight, Download, LogIn, Maximize, Maximize2, Minimize, Minimize2 } from "lucide-react";

import { Help, Th } from "@/components/Common";
import { WhatDrives } from "@/components/WhatDrives";
import { MapStrength, defaultStrength } from "@/components/MapStrength";
import { ShareMap } from "@/components/ShareMap";
import { sparseFailedNote } from "@/lib/sparseSkill";
import { reachedFromNote, renamedTaxonPath } from "@/lib/renamed";
import { openingView } from "@/lib/mapView";
import { useFullscreen } from "@/components/Fullscreen";
import { CircleMarker, FitBounds, ImageOverlay, MapContainer, TileLayer, useMap } from "@/components/Leaflet";
import { Page, PageHeader, SectionTitle } from "@/components/Layout";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  ALGORITHMS,
  ALGORITHM_LABELS,
  ALGORITHM_MIN_PRESENCES,
  FULL_MODELS,
  SPARSE_MODELS,
  ensembleMapUrl,
  getCells,
  getEnsemble,
  getModel,
  getStatus,
  getTaxon,
  resolveName,
  mapUrl,
  rasterUrl,
  type Algorithm,
  type Cell,
  type Ensemble,
  type Model,
} from "@/lib/api";
import { signInHere, useMe } from "@/lib/session";
import { formatNumber, formatWhen } from "@/lib/utils";
import { DevHint } from "@/components/DevHint";

// The fewest sites any map is fitted from (the small-model ensemble's).
const PUBLISH_AT = 3;

type Bounds = [[number, number], [number, number]];

/** Maps that move together: pan or zoom one and the others follow. */
interface MapGroup {
  maps: Map<string, LeafletMap>;
  syncing: boolean;
}

function SyncWith({ group, id }: { group: MutableRefObject<MapGroup>; id: string }) {
  const map = useMap();
  useEffect(() => {
    const maps = group.current.maps;
    maps.set(id, map);
    const follow = () => {
      if (group.current.syncing) return;
      group.current.syncing = true;
      for (const [other, target] of maps) {
        if (other !== id) target.setView(map.getCenter(), map.getZoom(), { animate: false });
      }
      group.current.syncing = false;
    };
    map.on("move", follow);
    return () => {
      map.off("move", follow);
      maps.delete(id);
    };
  }, [map, group, id]);
  return null;
}

function Legend() {
  return (
    <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-muted-foreground">
      <span className="flex items-center gap-2">
        <span>Lowest-rated ground</span>
        <span
          className="h-2 w-24 rounded"
          style={{ background: "linear-gradient(to right, #f7f7e8, #94c440, #2e5a17)" }}
        />
        <span>Highest-rated</span>
      </span>
      <span
        className="flex items-center gap-2"
        title="Conditions unlike any surveyed site the model learned from: it cannot say anything there"
      >
        <span
          className="h-2 w-6 rounded"
          style={{
            background:
              "repeating-linear-gradient(135deg, rgba(140,140,125,0.55) 0 2px, rgba(140,140,125,0.12) 2px 6px)",
          }}
        />
        <span>No data like it</span>
      </span>
    </div>
  );
}

/**
 * A provisional name: a DNA lineage with a code rather than a published
 * species, such as Mycena sp. 'IN10' or Amanita "gemmata-CA01".
 */
export function isProvisionalName(name: string): boolean {
  return /["'‘’“”]|\bsp\.|-[A-Z]{2,}\d|\b[A-Z]{2,}\d{2}\b/.test(name);
}

/** The citation for a taxon's maps in the release this site serves. */
export function mapCitation(name: string, release: string, accessed: Date, origin: string): string {
  const year = release.slice(0, 4);
  const day = accessed.toISOString().slice(0, 10);
  return (
    `MycoMap Atlas (${year}). Habitat maps of ${name}, release ${release}. ` +
    `${origin}/taxa/${encodeURIComponent(name)} (accessed ${day}). CC BY-SA 4.0.`
  );
}

function CiteThisMap({ name }: { name: string }) {
  const status = useQuery({ queryKey: ["status"], queryFn: getStatus });
  const [copied, setCopied] = useState(false);
  const release = status.data?.release?.id;
  if (!release) return null;
  const text = mapCitation(name, release, new Date(), window.location.origin);
  const copy = async () => {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 2000);
    } catch {
      setCopied(false);
    }
  };
  return (
    <p className="text-xs text-muted-foreground">
      Cite: <span className="select-all">{text}</span>{" "}
      <button type="button" onClick={copy} className="underline hover:text-myco-green">
        {copied ? "Copied" : "Copy"}
      </button>
    </p>
  );
}

/** What these maps are, and are not, said once above them. */
function AboutTheseMaps({ name }: { name: string }) {
  return (
    <div className="mb-6 rounded-lg border border-[#A87146]/20 bg-[#f8f5f0] px-4 py-3 text-sm text-[#5c4a3a] space-y-1.5">
      <p>
        <strong className="text-[#4a3728]">What these maps show.</strong> How closely each place's
        climate, soil and trees match the places where this fungus has been confirmed by DNA,
        ranked within its own range. They show suitable habitat, not where it grows or how common
        it is, and they know nothing about places unlike any surveyed site (hatched).
      </p>
      <p>
        <strong className="text-[#4a3728]">Not for decisions about safety or land.</strong> Never use
        them to decide what is safe to eat or where to forage, or for permits, land management or
        other regulatory decisions.
      </p>
      {isProvisionalName(name) && (
        <p>
          <strong className="text-[#4a3728]">A provisional name.</strong> This is a DNA lineage
          without a published species name yet. It may be renamed, split or merged, and its map
          will change with it.
        </p>
      )}
      <p className="text-xs text-muted-foreground">
        Maps:{" "}
        <a href="https://creativecommons.org/licenses/by-sa/4.0/" className="underline hover:text-myco-green">
          CC BY-SA 4.0
        </a>
        , built on WorldClim 2.1 and the other datasets listed under{" "}
        <a href="/sources" className="underline hover:text-myco-green">Sources</a>.
      </p>
      <CiteThisMap name={name} />
    </div>
  );
}

/**
 * The taxon's passing models as one map, or where they disagree. Each model
 * is ranked over the ground it knows, and the ranks are averaged, weighted by
 * how far each model's blocked AUC is above chance.
 */
function EnsembleMap({
  name,
  ensemble,
  points,
  view,
  group,
}: {
  name: string;
  ensemble: Ensemble;
  points: Cell[];
  view: Bounds | null;
  group: MutableRefObject<MapGroup>;
}) {
  const [layer, setLayer] = useState<"map" | "disagreement">("map");
  const busiest = points.reduce((most, cell) => Math.max(most, cell.records), 1);
  const b = ensemble.bounds;
  const overlay: Bounds | null = b ? [[b.south, b.west], [b.north, b.east]] : null;
  const members = ensemble.members
    .map((m) => `${ALGORITHM_LABELS[m.algorithm]} (weight ${m.weight.toFixed(2)})`)
    .join(", ");
  const high = ensemble.disagreement_high_share;
  return (
    <Card className="overflow-hidden">
      <CardHeader className="bg-[#f8f5f0] border-b border-[#A87146]/10 px-4 py-2">
        <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
          <CardTitle className="text-base text-[#4a3728]">All passing models together</CardTitle>
          <div
            className="inline-flex rounded-md border border-[#A87146]/20 p-0.5 text-xs"
            role="group"
            aria-label="Which ensemble layer to show"
          >
            {(["map", "disagreement"] as const).map((l) => (
              <button
                key={l}
                type="button"
                onClick={() => setLayer(l)}
                aria-pressed={layer === l}
                className={`rounded px-2 py-1 ${
                  layer === l ? "bg-myco-green text-white" : "text-[#5c4a3a] hover:bg-[#A87146]/10"
                }`}
              >
                {l === "map" ? "Combined map" : "Where they disagree"}
              </button>
            ))}
          </div>
        </div>
      </CardHeader>
      <div className="relative h-[420px]">
        <MapContainer center={[44, -100]} zoom={3} className="h-full w-full" scrollWheelZoom={false}>
          <SyncWith group={group} id="ensemble" />
          <FitBounds bounds={view} />
          <TileLayer
            attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
            url="https://tile.openstreetmap.org/{z}/{x}/{y}.png"
          />
          {overlay && (
            <ImageOverlay
              url={ensembleMapUrl(name, layer, ensemble.built_at)}
              bounds={overlay}
              opacity={layer === "map" ? defaultStrength(false, ensemble.map_strength) / 100 : 0.85}
            />
          )}
          {points.map((cell) => (
            <CircleMarker
              key={`${cell.lat}:${cell.lng}`}
              center={[cell.lat, cell.lng]}
              radius={2 + (cell.records / busiest) * 5}
              pathOptions={{ color: "#4a3728", fillColor: "#ffffff", fillOpacity: 0.85, weight: 1 }}
              tooltip={`${formatNumber(cell.records)} record${cell.records === 1 ? "" : "s"}`}
            />
          ))}
        </MapContainer>
      </div>
      <CardContent className="px-4 py-3 text-xs text-muted-foreground">
        {layer === "map" ? (
          <>Averaged from {members}. Where a model has no data like a place, it has no say there.</>
        ) : (
          <>
            Clear where the models rank a place alike; brown where they put it at opposite ends.
            {high != null && ` They disagree strongly on ${Math.round(high * 100)}% of the ground.`}
          </>
        )}
      </CardContent>
    </Card>
  );
}

/**
 * The model's GeoTIFF for GIS work: a download for signed-in people, and an
 * invitation to sign in for everyone else, rather than a link that fails.
 */
function RasterDownload({ name, algorithm }: { name: string; algorithm: Algorithm }) {
  const me = useMe();
  const cls = "inline-flex items-center gap-1 text-xs font-medium text-myco-green hover:underline";
  if (me.signedIn) {
    return (
      <a href={rasterUrl(name, algorithm)} className={cls} title="The raw suitability values as a GeoTIFF, CC BY-SA 4.0">
        <Download className="h-3.5 w-3.5" /> GeoTIFF
      </a>
    );
  }
  if (!me.signInAvailable) return null;
  return (
    <a href={signInHere()} className={cls} title="Sign in with your mycomap.org account to download the GeoTIFF">
      <LogIn className="h-3.5 w-3.5" /> Sign in to download
    </a>
  );
}

function boundsOf(model?: Model | null): Bounds | null {
  const b = model?.bounds;
  return b ? [[b.south, b.west], [b.north, b.east]] : null;
}

function ModelMap({
  name,
  algorithm,
  model,
  loading,
  points,
  view,
  group,
  presences,
  expanded,
  hidden,
  alone = false,
  onToggle,
}: {
  name: string;
  algorithm: Algorithm;
  model?: Model | null;
  loading: boolean;
  points: Cell[];
  presences?: number;
  view: Bounds | null;
  group: MutableRefObject<MapGroup>;
  expanded: boolean;
  hidden: boolean;
  /** The only map this taxon has: it takes the whole row. */
  alone?: boolean;
  onToggle: () => void;
}) {
  const busiest = points.reduce((most, cell) => Math.max(most, cell.records), 1);
  const overlay = boundsOf(model);
  const minimum = ALGORITHM_MIN_PRESENCES[algorithm];
  const failed = model?.skill === "failed";
  // Starts where the model's null test puts it, and again whenever the model
  // (or its verdict) changes; after that it is the viewer's.
  const [strength, setStrength] = useState(defaultStrength(failed, model?.map_strength));
  useEffect(
    () => setStrength(defaultStrength(failed, model?.map_strength)),
    [failed, model?.map_strength, model?.built_at],
  );
  const screen = useFullscreen<HTMLDivElement>();
  useLayoutEffect(() => {
    const map = group.current.maps.get(algorithm);
    if (!map) return;
    // Leaflet does not notice its panel changing size. Going in or out of
    // full screen opens the map on the taxon's ground again, sized to the new
    // panel; with no page to scroll, the wheel can zoom it meanwhile.
    map.invalidateSize({ animate: false });
    if (view) map.fitBounds(view, { animate: false });
    if (screen.full) map.scrollWheelZoom.enable();
    else map.scrollWheelZoom.disable();
    // Only on going in or out: a new view on its own is FitBounds' to show.
  }, [screen.full, group, algorithm]);
  const layout = screen.full
    ? `flex flex-col ${screen.pinned ? "fixed inset-0 z-[2000] rounded-none" : ""}`
    : hidden
      ? "hidden"
      : expanded || alone
        ? "lg:col-span-3"
        : "";
  return (
    <Card ref={screen.ref} className={`overflow-hidden ${layout}`}>
      <CardHeader className="bg-[#f8f5f0] border-b border-[#A87146]/10 px-4 py-2">
        <div className="flex flex-wrap items-baseline justify-between gap-x-2 gap-y-1">
          <CardTitle className="text-base text-[#4a3728]">{ALGORITHM_LABELS[algorithm]}</CardTitle>
          <span className="flex items-center gap-3">
            {model && (
              <>
                <span className="text-xs text-muted-foreground tabular-nums">
                  AUC {model.auc_mean.toFixed(2)} · Boyce {(model.boyce ?? model.boyce_mean).toFixed(2)}
                </span>
                {model.bounds && <RasterDownload name={name} algorithm={algorithm} />}
              </>
            )}
            {!alone && <button
              type="button"
              onClick={onToggle}
              className="rounded p-1 text-muted-foreground hover:bg-[#A87146]/10 hover:text-[#4a3728]"
              title={expanded ? "Back to all three maps (Esc)" : "Expand this map across all three panels"}
              aria-label={
                expanded
                  ? "Back to all three maps"
                  : `Expand the ${ALGORITHM_LABELS[algorithm]} map across all three panels`
              }
              aria-pressed={expanded}
            >
              {expanded ? <Minimize2 className="h-4 w-4" /> : <Maximize2 className="h-4 w-4" />}
            </button>}
            <button
              type="button"
              onClick={screen.toggle}
              className="rounded p-1 text-muted-foreground hover:bg-[#A87146]/10 hover:text-[#4a3728]"
              title={screen.full ? "Leave full screen (Esc)" : "Full screen"}
              aria-label={
                screen.full
                  ? "Leave full screen"
                  : `Show the ${ALGORITHM_LABELS[algorithm]} map full screen`
              }
              aria-pressed={screen.full}
            >
              {screen.full ? <Minimize className="h-4 w-4" /> : <Maximize className="h-4 w-4" />}
            </button>
          </span>
        </div>
      </CardHeader>
      <div
        className={`relative ${screen.full ? "min-h-0 flex-1" : expanded ? "h-[70vh] min-h-[420px]" : "h-[380px]"}`}
      >
        <MapContainer
          // North America until the records arrive; FitBounds then opens on them.
          center={[44, -100]}
          zoom={3}
          className="h-full w-full"
          // Otherwise scrolling the page over a map zooms it instead.
          scrollWheelZoom={false}
        >
          <SyncWith group={group} id={algorithm} />
          <FitBounds bounds={view} />
          <TileLayer
            attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
            url="https://tile.openstreetmap.org/{z}/{x}/{y}.png"
          />
          {overlay && (
            <ImageOverlay
              url={mapUrl(name, algorithm, model?.map_drawn_at ?? model?.built_at)}
              bounds={overlay}
              // A map starts as strong as it beat its null models by.
              opacity={strength / 100}
            />
          )}
          {points.map((cell) => (
            <CircleMarker
              key={`${cell.lat}:${cell.lng}`}
              center={[cell.lat, cell.lng]}
              radius={2 + (cell.records / busiest) * 5}
              pathOptions={{ color: "#4a3728", fillColor: "#ffffff", fillOpacity: 0.85, weight: 1 }}
              tooltip={`${formatNumber(cell.records)} record${cell.records === 1 ? "" : "s"}`}
            />
          ))}
        </MapContainer>
        {failed && !model?.map_withheld && (
          <div className="pointer-events-none absolute inset-x-0 bottom-3 z-[500] mx-auto max-w-[90%] w-fit rounded-md bg-white/90 px-3 py-1 text-center text-xs text-muted-foreground shadow">
            {algorithm === "esm"
              ? sparseFailedNote(model?.presences ?? presences ?? 0)
              : "No better than its null models: this map says little about habitat."}
          </div>
        )}
        {model?.map_withheld && (
          <div className="pointer-events-none absolute inset-x-0 bottom-3 z-[500] mx-auto max-w-[90%] w-fit rounded-md bg-white/90 px-3 py-1 text-center text-xs text-muted-foreground shadow">
            Not drawn yet: maps from 3 or 4 sites used to be shown only when they passed a test
            that so few sites cannot pass. This one is drawn at its next fit.
          </div>
        )}
        {!loading && !model && (
          <div className="pointer-events-none absolute inset-x-0 bottom-3 z-[500] mx-auto max-w-[90%] w-fit rounded-md bg-white/90 px-3 py-1 text-center text-xs text-muted-foreground shadow">
            {minimum != null && presences != null && presences < minimum
              ? `Not drawn below ${minimum} detection sites: with this few records this model ranks ground wrongly.`
              : "Not fitted yet"}
          </div>
        )}
      </div>
      {overlay && (
        <MapStrength value={strength} onChange={setStrength} algorithm={ALGORITHM_LABELS[algorithm]} />
      )}
    </Card>
  );
}

/** A score with its spread; a missing spread means only one fold was scored. */
function score(value?: number, sd?: number) {
  if (value == null || !Number.isFinite(value)) return "—";
  return sd != null && Number.isFinite(sd) ? `${value.toFixed(2)} ± ${sd.toFixed(2)}` : value.toFixed(2);
}

function Comparison({ models }: { models: Partial<Record<Algorithm, Model | null>> }) {
  const fitted = ALGORITHMS.filter((a) => models[a]);
  const best = (pick: (m: Model) => number) => {
    const values = fitted.map((a) => pick(models[a]!)).filter(Number.isFinite);
    return values.length > 1 ? Math.max(...values) : undefined;
  };
  const bestAuc = best((m) => m.auc_mean);
  const bestBoyce = best((m) => m.boyce ?? m.boyce_mean);
  const mark = (value: number, top?: number) =>
    top != null && value === top ? "font-semibold text-myco-green" : "";
  const first = fitted.length ? models[fitted[0]]! : undefined;
  const folds = first?.folds.length ?? 5;
  const blockKm = formatNumber(first?.block_km ?? 200);
  const considered = first?.predictors_considered ?? 33;

  const rows: { label: string; help: React.ReactNode; cell: (m: Model) => React.ReactNode }[] = [
    {
      label: "Blocked AUC",
      help: (
        <>
          <p>
            How well the map separates the places this species was collected from the other places
            people collected and sequenced fungi. 0.5 is no better than chance; 1 would be perfect.
          </p>
          <p className="mt-1.5">
            Blocked: the records are cut into {blockKm} km blocks, about as far as this species'
            finds stay alike (measured with blockCV), and each score comes from blocks the model
            never saw while fitting, settings included. It measures predicting new ground, not
            remembering known sites.
          </p>
          <p className="mt-1.5">
            Compare the three models on this page rather than one species against another. A
            species that turns up wherever people look sits near 0.5 even when its map is good.
            The ± is the spread across folds. Green marks the best of the three.
          </p>
        </>
      ),
      cell: (m) => <span className={mark(m.auc_mean, bestAuc)}>{score(m.auc_mean, m.auc_sd)}</span>,
    },
    {
      label: "Blocked Boyce",
      help: (
        <>
          <p>
            Whether the ground a map rates higher really holds more records than its share of the
            area. It runs from −1 to 1: near 1, records pile up where the map is darkest; near 0,
            the map's ranking says little; below 0, it ranks ground backwards.
          </p>
          <p className="mt-1.5">
            Scored on held-out {blockKm} km blocks, like AUC. This is the closer test of what the
            colours on the map claim. It is unsteady with fewer than about 50 detection sites, so
            read a wide ± as "not enough records to tell".
          </p>
        </>
      ),
      cell: (m) => (
        <span className={mark(m.boyce ?? m.boyce_mean, bestBoyce)}>
          {m.boyce == null ? score(m.boyce_mean, m.boyce_sd) : m.boyce.toFixed(2)}
        </span>
      ),
    },
    {
      label: "Beats chance",
      help: (
        <>
          <p>
            Each model is refitted {first?.null?.reps ?? 19} times on a made-up species: the same
            number of sites drawn at random from everywhere people collected, busier places more
            often. A map that knows something about this fungus should score higher than every one
            of those.
          </p>
          <p className="mt-1.5">
            Shown as the null models' AUC and the share that scored at least as well (p). A map
            passes at p ≤ 0.05 with a Boyce index above zero. One that fails is drawn faint and left
            out of Explore: its colours rank ground no better than collecting effort does.
          </p>
          <p className="mt-1.5">
            Below 20 sites the test has too little to go on: the made-up species score so variously
            that even a sound map rarely beats all of them. A small-model map that fails says
            "too few sites to tell", not "no".
          </p>
        </>
      ),
      cell: (m) =>
        m.skill === "passed" || m.skill === "failed" ? (
          <span className={m.skill === "passed" ? "text-myco-green" : "text-muted-foreground"}>
            {m.skill === "passed" ? "Yes" : m.algorithm === "esm" ? "Too few sites to tell" : "No"}
            {m.null?.auc_mean != null && (
              <span className="text-muted-foreground">
                {" "}
                (null {m.null.auc_mean.toFixed(2)}, p {m.null.auc_p?.toFixed(2) ?? "—"})
              </span>
            )}
          </span>
        ) : (
          <span className="text-muted-foreground">Not tested</span>
        ),
    },
    {
      label: "Predictors",
      help: (
        <>
          <p>
            How many environmental variables the model used, out of the {considered} every model
            is offered: climate (WorldClim bio1–19), elevation, slope and terrain roughness,
            soil pH, carbon, nitrogen, clay, sand and exchange capacity (SoilGrids), and tree, shrub,
            grassland, wetland, water and built-up cover (ESA WorldCover).
          </p>
          <p className="mt-1.5">
            Maxent drops variables that rise and fall together and keeps about one per four
            detection sites, soil pH first, because correlated inputs blur its fit. Boosted trees
            and the random forest take all {considered} and weigh them themselves.
          </p>
          <p className="mt-1.5">
            Every model also gets collecting effort (records per site), held at one level when the
            map is drawn, so a much-visited place does not look like better habitat.
          </p>
        </>
      ),
      cell: (m) =>
        m.predictors_considered
          ? `${m.predictors.length} of ${m.predictors_considered}`
          : formatNumber(m.predictors.length),
    },
    {
      label: "Folds scored",
      help: (
        <p>
          The {blockKm} km blocks are dealt into {folds} spatial folds. Each fold is held out in
          turn, the model is fitted on the rest and scored on it. A fold holding none of this
          species' records cannot be scored, so fewer than {folds} means the AUC and Boyce above
          rest on less of the range.
        </p>
      ),
      cell: (m) => `${m.folds.filter((f) => f.auc != null).length} of ${m.folds.length}` },
    {
      label: "Fitted",
      help: (
        <p>
          When this model was last fitted. The next run fits it again only if this taxon's
          validated records have changed, or the fitting method or environmental layers have.
        </p>
      ),
      cell: (m) => formatWhen(m.built_at).split(",")[0] },
  ];

  return (
    <Card>
      <CardContent className="p-0 overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="text-xs uppercase tracking-wider text-muted-foreground">
            <tr className="border-b">
              <Th> </Th>
              {ALGORITHMS.map((a) => (
                <Th key={a} right>
                  {ALGORITHM_LABELS[a]}
                </Th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.map((row) => (
              <tr key={row.label} className="border-b last:border-0">
                <td className="px-4 py-2 text-[#4a3728] whitespace-nowrap">
                  {row.label}
                  <Help label={row.label}>{row.help}</Help>
                </td>
                {ALGORITHMS.map((a) => (
                  <td key={a} className="px-4 py-2 text-right tabular-nums">
                    {models[a] ? row.cell(models[a]!) : <span className="text-muted-foreground">—</span>}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </CardContent>
    </Card>
  );
}

export default function Taxon() {
  const params = useParams<{ name: string }>();
  const name = decodeURIComponent(params.name ?? "");

  const taxon = useQuery({ queryKey: ["taxon", name], queryFn: () => getTaxon(name) });
  // A name Atlas no longer uses (renamed, or another spelling): go to the name
  // its records have now, and say so there.
  const [, navigate] = useLocation();
  const search = useSearch();
  const resolution = useQuery({
    queryKey: ["name", name],
    queryFn: () => resolveName(name),
    enabled: taxon.isError,
  });
  useEffect(() => {
    const to = renamedTaxonPath(name, resolution.data);
    if (to) navigate(to, { replace: true });
  }, [name, resolution.data, navigate]);
  const reachedFrom = reachedFromNote(name, search);
  const cells = useQuery({ queryKey: ["cells", name], queryFn: () => getCells(name) });
  const fits = useQueries({
    queries: ALGORITHMS.map((algorithm) => ({
      queryKey: ["model", name, algorithm],
      queryFn: () => getModel(name, algorithm),
    })),
  });
  const models: Partial<Record<Algorithm, Model | null>> = {};
  ALGORITHMS.forEach((a, i) => {
    models[a] = fits[i].data;
  });
  const anyModel = ALGORITHMS.map((a) => models[a]).find(Boolean) ?? null;
  // A taxon with 3 to 19 sites has the ensemble alone; richer ones the three.
  const sparse = Boolean(models.esm);
  const shown = sparse ? SPARSE_MODELS : FULL_MODELS;
  const shownModels: Partial<Record<Algorithm, Model | null>> = {};
  shown.forEach((a) => {
    shownModels[a] = models[a];
  });
  const loading = fits.some((f) => f.isLoading);
  const ensemble = useQuery({ queryKey: ["ensemble", name], queryFn: () => getEnsemble(name) });
  const points = cells.data?.cells ?? [];
  const group = useRef<MapGroup>({ maps: new Map(), syncing: false });
  // Opens on the collections and the ground around them, once they are in.
  const opening = cells.isPending ? null : openingView(points, anyModel?.bounds);

  // One map can be expanded across all three panels. The others stay mounted
  // (hidden), so they keep following it and come back where it was.
  const [expanded, setExpanded] = useState<Algorithm | null>(null);
  const view = useRef<{ center: LatLng; zoom: number } | null>(null);
  const show = (next: Algorithm | null) => {
    // Read the view before the layout changes: the map that is on screen now.
    const source = group.current.maps.get(expanded ?? next ?? "");
    view.current = source ? { center: source.getCenter(), zoom: source.getZoom() } : null;
    setExpanded(next);
  };
  useLayoutEffect(() => {
    const target = view.current;
    if (!target) return;
    // Leaflet only notices a window resize, not a panel changing size, so
    // tell every map its size changed and put each back on the same view.
    group.current.syncing = true;
    for (const map of group.current.maps.values()) {
      map.invalidateSize({ animate: false, pan: false });
      map.setView(target.center, target.zoom, { animate: false });
    }
    group.current.syncing = false;
    view.current = null;
  }, [expanded]);
  useEffect(() => {
    if (!expanded) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") show(null);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  });

  return (
    <>
      <PageHeader title={<span className="sci">{name}</span>}>
        <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-sm">
          <Link href="/taxa" className="hover:text-myco-green">
            ← All taxa
          </Link>
          {reachedFrom && <span className="text-[#5c4a3a]">{reachedFrom}</span>}
          {taxon.data && (
            <span className="tabular-nums">
              {formatNumber(taxon.data.records)} validated records ·{" "}
              {formatNumber(taxon.data.localities)} independent localities
            </span>
          )}
          {anyModel?.record_years?.first != null && (
            <span
              className="tabular-nums"
              title={
                anyModel.record_years.before_climate_period != null
                  ? `${Math.round(anyModel.record_years.before_climate_period * 100)}% of dated records were collected before ${anyModel.record_years.climate_period_start}, when the climate on the maps begins. ${formatNumber(anyModel.record_years.records - anyModel.record_years.dated)} records have no date.`
                  : undefined
              }
            >
              Collected {anyModel.record_years.first}–{anyModel.record_years.last} (median{" "}
              {anyModel.record_years.median})
            </span>
          )}
          <a
            href={`https://mycomap.org/species/${encodeURIComponent(name)}`}
            className="inline-flex items-center gap-1 hover:text-myco-green"
          >
            On mycomap.org <ArrowUpRight className="h-3.5 w-3.5" />
          </a>
          <a href="#where" className="inline-flex items-center gap-1 hover:text-myco-green">
            Where it occurs <ArrowDown className="h-3.5 w-3.5" />
          </a>
          <a href="#use" className="inline-flex items-center gap-1 hover:text-myco-green">
            Embed or download <ArrowDown className="h-3.5 w-3.5" />
          </a>
        </div>
      </PageHeader>

      <Page>
        {!loading && !anyModel ? (
          <Card className="border-dashed">
            <CardContent className="p-5 text-sm text-[#5c4a3a]">
              <h2 className="font-semibold text-[#4a3728]">No habitat map yet</h2>
              {taxon.data && taxon.data.localities < PUBLISH_AT ? (
                <p className="mt-1">
                  {formatNumber(taxon.data.localities)} independent{" "}
                  {taxon.data.localities === 1 ? "locality" : "localities"} so far, and a first map
                  needs {PUBLISH_AT}; the full three models need about 20. This taxon is a survey
                  target: every new sequenced collection from a new place brings a map closer.
                </p>
              ) : (
                <p className="mt-1">
                  Not mapped yet. Its collections come from enough places for a first map, but a
                  map counts collections within about 5 km of each other as one site, and it may
                  have too few separate sites once they are; or it is waiting for the next rebuild
                  of the maps, which follows new records.
                  <DevHint command={`./atlas fit --taxon="${name}"`} />
                </p>
              )}
            </CardContent>
          </Card>
        ) : (
          <>
            <AboutTheseMaps name={name} />
            {ensemble.data && (
              <section className="mb-8">
                <div className="mb-3 flex flex-wrap items-baseline justify-between gap-3">
                  <SectionTitle>The models together</SectionTitle>
                  <Legend />
                </div>
                <EnsembleMap
                  name={name}
                  ensemble={ensemble.data}
                  points={points}
                  view={opening}
                  group={group}
                />
              </section>
            )}
            <section>
              <div className="mb-3 flex flex-wrap items-baseline justify-between gap-3">
                <SectionTitle>{sparse ? "One map from many small models" : "Three models, same records"}</SectionTitle>
                <div className="flex flex-wrap items-center gap-4">
                  {expanded && !sparse && (
                    <div
                      className="inline-flex rounded-md border border-[#A87146]/20 p-0.5 text-xs"
                      role="group"
                      aria-label="Which map to show"
                    >
                      {shown.map((a) => (
                        <button
                          key={a}
                          type="button"
                          onClick={() => show(a)}
                          aria-pressed={a === expanded}
                          className={`rounded px-2 py-1 ${
                            a === expanded
                              ? "bg-myco-green text-white"
                              : "text-[#5c4a3a] hover:bg-[#A87146]/10"
                          }`}
                        >
                          {ALGORITHM_LABELS[a]}
                        </button>
                      ))}
                      <button
                        type="button"
                        onClick={() => show(null)}
                        className="rounded px-2 py-1 text-[#5c4a3a] hover:bg-[#A87146]/10"
                      >
                        All three
                      </button>
                    </div>
                  )}
                  <Legend />
                </div>
              </div>
              <div className="grid gap-4 lg:grid-cols-3">
                {shown.map((algorithm) => (
                  <ModelMap
                    key={algorithm}
                    name={name}
                    algorithm={algorithm}
                    model={models[algorithm]}
                    loading={loading}
                    points={points}
                    view={opening}
                    group={group}
                    presences={anyModel?.presences}
                    expanded={expanded === algorithm}
                    hidden={expanded != null && expanded !== algorithm}
                    alone={shown.length === 1}
                    onToggle={() => show(expanded === algorithm ? null : algorithm)}
                  />
                ))}
              </div>
              {sparse && (
                <p className="mt-3 max-w-3xl text-sm text-[#5c4a3a] leading-relaxed">
                  With {formatNumber(anyModel?.presences ?? 0)} sites this taxon has too few for the
                  three full models, which need about 20. Its map averages dozens of small models of
                  two variables each, weighted by how well each did on ground it never saw. Tested on
                  well-recorded fungi cut down to 8 sites, such maps kept most of their skill.
                </p>
              )}
              <p className="mt-3 text-xs text-muted-foreground">
                White dots are collections, grouped into {cells.data?.degrees ?? 0.1}° cells. The
                maps move together; expand one to see it across all three panels. Each map is coloured by rank within its own ground: the darkest
                green is the tenth of the area that model rates highest, so the three can be compared
                directly even though their raw scores run on different scales. Colour stops 500 km
                from the nearest record: beyond that a map makes no claim.
              </p>
            </section>

            <section>
              <SectionTitle>How good is each map?</SectionTitle>
              <Comparison models={shownModels} />
              <p className="mt-3 max-w-3xl text-sm text-[#5c4a3a] leading-relaxed">
                All three are scored on the same {anyModel?.folds.length ?? 5} spatial folds of{" "}
                {formatNumber(anyModel?.block_km ?? 200)} km, against the same sites where people
                collected other DNA-validated fungi. Read AUC as a comparison, not a grade: a species
                that grows wherever people look sits near 0.5 however good the model. Boyce asks
                whether the places a map rates higher really hold more records, and the null models
                ask whether the map beats a random handful of collections at all.{" "}
                <Link href="/models" className="text-myco-green hover:underline">
                  How the three compare across every taxon
                </Link>
              </p>
            </section>

            <section>
              <SectionTitle>What drives this map</SectionTitle>
              <p className="mb-3 max-w-3xl text-sm text-[#5c4a3a] leading-relaxed">
                Which datasets, and which variables within each, the map leans on to tell where this
                fungus grows. Open a dataset to see its variables.
              </p>
              <WhatDrives models={shownModels} />
            </section>
          </>
        )}

        <ShareMap
          name={name}
          algorithms={shown.filter((a) => models[a]?.bounds && !models[a]?.map_withheld)}
        />
      </Page>
    </>
  );
}
