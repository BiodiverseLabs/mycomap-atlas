import type { ReactNode } from "react";
import { Link } from "wouter";
import { ArrowUpRight } from "lucide-react";

import { GithubMark } from "@/components/Common";
import { PageHeader } from "@/components/Layout";
import { GITHUB_URL, SOURCES } from "@/lib/contract";

// The method in full, for someone deciding whether to build on Atlas. Numbers
// here come from the README's measurements; when a setting changes in R/,
// change it here in the same pull request.

const SECTIONS: { id: string; title: string }[] = [
  { id: "brief", title: "In brief" },
  { id: "records", title: "Records" },
  { id: "grid", title: "The grid" },
  { id: "predictors", title: "Environmental predictors" },
  { id: "background", title: "Background" },
  { id: "selection", title: "Choosing predictors" },
  { id: "models", title: "Three models" },
  { id: "evaluation", title: "Evaluation" },
  { id: "thresholds", title: "How much data a map needs" },
  { id: "maps", title: "Drawing the maps" },
  { id: "reproducibility", title: "Reproducibility" },
  { id: "limits", title: "What the maps are not" },
  { id: "next", title: "What comes next" },
  { id: "cite", title: "Cite and contribute" },
];

function Section({ id, title, children }: { id: string; title: string; children: ReactNode }) {
  return (
    <section id={id} className="scroll-mt-24">
      <h2 className="font-display text-2xl text-[#4a3728] mb-3">{title}</h2>
      <div className="space-y-3">{children}</div>
    </section>
  );
}

function Table({ head, rows }: { head: string[]; rows: ReactNode[][] }) {
  return (
    <div className="overflow-x-auto rounded-lg border border-[#A87146]/15">
      <table className="w-full text-sm">
        <thead className="bg-[#f8f5f0] text-xs uppercase tracking-wider text-muted-foreground">
          <tr>
            {head.map((h) => (
              <th key={h} className="px-3 py-2 text-left font-medium">
                {h}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row, i) => (
            <tr key={i} className="border-t border-[#A87146]/10 align-top">
              {row.map((cell, j) => (
                <td key={j} className="px-3 py-2">
                  {cell}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function Ext({ href, children }: { href: string; children: ReactNode }) {
  return (
    <a href={href} target="_blank" rel="noreferrer" className="text-myco-green hover:underline">
      {children}
    </a>
  );
}

const dataset = (id: string) => SOURCES.datasets.find((d) => d.id === id)!;

function DatasetLink({ id }: { id: string }) {
  const d = dataset(id);
  return <Ext href={d.url}>{d.name}</Ext>;
}

const Sci = ({ children }: { children: ReactNode }) => <span className="sci">{children}</span>;
const B = ({ children }: { children: ReactNode }) => <strong className="text-[#4a3728]">{children}</strong>;

export default function Methods() {
  return (
    <>
      <PageHeader title="Methods">
        How every Atlas map is made, in enough detail to judge it, reproduce it or build on it. The
        code for each step is linked; the datasets and packages are listed with their sources on{" "}
        <Link href="/sources" className="text-myco-green hover:underline">
          Data and sources
        </Link>
        .
      </PageHeader>
      <div className="container mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div className="grid gap-10 lg:grid-cols-[13rem_1fr]">
          <nav className="hidden lg:block" aria-label="On this page">
            <ol className="sticky top-24 space-y-1 text-sm">
              {SECTIONS.map((s) => (
                <li key={s.id}>
                  <a href={`#${s.id}`} className="block text-[#5c4a3a] hover:text-myco-green">
                    {s.title}
                  </a>
                </li>
              ))}
            </ol>
          </nav>

          <div className="max-w-3xl space-y-10 text-[#5c4a3a] leading-relaxed">
            <Section id="brief" title="In brief">
              <p>
                A habitat map answers one question: given the climate, soil and cover of a place,
                how much does it resemble the places this fungus has been found? Atlas answers it
                for every North American fungus with enough DNA-confirmed collections, three ways,
                and publishes the maps, the scores, the code and the intermediate data so that the
                answer can be checked and reused.
              </p>
              <ol className="list-decimal space-y-1 pl-5">
                <li>Pull every MycoMap collection whose name was confirmed by DNA.</li>
                <li>Describe every cell of North America (5 km now, 1 km for releases) with 33 environmental predictors.</li>
                <li>Compare each species with every other sequenced collection near it, so the model learns habitat, not where people collect.</li>
                <li>Fit Maxent, boosted trees and a random forest on the same records and background.</li>
                <li>Score each on whole 200 km regions it never saw.</li>
                <li>Publish maps and scores as a versioned, reproducible release.</li>
              </ol>
            </Section>

            <Section id="records" title="Records">
              <p>
                A record trains a model only when its name is confirmed by DNA: it is{" "}
                <B>green in at least one MycoMap validation project and red in none</B>. Photo
                identifications, herbarium names and unassessed records are left out. An old
                species concept can be wrong even after its synonyms are sorted out, and a model
                trained on a wrong name draws a confident, wrong map.
              </p>
              <p>A record must also:</p>
              <ul className="list-disc space-y-1 pl-5">
                <li>have coordinates that are present and not obscured;</li>
                <li>be accurate to within 1 km, where an accuracy was recorded;</li>
                <li>lie in North America (United States, Canada, Mexico, Puerto Rico, US Virgin Islands);</li>
                <li>carry a species-level name. Provisional names count.</li>
              </ul>
              <p>
                On production in September 2026 that left <B>127,823 records across 17,590 taxa</B>.
                Records green in one project and red in another (2,840 of them) are excluded as
                contested.
              </p>
              <p>
                Provisional names such as <Sci>Mycena</Sci> sp. &lsquo;IN10&rsquo; are DNA clusters
                with no formal name yet. They make up about a third of the taxa with enough records
                to map. They are codes, not ranges, and can be renamed or re-clustered, so{" "}
                <B>a model belongs to its record set, not to its name</B>. Each taxon's records are
                hashed into a fingerprint, and a model is refitted when the fingerprint changes.
              </p>
              <p>
                Exact coordinates never leave the machines that fit the models. Anything drawn on
                this site is aggregated to 0.1° cells, and anything published is 1 km or coarser.
              </p>
            </Section>

            <Section id="grid" title="The grid">
              <p>
                Everything is modelled on a <B>North America Albers Equal Area Conic</B> projection,
                so a cell covers the same ground in Oaxaca and in Nunavut. That matters twice:
                habitat area is reported in km², and spatial blocking needs real distances. Two
                grids share one extent and their cells nest exactly.
              </p>
              <Table
                head={["Grid", "Cell", "Cells", "Used for"]}
                rows={[
                  ["draft", "5 km", "3.7 million", "the maps on this site today"],
                  ["production", "1 km", "94 million", "published releases"],
                ]}
              />
            </Section>

            <Section id="predictors" title="Environmental predictors">
              <p>
                Thirty-three predictors, all from sources that cover the whole continent. The
                obvious United States products (TreeMap, NLCD, PAD-US) stop at the border, and
                British Columbia alone holds 8% of the records.
              </p>
              <Table
                head={["Group", "Predictors", "Source"]}
                rows={[
                  [
                    "Climate",
                    "bio1–bio19: annual and seasonal temperature and precipitation, 1970–2000",
                    <DatasetLink id="worldclim" />,
                  ],
                  ["Elevation", "elevation", <DatasetLink id="worldclim" />],
                  ["Terrain", "slope, roughness (derived from elevation on the grid)", <Ext href="https://rspatial.github.io/terra/reference/terrain.html">terra::terrain</Ext>],
                  ["Soil, 0–5 cm", "pH, organic carbon, clay, sand, cation exchange capacity", <DatasetLink id="soilgrids" />],
                  [
                    "Land cover",
                    "fraction of each cell under trees, shrubs, grass, wetland, open water, built-up",
                    <DatasetLink id="worldcover" />,
                  ],
                ]}
              />
              <p>
                Each source is cropped to the region before it is reprojected, then resampled onto
                the grid. Sea level is filled as 0 before slope is computed; without that, every
                coastal cell came out empty and 10.7% of records were silently dropped. The build is{" "}
                <Ext href={`${GITHUB_URL}/blob/main/R/layers.R`}>R/layers.R</Ext>.
              </p>
            </Section>

            <Section id="background" title="Background">
              <p>
                A presence-only model compares where a species was found with a sample of where it
                could have been. The choice of that sample decides what the model learns.
              </p>
              <p>
                Six states and provinces hold 61% of MycoMap's records, and Indiana alone holds 12%.
                Against random points across the continent, almost every fungus would appear to love
                Indiana's climate, because that is where the sequencing happened. So Atlas uses a{" "}
                <B>target-group background</B> (Phillips et al. 2009): 10,000 cells drawn from every
                other DNA-validated collection. Those carry the same bias as the presences, and the
                model answers a better question — given that someone collected and sequenced a
                fungus here, what makes it this one?
              </p>
              <ul className="list-disc space-y-1 pl-5">
                <li>
                  The background keeps its density: a cell collected from a hundred times counts a
                  hundred times. That is the effort signal, not noise.
                </li>
                <li>
                  It is drawn only from the <B>accessible area</B>, the species' own cells buffered
                  by 500 km. A fungus is not absent from Yukon because nobody looked there.
                </li>
                <li>
                  The random seed comes from the record-set fingerprint, so the same records always
                  draw the same background.
                </li>
              </ul>
              <p>
                Code: <Ext href={`${GITHUB_URL}/blob/main/R/background.R`}>R/background.R</Ext>.
              </p>
            </Section>

            <Section id="selection" title="Choosing predictors">
              <p>
                Thirty-three predictors is a lot of rope for a taxon with forty records, and the
                bioclim variables are near-copies of one another. For Maxent, correlated predictors
                are pruned before fitting:
              </p>
              <ol className="list-decimal space-y-1 pl-5">
                <li>
                  Correlation is measured <B>on the background</B>, which describes the environment
                  available to the species. Forty presences cannot estimate a correlation matrix.
                </li>
                <li>
                  Of any pair with |r| ≥ 0.7, the one earlier in a fixed <B>ecological order</B>{" "}
                  survives: moisture, then temperature, then cover, then soil, then terrain. When
                  two variables are interchangeable, the one a mycologist would name is kept, and
                  the response curves stay readable.
                </li>
                <li>
                  The count is capped at about <B>one predictor per four presence cells</B>.
                </li>
              </ol>
              <p>
                A sweep over 153 taxa, each scored against itself on shared folds, set the ratio.
                Removing the cap cost 0.089 ± 0.033 of Boyce for taxa with 20–29 cells and
                0.070 ± 0.027 at 30–49, while AUC moved by only 0.016. One predictor per two was
                worse; one per three and one per six were within noise. Above about 100 cells the
                cap stops binding.
              </p>
              <p>
                The two tree models get all 33 predictors. Trees are not confused by correlated
                inputs the way a regression is, and in the benchmark boosted trees did worse when
                restricted to Maxent's list (−0.011 ± 0.003 AUC).
              </p>
            </Section>

            <Section id="models" title="Three models">
              <p>
                Every taxon is fitted three ways, from the same training table, against the same
                background, on the same folds. Only the learner differs. None is right by default:
                where the three agree, the pattern is in the records; where they part, the map is
                saying more about the model than the fungus.
              </p>
              <Table
                head={["Model", "Package", "Settings"]}
                rows={[
                  [
                    <B>Maxent</B>,
                    <Ext href="https://github.com/mrmaxent/maxnet">maxnet</Ext>,
                    "Linear and quadratic features, plus hinge from 30 presence cells; regularisation multiplier 1; pruned predictors; cloglog output, clamped outside the training range.",
                  ],
                  [
                    <B>Boosted trees</B>,
                    <Ext href="https://github.com/dmlc/xgboost">xgboost</Ext>,
                    "Learning rate 0.05, depth 3, min child weight 5, row sample 0.75, column sample 0.8; presences and background weighted equally; tree count by early stopping on spatial folds inside the training data only. Fitted only from 50 presence cells.",
                  ],
                  [
                    <B>Random forest</B>,
                    <Ext href="https://github.com/imbs-hl/ranger">ranger</Ext>,
                    "1,000 probability trees, each grown on as many background cells as presences, drawn afresh per tree (down-sampling; Valavi et al. 2021).",
                  ],
                ]}
              />
              <p>
                The random forest is one of the three final models. No model is used to prepare a
                layer or pick records for another; each learns directly from the training table.
              </p>
              <p>
                Benchmark on the draft grid, 268 taxa with 50+ presence cells, paired against
                Maxent: the random forest gained <B>+0.020 ± 0.002 AUC</B> and{" "}
                <B>+0.131 ± 0.010 Boyce</B> and had the best AUC for 54% of taxa. Boosted trees tied
                Maxent (−0.002 AUC). Extending the benchmark to 20 cells (475 taxa) showed boosted
                trees ranking ground backwards on sparse taxa (Boyce 0.35 below Maxent at 20–29
                cells), which is why they stop at 50. The forest never did worse than Maxent in any
                band. Details are on the{" "}
                <Link href="/models" className="text-myco-green hover:underline">
                  Models page
                </Link>
                .
              </p>
            </Section>

            <Section id="evaluation" title="Evaluation">
              <p>
                Collections come in clusters: one foray can yield thirty from a single wood. A random
                hold-out leaves near neighbours on both sides and reports only that the model can
                interpolate 200 m (Roberts et al. 2017). Instead the continent is cut into{" "}
                <B>200 km blocks</B>, the blocks are dealt into <B>five folds</B>, and each model is
                scored on whole blocks it was not trained on.
              </p>
              <p>
                <B>Blocked AUC</B> is how well a map separates this fungus from other collections;
                0.5 is chance. Against a target-group background it is comparative, not absolute: a
                generalist that grows wherever people look scores near 0.5 by construction, and that
                is the honest answer.
              </p>
              <p>
                <B>Boyce</B> (Hirzel et al. 2006) slides a window across the predicted range and
                asks whether higher-rated ground holds proportionally more held-out records. It is
                the rank correlation of that ratio with suitability: 1 is consistent, 0 no better
                than the background, negative upside down. Atlas uses 100 windows each a tenth of
                the range wide. It is unsteady below about 50 presences.
              </p>
              <p>
                Across all 1,224 mapped taxa the median blocked scores are Maxent AUC 0.649 / Boyce
                0.263 and random forest 0.669 / 0.291.
              </p>
            </Section>

            <Section id="thresholds" title="How much data a map needs">
              <p>
                A map needs presences in <B>at least 20 separate grid cells</B>; boosted trees need
                50. Record counts mislead: <Sci>Lysurus mokusin</Sci> has 105 records from 4
                distinct 5 km cells — one urban population, collected over and over. Below the line a
                taxon is refused rather than modelled, and it becomes a survey target: every
                sequenced collection from a new place brings its map closer.
              </p>
              <p>
                Of the 17,590 taxa, 1,266 clear 20 cells on the draft grid and 268 clear 50.
              </p>
            </Section>

            <Section id="maps" title="Drawing the maps">
              <p>
                Each model predicts every cell in the accessible area. Outside it the map is blank,
                which is why colour stops in arcs 500 km from the nearest record: there the map
                makes no claim.
              </p>
              <p>
                The three models put their scores on different scales (on{" "}
                <Sci>Pluteus petasatus</Sci>, Maxent spans 0.03–1.00 and boosted trees 0.27–0.63), so
                each map is <B>coloured by percentile within its own area</B>. The darkest green is
                the ground that model rates highest. The stored rasters keep the raw values. Maps are
                reprojected to Web Mercator for display; collections are drawn as 0.1° cells.
              </p>
            </Section>

            <Section id="reproducibility" title="Reproducibility">
              <ul className="list-disc space-y-1 pl-5">
                <li>
                  A model is current only while its record-set fingerprint <B>and</B> its settings
                  match. The settings include a hash of every layer build, so a rebuilt layer
                  refits everything.
                </li>
                <li>
                  Only the release container publishes: one image pinned by digest, with R packages
                  from a dated snapshot. Anyone can run the same image.
                </li>
                <li>
                  A release stores every file once by its SHA-256 and records the code commit,
                  package versions, layer builds and pull fingerprint. Rolling back is one pointer.
                </li>
                <li>
                  Everything is tested, including simulation tests that plant a species with a
                  known response on a synthetic landscape and check the fit recovers it.
                </li>
              </ul>
            </Section>

            <Section id="limits" title="What the maps are not">
              <p>
                They are <B>habitat suitability, not occurrence</B>: a high value means a place
                resembles where the species has been found, not that it is there. No continental map
                of tree species exists, so the models know how wooded a place is but not which trees
                grow there — a real gap for mycorrhizal fungi. Climate is a 1970–2000 average. And the
                maps can only be as good as where people have collected and sequenced.
              </p>
            </Section>

            <Section id="next" title="What comes next">
              <ul className="list-disc space-y-1 pl-5">
                <li>1 km releases, recomputed regularly on remote workers as records arrive.</li>
                <li>Downloads of every intermediate product (see <Link href="/sources" className="text-myco-green hover:underline">Data and sources</Link>).</li>
                <li>Phase 2: MycoMap's own eDNA and GlobalFungi — the only non-detection data — and lower-weighted unassessed records.</li>
                <li>Conservation metrics for mycomap.org, and a geographic prior for MycoMap Vision.</li>
              </ul>
            </Section>

            <Section id="cite" title="Cite and contribute">
              <p>
                Cite the release you used: its id and fingerprint are in{" "}
                <Link href="/developers#getStatus" className="text-myco-green hover:underline">
                  /api/status
                </Link>
                . Cite the datasets and packages behind it from{" "}
                <Link href="/sources" className="text-myco-green hover:underline">
                  Data and sources
                </Link>
                .
              </p>
              <p>
                The code is GPL-3.0-or-later. Issues, method critiques and pull requests are welcome;
                the fastest way to improve a map is to collect and sequence more of that species
                through{" "}
                <Ext href="https://mycomap.org/network">MycoMap's free sequencing network</Ext>.
              </p>
              <a
                href={GITHUB_URL}
                className="inline-flex items-center gap-2 rounded-md border border-[#A87146]/20 px-3 py-2 text-sm font-medium text-[#4a3728] hover:border-myco-green hover:text-myco-green"
              >
                <GithubMark /> BiodiverseLabs/mycomap-atlas <ArrowUpRight className="h-3.5 w-3.5" />
              </a>
            </Section>
          </div>
        </div>
      </div>
    </>
  );
}
