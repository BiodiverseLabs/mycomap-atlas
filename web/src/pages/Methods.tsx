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
  { id: "background", title: "Sites and effort" },
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
                <li>Describe every cell of North America (5 km now, 1 km for releases) with 58 environmental predictors, including which trees grow there and what kind of forest it is.</li>
                <li>Gather all collections into survey sites, and for each species mark the sites where it was found and the sites where people collected other fungi but not it.</li>
                <li>Fit Maxent, boosted trees and a random forest to the same sites, with collecting effort as a predictor for the trees, held fixed when the map is drawn, so the model learns habitat, not where people collect.</li>
                <li>Tune each model and score it on whole regions it never saw, blocks as wide as the species' finds are spatially alike.</li>
                <li>Test each map against null models, random handfuls of collections fitted the same way; a map that cannot beat them is marked and kept out of Explore.</li>
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
                Fifty-eight predictors. All but the host trees and forest type come from sources
                that cover the whole continent: the obvious United States products (TreeMap, NLCD,
                PAD-US) stop at the border, and British Columbia alone holds 8% of the records. No
                continental map of tree species exists, so the host trees join the two national
                forest inventories, and the forest type joins North America's land cover map to a
                global one where it stops.
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
                  [
                    "Host trees",
                    "share of a cell's trees that are each of 19 host genera (pine, oak, spruce, fir, Douglas-fir, hemlock, birch, poplar, beech, larch, chestnut, tanoak, hickory, alder, willow, basswood, hornbeam, hophornbeam, madrone), and the share that are conifers",
                    <span>
                      <DatasetLink id="bigmap" /> (lower 48), <DatasetLink id="nfi" /> (Canada)
                    </span>,
                  ],
                  [
                    "Forest type",
                    "share of each cell under needleleaf, broadleaf and mixed forest, counted from 30 m pixels; Hawaii and the Caribbean islands from a 100 m global map, with a predictor saying which",
                    <span>
                      <DatasetLink id="nalcms" />, filled from <DatasetLink id="copernicus-lc100" />
                    </span>,
                  ],
                ]}
              />
              <p>
                The two inventories measure different things, so both are brought to one unit:{" "}
                <B>the share of a cell's trees in each genus</B>, from 0 to 1. BIGMAP maps the
                biomass of each tree species at 30 m; it is read at 250 m points and averaged, and a
                genus's share is its biomass over the biomass of all species. The Canadian inventory
                maps each species' percentage of the trees at 250 m; a genus's share is its species'
                percentages, unidentified members of the genus included, over the needleleaf and
                broadleaf groups together. A cell with no trees has a share of 0.{" "}
                <B>Alaska, Hawaii, Puerto Rico and Mexico are in neither inventory.</B> One layer's
                gap should not take ground away from every model, so there the shares are 0 and one
                more predictor says the inventories were silent: those records still train models,
                those places are still mapped, and a model can tell "no such trees" from "nobody
                mapped the trees". Hazel has no layer in BIGMAP and is left out. Code:{" "}
                <Ext href={`${GITHUB_URL}/blob/main/R/hosts.R`}>R/hosts.R</Ext>.
              </p>
              <p>
                Each source is cropped to the region before it is reprojected, then brought onto
                the grid by <B>averaging</B> the source cells each grid cell covers, never by
                interpolation, which reads only the four source cells nearest a cell's centre and
                leaves the cell empty if any of them is: measured at the records, that had cost
                soil 10,321 records against 117. Land cells still empty afterwards, along the coast
                mostly, are filled from the cells around them up to 10 km away, where land is
                wherever the land-cover layer has data. Sea level is filled as 0 before slope is
                computed; without that, every coastal cell came out empty and 10.7% of records
                were silently dropped. The build is{" "}
                <Ext href={`${GITHUB_URL}/blob/main/R/layers.R`}>R/layers.R</Ext>.
              </p>
            </Section>

            <Section id="background" title="Sites and effort">
              <p>
                A model compares where a species was found with where it could have been found.
                The choice of that comparison decides what the model learns.
              </p>
              <p>
                Six states and provinces hold 61% of MycoMap's records, and Indiana alone holds 12%.
                Against random points across the continent, almost every fungus would appear to love
                Indiana's climate, because that is where the sequencing happened. So Atlas compares
                each species with <B>the other places people collected and sequenced fungi</B>{" "}
                (a target group; Phillips et al. 2009), and asks a better question: given that people
                collected here, was this species among what they found?
              </p>
              <ul className="list-disc space-y-1 pl-5">
                <li>
                  <B>Survey sites.</B> Every record is gathered into a site. Places with records are
                  thinned by distance, busiest first, so no two sites are closer than 5 km, and every
                  other record joins its nearest site. The spacing is in kilometres, not cells, so a
                  foray is one site on the 1 km grid just as on the 5 km one.
                </li>
                <li>
                  <B>Detection or not.</B> For each species, a site is a detection when any of its
                  records is that species, and a non-detection otherwise. Both are counted once per
                  site. An earlier version counted presences once per cell but the comparison once
                  per record, so a wood collected a hundred times counted a hundred times against
                  every species found there, and the best-surveyed ground looked worse than it was.
                </li>
                <li>
                  <B>Effort as a predictor.</B> How hard a site was worked goes into the boosted
                  trees and the random forest, and is held at one level, the median of the species' detection sites, whenever a
                  map is drawn or scored. Effort is the log of the site's records, with the
                  species' own records <B>counted once</B> however many there are, or a fungus
                  collected a hundred times in one wood would make that wood look well surveyed by
                  being there. Effort explains what effort explains, and the map shows the rest
                  (Warton, Renner &amp; Ramp 2013; Fithian et al. 2015). Maxent is fitted without
                  it: measured twice on 150-odd species, Maxent scored better without effort (+0.02
                  blocked AUC, Boyce unchanged), while the random forest did markedly worse
                  without it. Effort still decides where every null model draws its sites.
                </li>
                <li>
                  Sites are drawn only from the <B>accessible area</B>, the species' own sites
                  buffered by 500 km. A fungus is not absent from Yukon because nobody looked there.
                </li>
                <li>
                  The random seed comes from the record-set fingerprint, so the same records always
                  draw the same sites and folds.
                </li>
              </ul>
              <p>
                Code: <Ext href={`${GITHUB_URL}/blob/main/R/sites.R`}>R/sites.R</Ext> and{" "}
                <Ext href={`${GITHUB_URL}/blob/main/R/background.R`}>R/background.R</Ext>.
              </p>
            </Section>

            <Section id="selection" title="Choosing predictors">
              <p>
                Fifty-eight predictors is a lot of rope for a taxon with forty records, and the
                bioclim variables are near-copies of one another. For Maxent, correlated predictors
                are pruned before fitting:
              </p>
              <ol className="list-decimal space-y-1 pl-5">
                <li>
                  Correlation is measured <B>on the non-detection sites</B>, which describe the
                  environment available to the species. Forty detections cannot estimate a
                  correlation matrix.
                </li>
                <li>
                  Of any pair with |r| ≥ 0.7, the one earlier in a fixed <B>ecological order</B>{" "}
                  survives: soil pH first, among the strongest known drivers of where fungi occur
                  (Tedersoo et al. 2014), then moisture, temperature, cover, the rest of the soil,
                  and terrain. When two variables are interchangeable, the one a mycologist would
                  name is kept, and the response curves stay readable.
                </li>
                <li>
                  Where the host trees go depends on the fungus. Its genus is looked up in
                  FungalTraits (Põlme et al. 2020): for an <B>ectomycorrhizal</B> genus, which
                  cannot fruit without its partner tree, the host trees come straight after soil pH;
                  for every other guild, and for genera FungalTraits does not list, they come after
                  temperature and before land cover. Each model records the guild and the order it
                  was given.
                </li>
                <li>
                  The trees have an <B>allowance</B>: a third of an ectomycorrhizal fungus's
                  predictors, a fifth of any other's. The host trees are barely correlated with one
                  another, so without it a fungus with forty sites spent its ten predictors on soil
                  pH and nine trees, and had no climate at all. The ones kept are the conifer share
                  and then the commonest trees of the region, judged on the non-detection sites,
                  never on the detections.
                </li>
                <li>
                  The count is capped at about <B>one predictor per four detection sites</B>.
                </li>
                <li>
                  Effort is never pruned or counted against the cap; every model gets it.
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
                The two tree models get all 58 predictors, in any order; Maxent is never given the two that only say which source described a cell. Trees are not confused by correlated
                inputs the way a regression is, and in the benchmark boosted trees did worse when
                restricted to Maxent's list (−0.011 ± 0.003 AUC).
              </p>
            </Section>

            <Section id="models" title="Three models">
              <p>
                Every taxon is fitted three ways, from the same sites, on the same folds. Only the
                learner differs. None is right by default: where the three agree, the pattern is in
                the records; where they part, the map is saying more about the model than the
                fungus.
              </p>
              <Table
                head={["Model", "Package", "Settings (tuned ones in bold)"]}
                rows={[
                  [
                    <B>Maxent</B>,
                    <Ext href="https://github.com/mrmaxent/maxnet">maxnet</Ext>,
                    <>
                      <B>Feature classes</B> linear+quadratic or linear+quadratic+hinge;{" "}
                      <B>regularisation multiplier</B> 0.25, 0.5, 1, 2 or 4 (as ENMeval tunes them);
                      pruned predictors; cloglog output, clamped outside the training range.
                    </>,
                  ],
                  [
                    <B>Boosted trees</B>,
                    <Ext href="https://github.com/dmlc/xgboost">xgboost</Ext>,
                    <>
                      <B>Tree depth</B> 2, 3 or 5, with the <B>tree count</B> by early stopping;
                      learning rate 0.05, min child weight 5, row sample 0.75, column sample 0.8;
                      detections and non-detections weighted equally. Fitted only from 50 detection
                      sites.
                    </>,
                  ],
                  [
                    <B>Random forest</B>,
                    <Ext href="https://github.com/imbs-hl/ranger">ranger</Ext>,
                    <>
                      250 probability trees, each grown on as many non-detection sites as
                      detections, drawn afresh per tree (down-sampling; Valavi et al. 2021);{" "}
                      <B>predictors tried at each split</B> 2, √p or p/3.
                    </>,
                  ],
                ]}
              />
              <p>
                Settings are chosen by <B>nested spatial cross-validation</B>: for each held-out
                region, the candidates are compared on inner spatial folds of the other regions
                only, so the choice never sees the ground it is scored on. The final model is tuned
                the same way on all the folds.
              </p>
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
                interpolate 200 m (Roberts et al. 2017). Instead the continent is cut into square
                blocks, the blocks are dealt into <B>five folds</B>, and each model is scored on whole
                blocks it was not trained on.
              </p>
              <p>
                <B>Block size comes from the species.</B>{" "}
                <Ext href="https://github.com/rvalavi/blockCV">blockCV</Ext> fits a variogram to its
                detections and non-detections; beyond that range two sites say little about each
                other, so a block that wide keeps the held-out region honest (Valavi et al. 2019).
                The size is held between 50 and 300 km: below 50 a foray's cluster could straddle a
                boundary, above 300 a 500 km accessible area holds too few blocks. Widespread
                species usually reach the 300 km ceiling. The autocorrelation of the predictors
                themselves was measured too, and over a continent it runs to thousands of
                kilometres for climate, which would leave no blocks at all. Blocks holding
                detections are dealt first, spread evenly, so no fold is left with nothing to score.
              </p>
              <p>
                <B>Blocked AUC</B> is how well a map separates the sites where this fungus was found
                from the other surveyed sites; 0.5 is chance. It is comparative, not absolute: a
                generalist that grows wherever people look scores near 0.5 by construction, and that
                is the honest answer.
              </p>
              <p>
                <B>Boyce</B> (Hirzel et al. 2006) slides a window across the predicted range and
                asks whether higher-rated ground holds proportionally more held-out records. It is
                the rank correlation of that ratio with suitability: 1 is consistent, 0 no better
                than the background, negative upside down. Atlas uses 100 windows each a tenth of
                the range wide, and computes it once over the held-out scores of every fold
                together: a species with twenty sites leaves four detections in a fold, too few for
                an index of its own. It is still unsteady below about 50 detections.
              </p>
              <p>
                <B>Null models.</B> A score alone cannot say whether a map knows anything: where
                collecting is patchy, even a made-up species can score above 0.5. So every model is
                refitted 19 times on a <B>null species</B> — the same number of sites drawn at random
                from all surveyed sites, busier sites more often, as a random handful of collections
                would fall — on the same folds (Raes &amp; ter Steege 2007; the null models of
                ENMeval 2.0, Kass et al. 2021). The species and its nulls go through exactly one
                procedure, the model's untuned settings: settings tuned on the real finds and then
                handed to the nulls would tilt the test towards the species. A map{" "}
                <B>passes</B> when the species' blocked AUC
                beats every null (p ≤ 0.05) and its Boyce index is above zero. A map that fails is
                drawn faint, hidden from the Maps list unless asked for, and left out of Explore and
                of anything mycomap.org reads from a release.
              </p>
            </Section>

            <Section id="thresholds" title="How much data a map needs">
              <p>
                The three full models need <B>at least 20 detection sites</B>, in{" "}
                <B>at least 5 blocks</B> so that every fold has something to score; boosted trees
                need 50. Record counts mislead: <Sci>Lysurus mokusin</Sci> has 105 records from 4
                distinct places — one urban population, collected over and over.
              </p>
              <p>
                A taxon with <B>3 to 19 sites</B> gets one map instead, an{" "}
                <B>ensemble of small models</B> (Breiner et al. 2015). Every pair of its first ten
                predictors, in the same ecological order Maxent uses, gets a small regression of its
                own: the two variables and their squares, and effort, penalised so that a handful of
                detections cannot push it to certainty. Each small model is scored on blocks held
                out inside the taxon's sites, and the map averages them weighted by how well each
                did there; one no better than chance has no say. These taxa are scored on three
                folds of 100 km blocks rather than five of up to 300 km: few sites are rarely
                spread over five large blocks.
              </p>
              <p>
                How few sites can carry a map was measured, not assumed. Well-recorded fungi (40
                sites or more, 118 of them) were cut down to a few sites and fitted, and every map
                was scored on all the sites held out. At 8 sites the ensemble's Boyce index stayed
                within 0.04 of what all the sites gave it; at 5, half the maps still showed clear
                skill and 7% were no better than chance; at 3, 40% and 8%. Maxent fell apart below 20 on the same
                test, and a random forest cannot be fitted at 5. So from <B>5 sites</B> an ensemble
                map is drawn like any other, faint when it fails its null test; from{" "}
                <B>3 or 4</B> it is drawn only when it passes.
              </p>
              <p>
                Below 3 sites a taxon is a survey target: every sequenced collection from a new
                place brings its map closer. On the draft grid, 1,274 taxa have 20 or more sites,
                3,340 have 5 to 19 and 2,219 have 3 or 4. Clearing a line does not mean a map is
                trusted; the null models decide that.
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
              <p>
                Because every map has a darkest tenth, colour alone cannot show a map that knows
                nothing. That is what the null models are for: a map that did not beat them is drawn
                faint, with a note saying so.
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
                resembles where the species has been found, not that it is there. Which trees grow
                where comes from two national forest inventories, so it stops at their borders: in
                Alaska, Hawaii, Puerto Rico and Mexico the models know the climate and the soil but
                not the trees. The inventories are
                themselves models, from 2011 (Canada) and 2018 (United States), at a genus level
                that cannot tell one oak from another. Climate is a 1970–2000 average. And the maps
                can only be as good as where people have collected and sequenced.
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
