# Changelog

What changed for people who read Atlas's maps or call its API. The API is in
beta, versioned `0.1.0-dev` in [`inst/api/openapi.json`](inst/api/openapi.json);
a breaking change to it is announced here and on the Developers page at least
30 days before it ships. Commits carry the full reasoning; this file says what
changed and what it means for you.

## Unreleased

### API

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
- Model metrics gain `map_strength` (0 for a map that failed its null test,
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

### Maps

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
  of it. A MyCoPortal record placed on a county's or state's centre is left
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

### Methods and studies (no change to production fits)

- `study-virtual`: virtual species with a known habitat, collected at the
  real survey sites with their real effort, to compare Maxent's effort
  handling, a detection model and the forest against the truth. Result:
  production Maxent, without an effort correction, stays.
- `study-blocks`: whether the cross-validation block size tests at the
  distances a map predicts at (kNNDM's question).
- Null models that keep a taxon's clustering (`shift`, `shift-effort`), a
  sequential early-stopping test and Benjamini-Hochberg q-values, being
  calibrated before production uses them.
- Candidate layers, not yet in production: ClimateNA 1991-2020 normals (the
  test kept WorldClim), and host trees by species, one band for each of 316
  tree species beside the genera. Walnut, hackberry, bald cypress, redwoods
  and incense-cedar join the host genera, elm keeps a place where it is at
  least 1% of the trees, and all host layers show as "Host trees".
- The Methods page matches the code: the record rules, the number of
  predictors and models, the area of applicability, map strength, the
  combined map and the null test's limits.

### The site

- Map backgrounds now come from Stadia Maps (the OSM Bright style, drawn from
  OpenStreetMap data) instead of OpenStreetMap's own tile servers, whose
  policy is for light use. The credits under every map, the footer, the
  Sources page and the privacy page say so.
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
