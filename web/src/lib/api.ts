// The development API is the plumber server started by `./atlas api`. In
// production the same routes are served from atlas.mycomap.org.

export interface Status {
  ready: boolean;
  pulledAt?: string;
  records?: number;
  taxa?: number;
  fingerprint?: string;
  since?: string | null;
}

export interface Taxon {
  scientific_name: string;
  records: number;
  localities: number;
  fingerprint: string;
}

export interface TaxaPage {
  total: number;
  items: Taxon[];
}

export interface Cell {
  lat: number;
  lng: number;
  records: number;
}

export interface Cells {
  name: string;
  degrees: number;
  cells: Cell[];
}

export interface Layer {
  id: string;
  title: string;
  source: string;
  /** The provider's download page; absent for layers derived on the grid. */
  url?: string;
  license: string;
  citation: string;
  note?: string;
  built: boolean;
  bands?: string[];
  cellSizeM?: number;
  sizeMb?: number;
  builtAt?: string;
}

export interface LayersResponse {
  grid: string;
  layers: Layer[];
}

export interface ModelFold {
  fold: number;
  presences: number;
  auc: number | null;
  boyce: number | null;
}

export interface ModelBounds {
  south: number;
  west: number;
  north: number;
  east: number;
}

/** The models Atlas fits, side by side, in the order they are shown. */
export const ALGORITHMS = ["maxnet", "xgboost", "rf", "esm"] as const;
export type Algorithm = (typeof ALGORITHMS)[number];

// Which maps a taxon's page shows, by how many sites it has (lib/panels.ts).
export { FULL_MODELS, MIDDLE_MODELS, SPARSE_BELOW, SPARSE_MODELS, shownModels } from "./panels";

export const ALGORITHM_LABELS: Record<Algorithm, string> = {
  maxnet: "Maxent",
  xgboost: "Boosted trees",
  rf: "Random forest",
  esm: "Small-model ensemble",
};

/**
 * The fewest presence cells a model is drawn for, where it differs from the
 * site-wide 20. Mirrors min_presences in R/algorithms.R.
 */
export const ALGORITHM_MIN_PRESENCES: Partial<Record<Algorithm, number>> = {
  xgboost: 50,
  esm: 3,
};

/** One line on what each model is, for people rather than modellers. */
export const ALGORITHM_NOTES: Record<Algorithm, string> = {
  maxnet:
    "Smooth responses to each variable, fitted with a penalty that keeps them simple. The long-standing standard for presence-only data.",
  xgboost:
    "Hundreds of small decision trees, each correcting the last. Finds combinations of conditions a smooth curve cannot. Drawn only from 50 presence cells: with fewer it overfits and ranks ground wrongly.",
  rf:
    "250 trees grown independently, each on as many background records as presences, then left to vote.",
  esm:
    "Dozens of small models of two variables each, every one checked on ground it did not see and weighted by how well it did there, then averaged. For taxa with 3 to 19 sites, too few for the other three, and in place of boosted trees up to 49.",
};

/** How much a map relied on one dataset (or one variable): the fall in
 * held-out AUC when it is shuffled, with its spread between folds. */
export interface ModelImportance {
  name: string;
  label: string;
  fall?: number;
  sd?: number;
  /** Whether the fall stands out from its spread between folds. */
  clear?: boolean;
  /** A dataset's own variables, largest first. */
  predictors?: ModelImportance[];
}

export interface Model {
  taxon: string;
  algorithm?: Algorithm;
  algorithm_label?: string;
  nrounds?: number;
  grid: string;
  presences: number;
  background: number;
  area_km2: number;
  predictors: string[];
  predictors_considered?: number;
  classes?: string;
  block_km: number;
  folds: ModelFold[];
  auc_mean: number;
  auc_sd: number;
  /** Boyce index of every fold's held-out scores together: the one a map is
   * judged by. Fits from before it was computed have only boyce_mean. */
  boyce?: number;
  boyce_mean: number;
  boyce_sd: number;
  /** What the map rests on, dataset by dataset, largest first. Absent on fits
   * from before it was measured. */
  importance?: ModelImportance[];
  /** A map not drawn: from 3 or 4 sites, held back before 2026-10-04 until it passed. */
  map_withheld?: boolean;
  /** Datasets this model kept no variable of (Maxent prunes). */
  layers_unused?: string[];
  uses_effort?: boolean;
  built_at: string;
  map?: string;
  bounds?: ModelBounds;
  /** "rank" when colours are by percentile within the map. */
  map_scale?: string;
  map_drawn_at?: string;
  /** Whether the map beat its null models. Fits from before there were
   * null models have none, and read as "untested". */
  skill?: Skill;
  null?: ModelNull;
  /** Settings chosen by tuning in nested spatial folds. */
  params?: Record<string, string | number>;
  block_source?: "blockCV" | "fixed" | "fallback";
  presence_blocks?: number;
}

export type Skill = "passed" | "failed" | "untested";

/** A model scored against null models: the same number of sites drawn at
 * random from the surveyed sites, fitted and scored the same way. */
export interface ModelNull {
  reps: number;
  /** The untuned settings the taxon and its nulls were both fitted at. */
  settings?: string;
  observed_auc?: number;
  observed_boyce?: number;
  auc_mean?: number;
  auc_sd?: number;
  auc_p?: number;
  boyce_mean?: number;
  boyce_p?: number;
}

/** One row of /api/models: enough for a list. The full record is getModel. */
export interface ModelSummary {
  taxon: string;
  algorithm: Algorithm;
  presences?: number;
  predictors: number;
  auc_mean?: number;
  boyce?: number;
  boyce_mean?: number;
  skill?: Skill;
  map: boolean;
  built_at: string;
}

async function get<T>(path: string): Promise<T> {
  const response = await fetch(path);
  if (!response.ok) {
    throw new Error(`${response.status} ${response.statusText}`);
  }
  return (await response.json()) as T;
}

export function getStatus(): Promise<Status> {
  return get<Status>("/api/status");
}

export function getTaxa(params: {
  search?: string;
  minLocalities?: number;
  limit?: number;
  offset?: number;
}): Promise<TaxaPage> {
  const query = new URLSearchParams({
    search: params.search ?? "",
    min_localities: String(params.minLocalities ?? 0),
    limit: String(params.limit ?? 50),
    offset: String(params.offset ?? 0),
  });
  return get<TaxaPage>(`/api/taxa?${query.toString()}`);
}

/** How many taxa have at least this many independent localities. */
export async function getTaxaCount(minLocalities: number): Promise<number> {
  const page = await getTaxa({ minLocalities, limit: 1 });
  return page.total;
}

export function getLayers(grid = "draft"): Promise<LayersResponse> {
  return get<LayersResponse>(`/api/layers?grid=${encodeURIComponent(grid)}`);
}

export function getTaxon(name: string): Promise<Taxon> {
  return get<Taxon>(`/api/taxa/${encodeURIComponent(name)}`);
}

export function getCells(name: string): Promise<Cells> {
  return get<Cells>(`/api/taxa/${encodeURIComponent(name)}/cells`);
}

/** The fitted model for a taxon, or null when it has not been fitted. */
export async function getModel(name: string, algorithm: Algorithm = "maxnet"): Promise<Model | null> {
  const response = await fetch(
    `/api/taxa/${encodeURIComponent(name)}/model?algorithm=${algorithm}`,
  );
  if (response.status === 404) return null;
  if (!response.ok) throw new Error(`${response.status} ${response.statusText}`);
  return (await response.json()) as Model;
}

/**
 * A map's PNG. version changes whenever the map is redrawn, so a browser never
 * shows yesterday's colours from its cache.
 */
export function mapUrl(name: string, algorithm: Algorithm = "maxnet", version?: string): string {
  const v = version ? `&v=${encodeURIComponent(version)}` : "";
  return `/api/taxa/${encodeURIComponent(name)}/map.png?algorithm=${algorithm}${v}`;
}

/** Where the site sends someone to sign in with their mycomap.org account. */
export const SIGN_IN_PATH = "/auth/dev-bridge/start";

/** The sign-in link, coming back to returnTo (a path on this site). */
export function signInUrl(returnTo: string): string {
  return `${SIGN_IN_PATH}?returnTo=${encodeURIComponent(returnTo)}`;
}

/** /api/me: whether this browser is signed in. Never the mycomap.org id. */
export interface Me {
  signedIn: boolean;
  signInAvailable: boolean;
  name?: string;
  via?: "session" | "token";
  tier?: string;
}

export function getMe(): Promise<Me> {
  return get<Me>("/api/me");
}

/** Clear this site's session. The API checks the request came from this site. */
export async function signOut(): Promise<void> {
  const response = await fetch("/auth/logout", { method: "POST", credentials: "same-origin" });
  if (!response.ok) throw new Error(`${response.status} ${response.statusText}`);
}

/** A model's GeoTIFF: for signed-in people and token holders only. */
export function rasterUrl(name: string, algorithm: Algorithm = "maxnet"): string {
  return `/api/taxa/${encodeURIComponent(name)}/raster.tif?algorithm=${algorithm}`;
}

/** A state, province or territory, with how much it holds. */
export interface Region {
  country: string;
  region: string;
  /** ISO 3166-2, such as US-IN; empty when the records name no known region. */
  code: string;
  /** Taxa with validated records here. */
  taxa: number;
  records: number;
  /** More taxa its maps call likely here, without a record yet. */
  likely: number;
}

/** What a taxon's maps say about a state (R/predictions.R). */
export type RegionVerdict = "likely" | "unlikely" | "beyond reach" | "no map";

/** One taxon in one state, province or territory. */
export interface TaxonRegion {
  country: string;
  region: string;
  code: string;
  records: number;
  localities: number;
  model: RegionVerdict;
  /** Share of the state its maps rate as suitable; null with no map. */
  suitable_share: number | null;
  /** Share of the state within 500 km of a record; null with no map. */
  reach_share: number | null;
}

export interface TaxonRegions {
  name: string;
  /** Whether it has a map that beat its null models, counted by state. */
  mapped: boolean;
  /** The suitable share at which a state is called likely. */
  min_share: number;
  regions: TaxonRegion[];
}

export function getRegions(): Promise<{ regions: Region[] }> {
  return get<{ regions: Region[] }>("/api/regions");
}

export function getTaxonRegions(name: string): Promise<TaxonRegions> {
  return get<TaxonRegions>(`/api/taxa/${encodeURIComponent(name)}/regions`);
}

/**
 * A taxon's map as one picture, for Excel's =IMAGE(), documents and slides.
 * Without an algorithm, the API picks the taxon's main map.
 */
export function imageUrl(name: string, opts: { algorithm?: Algorithm; width?: number; points?: boolean } = {}): string {
  const query = new URLSearchParams();
  if (opts.algorithm) query.set("algorithm", opts.algorithm);
  if (opts.width) query.set("width", String(opts.width));
  if (opts.points === false) query.set("points", "0");
  const text = query.toString();
  return `/api/taxa/${encodeURIComponent(name)}/image.png${text ? `?${text}` : ""}`;
}

/**
 * The checklist CSV: everything, one region (by code or name), one country,
 * or one taxon. Relative, so it works on any copy of the site; absoluteUrl
 * makes it pasteable into a spreadsheet.
 */
export function checklistUrl(params: { region?: string; taxon?: string } = {}): string {
  const query = new URLSearchParams();
  if (params.region) query.set("region", params.region);
  if (params.taxon) query.set("taxon", params.taxon);
  const text = query.toString();
  return `/api/checklist.csv${text ? `?${text}` : ""}`;
}

/** The bare map page another site puts in an iframe. */
export function embedPath(name: string, algorithm: Algorithm, points = true): string {
  const query = new URLSearchParams({ model: algorithm });
  if (!points) query.set("points", "0");
  return `/embed/taxa/${encodeURIComponent(name)}?${query.toString()}`;
}

/** A path on this site as a full URL, for copying somewhere else. */
export function absoluteUrl(path: string): string {
  return new URL(path, window.location.origin).toString();
}

/** One row of a benchmark summary: an arm within a band of presence cells. */
export interface BenchmarkRow {
  band: string;
  arm: string;
  taxa: number;
  predictors?: number;
  auc?: number;
  boyce?: number;
  delta_auc?: number;
  delta_se?: number;
  delta_boyce?: number;
  delta_boyce_se?: number;
  best_share?: number;
}

export interface BenchmarkArm {
  arm: string;
  predictors: number;
  auc: number;
  boyce: number;
  seconds?: number;
}

export interface BenchmarkTaxon {
  taxon: string;
  status: string;
  presences?: number;
  band?: string;
  arms?: BenchmarkArm[];
}

export interface Benchmark {
  started_at: string;
  baseline: string;
  settings: { arms?: string[]; folds?: number; block_km?: number; [key: string]: unknown };
  summary: BenchmarkRow[];
  taxa: BenchmarkTaxon[];
}

/** The newest benchmark, or null when none has been run. */
export async function getBenchmark(): Promise<Benchmark | null> {
  const response = await fetch("/api/benchmarks/latest");
  if (response.status === 404) return null;
  if (!response.ok) throw new Error(`${response.status} ${response.statusText}`);
  return (await response.json()) as Benchmark;
}

/** Every fitted model, newest first, as a summary. */
export async function getModels(): Promise<ModelSummary[]> {
  const response = await get<{ models: ModelSummary[] }>("/api/models");
  return response.models;
}

/** One archived version on Zenodo. Only published versions have a DOI. */
export interface ArchiveVersion {
  version: string;
  state: "draft" | "published";
  doi?: string;
  url?: string;
  release?: string;
  layers_version?: string;
  bytes?: number;
  created_at?: string;
  published_at?: string;
  files?: { name: string; bytes: number; sha256: string }[];
}

/** One Zenodo record with all its versions: models-<grid> or layers-<grid>. */
export interface ArchiveSeries {
  series: string;
  concept_doi?: string;
  versions: ArchiveVersion[];
}

export async function getDownloads(): Promise<ArchiveSeries[]> {
  const response = await get<{ series: ArchiveSeries[] }>("/api/downloads");
  return response.series ?? [];
}

/** One species a search found, best first. */
export interface SearchSpecies {
  scientific_name: string;
  records: number;
  localities: number;
  /** Models with a map; empty when the taxon has none yet. */
  models: Algorithm[];
  /** similar is a near miss: show it as "did you mean". */
  match: "exact" | "prefix" | "words" | "contains" | "similar";
}

export interface SearchGenus {
  genus: string;
  taxa: number;
  mapped: number;
  records: number;
}

export interface SearchResult {
  query: string;
  species: SearchSpecies[];
  genera: SearchGenus[];
}

/** Forgiving search: typos, provisional-code spellings, word order. */
export function searchTaxa(q: string, limit = 8): Promise<SearchResult> {
  const query = new URLSearchParams({ q, limit: String(limit) });
  return get<SearchResult>(`/api/search?${query.toString()}`);
}

/** One taxon a place suits. models holds only the models rating it in their top half. */
export interface HereTaxon {
  scientific_name: string;
  score: number;
  models: Partial<Record<Algorithm, number>>;
  fitted: Algorithm[];
  agree: number;
  nearby_records: number;
  localities: number;
}

export interface HereAnswer {
  point: { lat: number; lng: number };
  cell_km: number;
  in_grid: boolean;
  nearby_km: number;
  total: number;
  taxa: HereTaxon[];
  recorded_unmapped: { scientific_name: string; nearby_records: number }[];
}

/** What could grow at a place. Throws with status 503 when the index is missing. */
export async function getHere(lat: number, lng: number, minScore = 0, limit = 100): Promise<HereAnswer> {
  const query = new URLSearchParams({
    lat: lat.toFixed(4),
    lng: lng.toFixed(4),
    min_score: String(minScore),
    limit: String(limit),
  });
  return get<HereAnswer>(`/api/here?${query.toString()}`);
}
