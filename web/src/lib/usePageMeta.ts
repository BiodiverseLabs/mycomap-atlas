import { useEffect } from "react";
import { useLocation } from "wouter";

import { documentTitle, metaTags, type MetaTag, type PageMeta } from "@/lib/pageMeta";

function setTag({ attr, key, content }: MetaTag) {
  let tag = document.head.querySelector<HTMLMetaElement>(`meta[${attr}="${key}"]`);
  if (content === null) {
    tag?.remove();
    return;
  }
  if (!tag) {
    tag = document.createElement("meta");
    tag.setAttribute(attr, key);
    document.head.appendChild(tag);
  }
  tag.setAttribute("content", content);
}

function apply(meta: PageMeta) {
  document.title = documentTitle(meta.title);
  for (const tag of metaTags(meta, window.location.href)) setTag(tag);
}

/**
 * Set the page's title and description (and noindex) while it is shown. On
 * leaving, the site's defaults come back, so a page that sets none never
 * inherits the last page's title.
 */
export function usePageMeta({ title, description, noindex }: PageMeta) {
  const [location] = useLocation();
  useEffect(() => {
    apply({ title, description, noindex });
    return () => apply({});
  }, [title, description, noindex, location]);
}
