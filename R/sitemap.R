# The site's sitemap: its pages, and a page for every taxon with a map worth
# finding.
#
# Written from the model index on this machine, with no API call: the web
# server runs `atlas sitemap` after each pull-release (deploy/lightsail/
# nightly.sh), and nginx serves the file from the web root like robots.txt.
# A sitemap names taxa and pages only; nothing in it is a place.

# The app's own pages (web/src/App.tsx), in the order a reader meets them.
ATLAS_SITEMAP_PAGES <- c(
  "/", "/maps", "/here", "/models", "/taxa", "/methods", "/data", "/sources",
  "/developers", "/privacy"
)

# A sitemap may hold at most this many addresses (sitemaps.org).
ATLAS_SITEMAP_MAX <- 50000L

#' The taxa a sitemap lists: those with a drawn map from a strong model
#' (atlas_map_grade), under any algorithm, each once and in name order, with
#' the day its newest such model was built.
#'
#' A map that failed or was never tested still has a taxon page, but it is not
#' one to send searchers to.
atlas_sitemap_taxa <- function(models) {
  none <- data.frame(taxon = character(), lastmod = character(), stringsAsFactors = FALSE)
  if (is.null(models) || !nrow(models)) return(none)
  keep <- models$map %in% TRUE & models$grade %in% "strong" &
    !is.na(models$taxon) & nzchar(models$taxon)
  models <- models[keep, , drop = FALSE]
  if (!nrow(models)) return(none)
  day <- substr(as.character(models$built_at), 1L, 10L)
  day[!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", day)] <- NA_character_
  taxa <- sort(unique(models$taxon), method = "radix")
  newest <- vapply(taxa, function(t) {
    days <- day[models$taxon == t & !is.na(day)]
    if (length(days)) max(days) else NA_character_
  }, character(1), USE.NAMES = FALSE)
  data.frame(taxon = taxa, lastmod = newest, stringsAsFactors = FALSE)
}

#' A path segment encoded as the app encodes it (encodeURIComponent), so the
#' sitemap names the same address as the app's own links.
atlas_url_component <- function(x) {
  plain <- charToRaw("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
  vapply(enc2utf8(as.character(x)), function(s) {
    bytes <- charToRaw(s)
    paste(vapply(bytes, function(b) {
      if (b %in% plain) rawToChar(b) else sprintf("%%%02X", as.integer(b))
    }, character(1)), collapse = "")
  }, character(1), USE.NAMES = FALSE)
}

#' Text escaped for XML, including the apostrophe sitemaps.org asks for.
atlas_xml_escape <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE)
  x <- gsub("\"", "&quot;", x, fixed = TRUE)
  gsub("'", "&apos;", x, fixed = TRUE)
}

#' The sitemap as XML text.
#'
#' taxa is atlas_sitemap_taxa()'s table; origin is the public site, such as
#' https://atlas.mycomap.org.
atlas_sitemap_xml <- function(taxa, origin, pages = ATLAS_SITEMAP_PAGES) {
  if (!is.character(origin) || length(origin) != 1L || !grepl("^https?://[^/?#]+/?$", origin)) {
    stop("the sitemap needs the site's origin, such as https://atlas.mycomap.org", call. = FALSE)
  }
  origin <- sub("/$", "", origin)
  entry <- function(path, lastmod = NA_character_) {
    paste0(
      "  <url><loc>", atlas_xml_escape(paste0(origin, path)), "</loc>",
      if (!is.na(lastmod)) paste0("<lastmod>", lastmod, "</lastmod>"),
      "</url>"
    )
  }
  lines <- vapply(pages, entry, character(1), USE.NAMES = FALSE)
  if (nrow(taxa)) {
    paths <- paste0("/taxa/", atlas_url_component(taxa$taxon))
    lines <- c(lines, unlist(Map(entry, paths, taxa$lastmod), use.names = FALSE))
  }
  paste0(
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n",
    "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n",
    paste(lines, collapse = "\n"), "\n",
    "</urlset>\n"
  )
}

#' Write the sitemap for this machine's models on a grid to path.
#'
#' Refuses, rather than writing one search engines would reject, when there
#' are more addresses than one sitemap may hold.
atlas_write_sitemap <- function(path, origin = Sys.getenv("ATLAS_PUBLIC_ORIGIN", unset = ""),
                                grid = "draft", models = atlas_model_index(grid),
                                max = ATLAS_SITEMAP_MAX) {
  taxa <- atlas_sitemap_taxa(models)
  if (nrow(taxa) + length(ATLAS_SITEMAP_PAGES) > max) {
    stop("more than ", max, " addresses: split the sitemap", call. = FALSE)
  }
  xml <- atlas_sitemap_xml(taxa, origin)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp")
  con <- file(tmp, open = "wb")
  writeBin(charToRaw(enc2utf8(xml)), con)
  close(con)
  file.rename(tmp, path)
  message("sitemap: ", nrow(taxa), " taxa with passing maps and ", length(ATLAS_SITEMAP_PAGES),
          " pages, to ", path)
  invisible(taxa)
}
