# Changelog

What changed for people who read Atlas's maps or call its API. The API is in
beta, versioned `0.1.0-dev` in [`inst/api/openapi.json`](inst/api/openapi.json);
a breaking change to it is announced here and on the Developers page at least
30 days before it ships. Commits carry the full reasoning; this file says what
changed and what it means for you.

## Unreleased

### API

- **Model `grade`** on `/api/models`, `/api/taxa/{name}/model` and the
  release index: `strong` (passed its null test against shifted nulls),
  `weak` (not shown to beat clustered collecting), `failed` or `untested`.
  Decide whether to use a map on `grade == "strong"`, not on `skill`: a fit
  from before 2026-10-08 can have `skill: passed` against scattered nulls,
  which is `weak`. Added field. `null` gains `design`, `stopped_early` and
  `drawn`.

- **Stricter inputs.** Every `/api/` route refuses, with 400 and a JSON
  reason, a `grid` other than `draft` or `production`, and a `limit`,
  `offset`, `min_localities`, `lat`, `lng`, `min_score`, `nearby_km` or
  `width` that is not a finite number. These used to fail as 500s or be
  ignored. `/api/taxa` returns at most 1,000 rows a page: page with
  `offset` for more.
- **`GET /api/status`** gains `release`: the id, grid, creation time, code
  commit and the pull (time, records, taxa, fingerprint) of the release this
  server serves, beside the newest pull. Cite the release id. Added field.
- **`GET /api/taxa/{name}/ensemble`** and
  **`/ensemble.png?layer=map|disagreement`** are new: the average of a
  taxon's passing models, and where they disagree. A taxon with fewer than
  two passing models has none (404).
- Model metrics gain `map_strength` (0 for a weak or failed map,
  0.4 to 1 with its margin over the nulls), `applicability` (the area of
  applicability's threshold and the share of the accessible area inside it)
  and `record_years` (dated records, first, median and last year, share
  before 1991). Added fields.
- Every map image, ensemble image and GeoTIFF response carries
  `Link: <https://creativecommons.org/licenses/by-sa/4.0/>; rel="license"`.
- Errors are JSON everywhere, image routes included, and every answer from
  400 up is `no-store`. Public answers keep `Cache-Control: public` (five
  minutes; a minute for `/api/status`), except `/api/here`, which carries the
  visitor's point and is `private, no-store`.
- `/api/models` is rebuilt at most once a minute, so a model fitted moments
  ago can take up to a minute to appear.
- **`GET /api/names/{name}`** is new: the name Atlas uses now for a name
  you have. It answers with the name itself when it is current, the one
  current name it is another spelling of (punctuation and case only), or
  the name its records were renamed to on mycomap.org (`how`: `current`,
  `spelling` or `renamed`, with `via` listing earlier names). 404 when none
  applies. Releases carry `occurrences/renames.json`.

### Maps

- **A stricter null test.** Every map is tested against null species that
  keep its own clustering (its detections rotated and moved onto other
  survey sites), up to 99, stopping once 5 do as well. The old scattered
  nulls let clustered collecting alone pass. Expect far fewer maps to pass:
  on simulated species about a quarter of real habitat signals did. Only
  strong maps are used for Explore, state verdicts ("likely" and
  "possible"), combined maps and the sitemap; weak and failed maps are drawn
  faint on their taxon page, worded "skill on held-out ground, but not shown
  to beat clustered collecting" (weak) or "no better than chance on held-out
  ground" (failed). Every model is refitted.

- **Colour now follows skill and data.** Each map is ranked on the
  equal-area grid, only over its area of applicability (Meyer and Pebesma
  2021); ground with conditions no training site resembles is hatched grey
  and left out of the ranking. The overlay's opacity follows `map_strength`.
  A taxon with two or more passing models also gets a combined map and a
  layer showing where they disagree.
- **Every stored model is refitted** on the next full run: the design now
  records the area of applicability.
- **Fewer, better-placed records.** A Mushroom Observer record needs a
  visible GPS point, or a named location whose centre is within 5 km of all
  of it, and its coordinate now comes from Mushroom Observer's own answer:
  the GPS point, or else that location's centre. mycomap.org's copy often
  held the centre of a larger place, or a point outside the location. A
  hidden GPS point counts as none, so the location decides. A MyCoPortal record placed on a county's or state's centre is left
  out. Records with no cached answer yet are kept. Some taxa may drop below
  the sites a model needs.
- A sparse map that failed its null test no longer quotes a skill rate
  borrowed from thinned common fungi; it says there are too few sites to
  tell.
- Every taxon's maps carry a notice of what they are (suitable habitat, not
  presence or abundance; never for deciding what is safe to eat or for
  permits), a provisional-name warning where it applies, a citation with
  the release id and a Copy button, and the maps' licence: CC BY-SA 4.0,
  as they derive from WorldClim 2.1. The footer credits every source.
- Public pages say what is missing ("too few sites", "waits for the next
  rebuild") instead of naming a command to run.
- **Old links keep working.** A taxon page opened under a name Atlas no
  longer uses goes to the current name's page and says "Formerly …" or
  "… is another spelling of this name". Renames are found by comparing each
  full pull with the one before, by record id, from the next full pull on.

### Methods and studies (no change to production fits)

- `study-virtual`: virtual species with a known habitat, collected at the
  real survey sites with their real effort, to compare Maxent's effort
  handling, a detection model and the forest against the truth. Result:
  production Maxent, without an effort correction, stays.
- `study-blocks`: whether the cross-validation block size tests at the
  distances a map predicts at (kNNDM's question).
- Null models that keep a taxon's clustering (`shift`, `shift-effort`), a
  sequential early-stopping test and Benjamini-Hochberg q-values. Calibrated
  on 99 virtual species: scattered nulls passed 74% of species with no
  habitat signal, shifted ones 2%; production now uses shifted nulls (see
  Maps).
- Candidate layers, not yet in production: ClimateNA 1991-2020 normals (the
  test kept WorldClim), and host trees by species, one band for each of 316
  tree species beside the genera. Walnut, hackberry, bald cypress, redwoods
  and incense-cedar join the host genera, elm keeps a place where it is at
  least 1% of the trees, and all host layers show as "Host trees".
- The Methods page matches the code: the record rules, the number of
  predictors and models, the area of applicability, map strength, the
  combined map and the null test's limits.

### The site

- **How to read a map** (`/guide`), linked from every taxon page and the home
  page: what the colours, dots and hatching mean, strong and faint maps (with
  the notes faint maps carry), the combined map and where its models
  disagree, and what a map is not: suitable habitat, not a sighting, and not
  for foraging.
- The home page says in two sentences what Atlas is and how it differs, then
  offers four ways in: explore a species, what could grow near me, embed or
  download, and how it works. Its preview map is a strong map once the
  release has any.
- A featured-species slot on the home page, filled from `web/public/featured.json`
  (up to three names, each with an optional note). It stays hidden while the
  list is empty.
- On a phone, each map's full-screen button is a thumb-sized target, and the
  "expand across all three panels" button is hidden, since the panels stack
  full width there anyway.
- A privacy page (`/privacy`): no analytics, a cookie only on sign-in, what
  the web logs keep, and what Cloudflare and OpenStreetMap see.
- Fonts are served from the site instead of Google Fonts, and every map's
  background comes from `tile.openstreetmap.org` rather than its retired
  `{s}.` subdomains.
- Every page, taxon pages included, has its own title and description, with
  link-preview tags; `robots.txt` points to a sitemap; an embedded map
  (`/embed/taxa/...`) is marked `noindex`, and an unknown address is
  answered with the app's not-found page, a 404 and `noindex`.
- The Developers page says how stable the API is (this file's promise).
- The footer links to reporting a map problem on GitHub, and to the private
  route for a map that shows a collection site too precisely.

### The server

- `atlas sitemap` writes the site's pages and every taxon whose model passed
  its null test and drew a map. The nightly job puts it in the web root after
  `pull-release`, and a deploy keeps it.
- A failed nightly run, or an API that stops answering (checked every 5
  minutes), is recorded in the journal (`atlas-alert`), in
  `/srv/atlas/data/health` and in the login banner.
- nginx keeps the API's public answers for as long as their own headers
  allow, never for a token holder, sign-in or an error; requests for the
  same thing at once wait for one answer. deploy.sh does not install nginx
  files: the new site configuration is copied to the box by hand.
