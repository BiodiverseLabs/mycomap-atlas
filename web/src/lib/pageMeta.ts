// Each page's title and description, for the browser tab, search results and
// link previews. Pure, so `node --test` checks it; usePageMeta.ts puts it in
// the document. index.html carries the same defaults for crawlers that do
// not run the app (pageMeta.test.ts checks the two agree).

export const SITE_NAME = "MycoMap Atlas";
export const SITE_DESCRIPTION =
  "Species distribution models for fungi, built from DNA-validated MycoMap records.";

// Search results show about this many characters of a description.
export const DESCRIPTION_MAX = 160;

export interface PageMeta {
  /** The page's own name; the site's name is added after it. */
  title?: string;
  /** One or two sentences on what the page holds. */
  description?: string;
  /** Keep the page out of search results (a page that is not there). */
  noindex?: boolean;
}

export interface MetaTag {
  attr: "name" | "property";
  key: string;
  /** null: the tag is removed. */
  content: string | null;
}

/** "Maps · MycoMap Atlas"; the site's name alone for the home page. */
export function documentTitle(title?: string): string {
  const own = (title ?? "").replace(/\s+/g, " ").trim();
  return own && own !== SITE_NAME ? `${own} · ${SITE_NAME}` : SITE_NAME;
}

/** On one line, and cut at a word to fit a search result. */
export function metaDescription(description?: string): string {
  const text = (description ?? "").replace(/\s+/g, " ").trim() || SITE_DESCRIPTION;
  if (text.length <= DESCRIPTION_MAX) return text;
  const cut = text.slice(0, DESCRIPTION_MAX - 1);
  const space = cut.lastIndexOf(" ");
  return `${(space > DESCRIPTION_MAX / 2 ? cut.slice(0, space) : cut).replace(/[\s,;:.]+$/, "")}…`;
}

/** Every head tag a page sets, for the page at url (query and hash dropped). */
export function metaTags(meta: PageMeta, url: string): MetaTag[] {
  const title = documentTitle(meta.title);
  const description = metaDescription(meta.description);
  const canonical = url.replace(/[?#].*$/, "");
  return [
    { attr: "name", key: "description", content: description },
    { attr: "property", key: "og:title", content: title },
    { attr: "property", key: "og:description", content: description },
    { attr: "property", key: "og:url", content: canonical },
    { attr: "name", key: "twitter:title", content: title },
    { attr: "name", key: "twitter:description", content: description },
    { attr: "name", key: "robots", content: meta.noindex ? "noindex" : null },
  ];
}
