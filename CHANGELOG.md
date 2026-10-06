# Changelog

What changed for people who read Atlas's maps or call its API. The API is in
beta, versioned `0.1.0-dev` in [`inst/api/openapi.json`](inst/api/openapi.json);
a breaking change to it is announced here and on the Developers page at least
30 days before it ships. Commits carry the full reasoning; this file says what
changed and what it means for you.

## Unreleased

### API

No change to any route or field.

### The site

- A privacy page (`/privacy`): no analytics, a cookie only on sign-in, what
  the web logs keep, and what Cloudflare and OpenStreetMap see.
- Fonts are served from the site instead of Google Fonts, and map
  backgrounds come from `tile.openstreetmap.org` rather than its retired
  `{s}.` subdomains.
- Every page has its own title and description, with link-preview tags;
  `robots.txt` points to a sitemap; an unknown address and an embedded
  map (`/embed/taxa/...`) are marked `noindex`.
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
