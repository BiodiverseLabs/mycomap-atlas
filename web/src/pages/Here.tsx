import { useEffect, useMemo, useState } from "react";
import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { Link, useLocation, useSearch } from "wouter";
import { Crosshair, MapPin, X } from "lucide-react";

import { Circle, CircleMarker, ImageOverlay, MapContainer, PanTo, TileLayer, useMapEvents } from "@/components/Leaflet";
import { PageHeader } from "@/components/Layout";
import { Card } from "@/components/ui/card";
import {
  ALGORITHMS,
  ALGORITHM_LABELS,
  getHere,
  getModel,
  mapUrl,
  type Algorithm,
  type HereTaxon,
} from "@/lib/api";
import { formatNumber } from "@/lib/utils";

// What could grow here: pick a place, see every mapped fungus its maps rate
// highly there, and which have actually been collected nearby. The server
// answers from an index of every map by 20 km cell (R/here.R).

interface Point {
  lat: number;
  lng: number;
}

const SHORT: Record<Algorithm, string> = { maxnet: "M", xgboost: "B", rf: "R" };

function readPoint(search: string): Point | null {
  const params = new URLSearchParams(search);
  const lat = Number(params.get("lat"));
  const lng = Number(params.get("lng"));
  return params.has("lat") && Number.isFinite(lat) && Number.isFinite(lng) ? { lat, lng } : null;
}

function ClickToPick({ onPick }: { onPick: (p: Point) => void }) {
  useMapEvents({ click: (event) => onPick({ lat: event.latlng.lat, lng: event.latlng.lng }) });
  return null;
}

/** "top 3%" from a 0-1 rank. */
function topShare(score: number): string {
  const share = Math.max(1, Math.round((1 - score) * 100));
  return share >= 50 ? "upper half" : `top ${share}%`;
}

/** A small letter per model, dark when it puts this place in its top tenth. */
function ModelDots({ taxon }: { taxon: HereTaxon }) {
  return (
    <span className="flex gap-1">
      {ALGORITHMS.filter((a) => taxon.fitted.includes(a)).map((a) => {
        const rank = taxon.models[a];
        const tone =
          rank == null
            ? "border-gray-300 text-gray-400 bg-white"
            : rank >= 0.9
              ? "border-[#2e5a17] bg-[#2e5a17] text-white"
              : "border-myco-green bg-myco-green/20 text-[#2e5a17]";
        const title =
          rank == null
            ? `${ALGORITHM_LABELS[a]}: this place is not in its top half`
            : `${ALGORITHM_LABELS[a]}: ${topShare(rank)} of its map`;
        return (
          <span
            key={a}
            title={title}
            className={`inline-flex h-5 w-5 items-center justify-center rounded-full border text-[10px] font-bold ${tone}`}
          >
            {SHORT[a]}
          </span>
        );
      })}
    </span>
  );
}

function ResultRow({
  taxon,
  selected,
  onSelect,
  nearbyKm,
}: {
  taxon: HereTaxon;
  selected: boolean;
  onSelect: () => void;
  nearbyKm: number;
}) {
  return (
    <li
      className={`cursor-pointer border-b px-4 py-2.5 last:border-0 ${selected ? "bg-myco-green/10" : "hover:bg-myco-green/5"}`}
      onClick={onSelect}
    >
      <div className="flex items-baseline justify-between gap-3">
        <Link
          href={`/taxa/${encodeURIComponent(taxon.scientific_name)}`}
          onClick={(event) => event.stopPropagation()}
          className="sci min-w-0 truncate text-[#4a3728] hover:text-myco-green"
        >
          {taxon.scientific_name}
        </Link>
        <span className="shrink-0 text-xs font-semibold text-[#2e5a17]">{topShare(taxon.score)}</span>
      </div>
      <div className="mt-1 flex items-center gap-3">
        <div className="h-1.5 flex-1 overflow-hidden rounded bg-gray-100">
          <div className="h-full bg-myco-green" style={{ width: `${Math.round(taxon.score * 100)}%` }} />
        </div>
        <ModelDots taxon={taxon} />
      </div>
      {taxon.nearby_records > 0 && (
        <div className="mt-1 text-xs text-[#7a4e2c]">
          <MapPin className="mr-0.5 inline h-3 w-3" />
          {formatNumber(taxon.nearby_records)} record{taxon.nearby_records === 1 ? "" : "s"} within {nearbyKm} km
        </div>
      )}
    </li>
  );
}

/** The chosen taxon's best map, laid over the place. */
function SelectedOverlay({ taxon }: { taxon: HereTaxon }) {
  const algorithm: Algorithm = taxon.fitted.includes("rf") ? "rf" : taxon.fitted[0];
  const model = useQuery({
    queryKey: ["model", taxon.scientific_name, algorithm],
    queryFn: () => getModel(taxon.scientific_name, algorithm),
  });
  const b = model.data?.bounds;
  if (!b || b.east - b.west <= 1) return null;
  return (
    <ImageOverlay
      url={mapUrl(taxon.scientific_name, algorithm, model.data?.map_drawn_at ?? model.data?.built_at)}
      bounds={[[b.south, b.west], [b.north, b.east]]}
      opacity={0.7}
    />
  );
}

export default function Here() {
  const [, navigate] = useLocation();
  const point = readPoint(useSearch());
  const [topOnly, setTopOnly] = useState(false);
  const [nearbyOnly, setNearbyOnly] = useState(false);
  const [filter, setFilter] = useState("");
  const [selected, setSelected] = useState<string | null>(null);
  const [locating, setLocating] = useState<string | null>(null);
  // Where "Use my location" found you: the map moves there. A click on the
  // map picks a place already on screen, so it leaves the map where it is.
  const [found, setFound] = useState<{ lat: number; lng: number; seq: number } | null>(null);

  const pick = (p: Point) => {
    setSelected(null);
    navigate(`/here?lat=${p.lat.toFixed(4)}&lng=${p.lng.toFixed(4)}`, { replace: true });
  };

  const answer = useQuery({
    queryKey: ["here", point?.lat, point?.lng, topOnly],
    enabled: !!point,
    queryFn: () => getHere(point!.lat, point!.lng, topOnly ? 0.9 : 0, 1000),
    placeholderData: keepPreviousData,
  });

  const shown = useMemo(() => {
    const needle = filter.trim().toLowerCase();
    return (answer.data?.taxa ?? []).filter(
      (t) => (!nearbyOnly || t.nearby_records > 0) && (!needle || t.scientific_name.toLowerCase().includes(needle)),
    );
  }, [answer.data, nearbyOnly, filter]);
  const selectedTaxon = shown.find((t) => t.scientific_name === selected) ?? null;

  useEffect(() => setSelected(null), [point?.lat, point?.lng]);

  const locate = () => {
    if (!navigator.geolocation) {
      setLocating("This browser cannot share its location.");
      return;
    }
    setLocating("Finding you…");
    navigator.geolocation.getCurrentPosition(
      (position) => {
        setLocating(null);
        const here = { lat: position.coords.latitude, lng: position.coords.longitude };
        pick(here);
        setFound((last) => ({ ...here, seq: (last?.seq ?? 0) + 1 }));
      },
      () => setLocating("Location was not shared. Click the map instead."),
      { enableHighAccuracy: false, timeout: 10000 },
    );
  };

  const unavailable = answer.error instanceof Error && answer.error.message.startsWith("503");

  return (
    <>
      <PageHeader title="What could grow here?">
        Pick a place and see every mapped fungus whose habitat maps rate it highly, and which have
        actually been collected nearby. A high rank means the place resembles where a species has
        been found, not that it is there — the best reason yet to go and look.
      </PageHeader>
      <div className="container mx-auto px-4 sm:px-6 lg:px-8 py-6">
        <div className="grid gap-4 lg:grid-cols-[1.3fr_1fr]">
          <Card className="overflow-hidden">
            <div className="relative h-[360px] lg:h-[68vh]">
              <MapContainer
                center={point ? [point.lat, point.lng] : [44, -98]}
                zoom={point ? 7 : 4}
                className="h-full w-full"
              >
                <TileLayer
                  attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
                  url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
                />
                <ClickToPick onPick={pick} />
                <PanTo target={found} minZoom={7} />
                {selectedTaxon && <SelectedOverlay taxon={selectedTaxon} />}
                {point && (
                  <>
                    <Circle
                      center={[point.lat, point.lng]}
                      radius={(answer.data?.nearby_km ?? 25) * 1000}
                      pathOptions={{ color: "#7a4e2c", weight: 1, fillOpacity: 0.04, dashArray: "4 4" }}
                    />
                    <CircleMarker
                      center={[point.lat, point.lng]}
                      radius={7}
                      pathOptions={{ color: "#ffffff", weight: 2, fillColor: "#4a3728", fillOpacity: 1 }}
                    />
                  </>
                )}
              </MapContainer>
              <div className="absolute right-3 top-3 z-[500] flex flex-wrap justify-end gap-2">
                <button
                  type="button"
                  onClick={locate}
                  className="inline-flex items-center gap-1.5 rounded-md bg-white px-3 py-1.5 text-sm font-medium text-[#4a3728] shadow hover:bg-[#f8f5f0]"
                >
                  <Crosshair className="h-4 w-4 text-myco-green" /> Use my location
                </button>
                {!point && (
                  <span className="rounded-md bg-white/90 px-3 py-1.5 text-sm text-muted-foreground shadow">
                    or click anywhere on the map
                  </span>
                )}
              </div>
              {locating && (
                <div className="absolute bottom-3 left-3 z-[500] rounded-md bg-white/95 px-3 py-1.5 text-xs text-muted-foreground shadow">
                  {locating}
                </div>
              )}
            </div>
          </Card>

          <Card className="flex flex-col overflow-hidden lg:h-[68vh]">
            <div className="border-b border-[#A87146]/10 bg-[#f8f5f0] px-4 py-3">
              {!point ? (
                <p className="text-sm text-[#5c4a3a]">No place chosen yet.</p>
              ) : (
                <>
                  <div className="flex items-baseline justify-between gap-2">
                    <h2 className="font-semibold text-[#4a3728]">
                      {answer.data ? `${formatNumber(shown.length)} fungi this place suits` : "Looking…"}
                    </h2>
                    <span className="text-xs tabular-nums text-muted-foreground">
                      {point.lat.toFixed(3)}, {point.lng.toFixed(3)}
                    </span>
                  </div>
                  <div className="mt-2 flex flex-wrap items-center gap-3 text-sm">
                    <label className="inline-flex items-center gap-1.5">
                      <input type="checkbox" checked={topOnly} onChange={(e) => setTopOnly(e.target.checked)} />
                      Top tenth only
                    </label>
                    <label className="inline-flex items-center gap-1.5">
                      <input type="checkbox" checked={nearbyOnly} onChange={(e) => setNearbyOnly(e.target.checked)} />
                      Collected nearby
                    </label>
                    <input
                      value={filter}
                      onChange={(e) => setFilter(e.target.value)}
                      placeholder="Filter, e.g. Russula"
                      className="h-8 min-w-0 flex-1 rounded-md border border-input bg-white px-2 text-sm"
                    />
                  </div>
                </>
              )}
            </div>

            <div className="min-h-0 flex-1 overflow-y-auto">
              {!point && (
                <div className="space-y-3 p-4 text-sm text-[#5c4a3a] leading-relaxed">
                  <p>
                    Click the map or use your location. Atlas lists every mapped fungus whose maps put
                    that ground high in their own range, best first.
                  </p>
                  <p className="text-muted-foreground">
                    Each species is scored by the average rank its models give the place, where{" "}
                    <strong className="text-[#4a3728]">top 5%</strong> means the ground resembles the
                    best twentieth of that species&rsquo; habitat. The letters are its models —
                    Maxent, Boosted trees, Random forest — dark when that model puts the place in
                    its top tenth.
                  </p>
                </div>
              )}
              {unavailable && (
                <p className="p-4 text-sm text-muted-foreground">
                  This server has not built its place index yet. Run <code>./atlas build-here-index</code>.
                </p>
              )}
              {answer.data && !answer.data.in_grid && (
                <p className="p-4 text-sm text-[#5c4a3a]">
                  That place is outside the area Atlas models: North America, Hawaii, Puerto Rico and
                  the Virgin Islands.
                </p>
              )}
              {answer.data && answer.data.in_grid && !shown.length && (
                <p className="p-4 text-sm text-[#5c4a3a]">
                  No mapped fungus rates this place in the top half of its range
                  {topOnly || nearbyOnly || filter ? " with these filters" : ""}. Maps reach only 500 km
                  beyond where a species has been found.
                </p>
              )}
              {selectedTaxon && (
                <div className="flex items-center justify-between gap-2 border-b bg-myco-green/5 px-4 py-2 text-xs text-[#4a3728]">
                  <span>
                    Showing <span className="sci">{selectedTaxon.scientific_name}</span>&rsquo;s map
                  </span>
                  <button type="button" onClick={() => setSelected(null)} aria-label="Hide map">
                    <X className="h-4 w-4" />
                  </button>
                </div>
              )}
              <ul>
                {shown.map((taxon) => (
                  <ResultRow
                    key={taxon.scientific_name}
                    taxon={taxon}
                    selected={taxon.scientific_name === selected}
                    onSelect={() => setSelected(taxon.scientific_name === selected ? null : taxon.scientific_name)}
                    nearbyKm={answer.data?.nearby_km ?? 25}
                  />
                ))}
              </ul>
              {answer.data && answer.data.recorded_unmapped.length > 0 && !topOnly && (
                <div className="border-t bg-[#f8f5f0]/60 px-4 py-3 text-sm">
                  <h3 className="font-semibold text-[#4a3728]">Collected nearby, no map yet</h3>
                  <p className="mb-2 text-xs text-muted-foreground">
                    Too few places recorded to model. Every new sequenced collection brings a map closer.
                  </p>
                  <ul className="space-y-1">
                    {answer.data.recorded_unmapped.map((t) => (
                      <li key={t.scientific_name} className="flex justify-between gap-2">
                        <Link
                          href={`/taxa/${encodeURIComponent(t.scientific_name)}`}
                          className="sci min-w-0 truncate text-[#4a3728] hover:text-myco-green"
                        >
                          {t.scientific_name}
                        </Link>
                        <span className="shrink-0 text-xs text-muted-foreground">
                          {formatNumber(t.nearby_records)} record{t.nearby_records === 1 ? "" : "s"}
                        </span>
                      </li>
                    ))}
                  </ul>
                </div>
              )}
            </div>
          </Card>
        </div>
        <p className="mt-3 max-w-4xl text-xs text-muted-foreground leading-relaxed">
          Answers are for the 20 km square around the point, from 5 km maps. A rank compares places
          within one species&rsquo; own range, so it says how good this ground is for that species, not
          how common it is. Collections are counted from 0.1° cells; exact collection points are never
          used or shown. Click a species to lay its map over the place.
        </p>
      </div>
    </>
  );
}
