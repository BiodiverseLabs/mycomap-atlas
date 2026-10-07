import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";

import {
  DESCRIPTION_MAX,
  SITE_DESCRIPTION,
  SITE_NAME,
  documentTitle,
  metaDescription,
  metaTags,
} from "./pageMeta.ts";

const tag = (tags: ReturnType<typeof metaTags>, key: string) => tags.find((t) => t.key === key);

test("a page's title names the page first, then the site", () => {
  assert.equal(documentTitle("Maps"), "Maps · MycoMap Atlas");
  assert.equal(documentTitle("  What could   grow here? "), "What could grow here? · MycoMap Atlas");
});

test("the home page's title is the site's name alone, never doubled", () => {
  assert.equal(documentTitle(), SITE_NAME);
  assert.equal(documentTitle(""), SITE_NAME);
  assert.equal(documentTitle(SITE_NAME), SITE_NAME);
});

test("a page with no description of its own gets the site's", () => {
  assert.equal(metaDescription(), SITE_DESCRIPTION);
  assert.equal(metaDescription("   "), SITE_DESCRIPTION);
});

test("a description is one line, cut at a word to fit a search result", () => {
  const long =
    "Every taxon with a fitted habitat map, and how each of the three models scores it on\n" +
    "regions it never saw. Blocked AUC says how well a map tells the places this fungus was found " +
    "from the other places people collected: 0.5 is chance.";
  const cut = metaDescription(long);
  assert.ok(cut.length <= DESCRIPTION_MAX, `${cut.length} characters`);
  assert.ok(!cut.includes("\n"));
  assert.ok(cut.endsWith("…"));
  // Whole words only: what is left before the ellipsis starts the original.
  assert.ok(long.replace(/\s+/g, " ").startsWith(cut.slice(0, -1)));
  assert.equal(metaDescription("Short and whole."), "Short and whole.");
});

test("a page that is not there is kept out of search results, and no other page is", () => {
  assert.equal(tag(metaTags({ title: "Page not found", noindex: true }, "https://x/nope"), "robots")?.content, "noindex");
  // null removes the tag the missing page left behind.
  assert.equal(tag(metaTags({ title: "Maps" }, "https://x/maps"), "robots")?.content, null);
});

test("link previews carry the page's own title and address, without its query", () => {
  const tags = metaTags({ title: "Maps", description: "Every map." }, "https://atlas.mycomap.org/maps?sort=auc#top");
  assert.equal(tag(tags, "og:title")?.content, "Maps · MycoMap Atlas");
  assert.equal(tag(tags, "twitter:title")?.content, "Maps · MycoMap Atlas");
  assert.equal(tag(tags, "og:description")?.content, "Every map.");
  assert.equal(tag(tags, "og:url")?.content, "https://atlas.mycomap.org/maps");
});

test("every page sets its own title, so none wears the last page's or the bare site name", () => {
  const pages = new URL("../pages/", import.meta.url);
  const files = readdirSync(pages).filter((f) => f.endsWith(".tsx"));
  assert.ok(files.length >= 10, `${files.length} pages`);
  const missing = files.filter((f) => !/\busePageMeta\(\{/.test(readFileSync(new URL(f, pages), "utf8")));
  assert.deepEqual(missing, []);
});

test("an embedded map is kept out of search results, where crawlers can see that it is", () => {
  const embed = readFileSync(new URL("../pages/Embed.tsx", import.meta.url), "utf8");
  assert.match(embed, /usePageMeta\(\{[^;]*noindex: true[^;]*\}\);/);
  // robots.txt must let crawlers fetch the page, or they never read its noindex.
  const robots = readFileSync(new URL("../../public/robots.txt", import.meta.url), "utf8");
  assert.doesNotMatch(robots, /^Disallow:\s*\/embed/m);
});

test("index.html, which crawlers that run no script read, carries the same defaults", () => {
  const html = readFileSync(new URL("../../index.html", import.meta.url), "utf8").replace(/\s+/g, " ");
  const content = (attr: string, key: string) =>
    html.match(new RegExp(`<meta ${attr}="${key}" content="([^"]*)"`))?.[1];
  assert.equal(html.match(/<title>([^<]*)<\/title>/)?.[1], SITE_NAME);
  for (const [attr, key] of [
    ["name", "description"],
    ["property", "og:description"],
    ["name", "twitter:description"],
  ]) {
    assert.equal(content(attr, key), SITE_DESCRIPTION, key);
  }
  assert.equal(content("property", "og:title"), SITE_NAME);
  assert.equal(content("name", "twitter:title"), SITE_NAME);
  assert.equal(content("name", "robots"), undefined, "the shell itself must never be noindex");
});
