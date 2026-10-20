# Link-preview cards: the picture Facebook, X, iMessage and Slack show when
# someone shares an Atlas page. 1200 x 630 (1.91:1, Facebook's own shape; X
# trims a few pixels off the top and bottom for 2:1). The brand and the words
# on the left, a map on the right.
#
# A card shows the habitat map alone, never the collections: a preview
# travels further than the page, so it carries the least. The map is the same
# overlay the taxon page lays over its slippy map, on the same Natural Earth
# land as R/mapimage.R.

ATLAS_CARD_WIDTH <- 1200L
ATLAS_CARD_HEIGHT <- 630L
# Where the panel ends and the map begins, as a share of the width.
ATLAS_CARD_SPLIT <- 0.42
ATLAS_CARD_COLOURS <- list(
  panel = "#f6f3ec", ink = "#4a3728", soft = "#7a6a5a", green = "#6f9a2a",
  sea = "#dce8ef", land = "#fbf9f4", rule = "#d8d0c4"
)

#' Wrap text to lines no wider than width (user units of the open plot) at
#' character expansion cex, breaking at spaces; at most max_lines lines, the
#' last cut at a word with an ellipsis.
atlas_card_wrap <- function(text, width, cex, font = 1, max_lines = 3L) {
  words <- strsplit(gsub("\\s+", " ", trimws(text)), " ", fixed = TRUE)[[1]]
  fits <- function(s) graphics::strwidth(s, cex = cex, font = font) <= width
  lines <- character()
  current <- ""
  for (w in words) {
    trial <- if (nzchar(current)) paste(current, w) else w
    if (fits(trial) || !nzchar(current)) {
      current <- trial
    } else {
      lines <- c(lines, current)
      current <- w
    }
  }
  if (nzchar(current)) lines <- c(lines, current)
  if (length(lines) > max_lines) {
    last <- paste(lines[max_lines:length(lines)], collapse = " ")
    while (grepl(" ", last) && !fits(paste0(last, "…"))) last <- sub("\\s+\\S+$", "", last)
    lines <- c(lines[seq_len(max_lines - 1L)], paste0(last, "…"))
  }
  lines
}

#' The line under a species' name on its card.
atlas_card_line <- function(records) {
  records <- suppressWarnings(as.numeric(records %||% NA))
  if (length(records) != 1L || !is.finite(records)) return(character())
  paste0("Likely habitat, modelled from ", format(records, big.mark = ","),
         if (records == 1) " DNA-validated MycoMap record" else " DNA-validated MycoMap records")
}

#' A card's title as big as fits in two lines, down to a floor; past it, three
#' lines, the last cut with an ellipsis. Returns cex and lines. Measured on
#' the open plot, in its units.
atlas_card_title <- function(title, width, font = 2, largest = 2.6, smallest = 1.6) {
  cex <- largest
  lines <- atlas_card_wrap(title, width, cex, font, max_lines = 3L)
  while (cex > smallest && length(lines) > 2) {
    cex <- cex - 0.1
    lines <- atlas_card_wrap(title, width, cex, font, max_lines = 3L)
  }
  list(cex = cex, lines = lines)
}

atlas_card_logo_path <- function() {
  for (p in c(file.path(Sys.getenv("ATLAS_ROOT", "."), "web", "public", "mycomap-logo.png"),
              "/opt/atlas-web/mycomap-logo.png")) {
    if (file.exists(p)) return(p)
  }
  NULL
}

# The MycoMap logo as a raster for rasterImage, read once.
atlas_card_logo <- local({
  logo <- NULL
  function(path = atlas_card_logo_path()) {
    if (is.null(logo) && !is.null(path) && file.exists(path)) {
      img <- terra::rast(path)
      v <- terra::values(img, mat = TRUE)
      alpha <- if (ncol(v) >= 4) v[, 4] else rep(255, nrow(v))
      cols <- grDevices::rgb(v[, 1], v[, 2], v[, 3], alpha, maxColorValue = 255)
      logo <<- list(raster = grDevices::as.raster(matrix(cols, nrow = terra::nrow(img), byrow = TRUE)),
                    aspect = terra::ncol(img) / terra::nrow(img))
    }
    logo
  }
})

#' Draw a link-preview card to a PNG file.
#'
#' title, the big words (a taxon's name, or the site's tagline); italic, for
#' a scientific name; lines, up to three short lines under it; metrics and
#' overlay, the map to show (as for atlas_write_map_image), or NULL for none;
#' caption, a few words in the map's corner saying what it is.
atlas_write_card_image <- function(path, title, italic = FALSE, lines = character(),
                                   metrics = NULL, overlay = NULL, caption = NULL,
                                   site = atlas_site_origin()) {
  k <- ATLAS_CARD_COLOURS
  bounds <- if (!is.null(metrics$bounds)) {
    lapply(metrics$bounds[c("south", "west", "north", "east")], as.numeric)
  } else {
    NULL
  }
  has_map <- !is.null(bounds) && !is.null(overlay) && file.exists(overlay) && !isTRUE(metrics$map_withheld)
  view <- if (has_map) atlas_image_view(NULL, bounds) else list(south = 24, west = -128, north = 54, east = -64)
  lon_0 <- round((view$west + view$east) / 2)
  corners <- atlas_mercator_xy(c(view$west, view$east), c(view$south, view$north), lon_0)

  type <- if (isTRUE(capabilities("cairo"))) "cairo" else getOption("bitmapType")
  grDevices::png(path, width = ATLAS_CARD_WIDTH, height = ATLAS_CARD_HEIGHT, res = 144,
                 type = type, bg = k$panel)
  on.exit(grDevices::dev.off(), add = TRUE)

  # The map, filling the right of the card: the view padded to the panel's
  # shape, with a little room around the map's own edge.
  graphics::par(mar = c(0, 0, 0, 0), plt = c(ATLAS_CARD_SPLIT, 1, 0, 1), xaxs = "i", yaxs = "i")
  graphics::plot.new()
  panel_aspect <- (1 - ATLAS_CARD_SPLIT) * ATLAS_CARD_WIDTH / ATLAS_CARD_HEIGHT
  xr <- range(corners[, "x"])
  yr <- range(corners[, "y"])
  if (diff(xr) / diff(yr) < panel_aspect) {
    xr <- mean(xr) + c(-0.5, 0.5) * diff(yr) * panel_aspect
  } else {
    yr <- mean(yr) + c(-0.5, 0.5) * diff(xr) / panel_aspect
  }
  xr <- mean(xr) + c(-0.5, 0.5) * diff(xr) * 1.06
  yr <- mean(yr) + c(-0.5, 0.5) * diff(yr) * 1.06
  graphics::plot.window(xr, yr, asp = 1)
  usr <- graphics::par("usr")
  graphics::rect(usr[1], usr[3], usr[2], usr[4], col = k$sea, border = NA)
  to_picture <- function(v) terra::project(v, atlas_map_mercator(lon_0))
  countries <- to_picture(atlas_read_boundaries("countries"))
  regions <- to_picture(atlas_read_boundaries("regions"))
  lakes <- to_picture(atlas_read_boundaries("lakes"))
  atlas_draw_polygons(countries, col = k$land, border = NA)
  atlas_draw_polygons(lakes, col = k$sea, border = NA)
  if (has_map) {
    image <- terra::rast(overlay)
    rgba <- terra::values(image, mat = TRUE)
    faint <- !identical(atlas_metrics_grade(metrics), "strong")
    alpha <- rgba[, 4] * ATLAS_IMAGE_OPACITY[[if (faint) "faint" else "standard"]]
    colours <- grDevices::rgb(rgba[, 1], rgba[, 2], rgba[, 3], alpha, maxColorValue = 255)
    raster <- grDevices::as.raster(matrix(colours, nrow = terra::nrow(image), byrow = TRUE))
    at <- atlas_mercator_xy(c(bounds$west, bounds$east), c(bounds$south, bounds$north), lon_0)
    graphics::rasterImage(raster, at[1, "x"], at[1, "y"], at[2, "x"], at[2, "y"], interpolate = TRUE)
  }
  atlas_draw_lines(regions, col = "#a59c8f", lwd = 0.5)
  atlas_draw_lines(countries, col = "#6f6659", lwd = 0.9)

  # The panel, in the whole card's pixels.
  graphics::par(new = TRUE, plt = c(0, 1, 0, 1))
  graphics::plot.new()
  graphics::plot.window(c(0, ATLAS_CARD_WIDTH), c(0, ATLAS_CARD_HEIGHT))
  split <- ATLAS_CARD_SPLIT * ATLAS_CARD_WIDTH
  graphics::rect(0, 0, split, ATLAS_CARD_HEIGHT, col = k$panel, border = NA)
  graphics::segments(split, 0, split, ATLAS_CARD_HEIGHT, col = k$rule, lwd = 1.5)
  left <- 56
  inner <- split - left - 36

  logo <- atlas_card_logo()
  brand_y <- ATLAS_CARD_HEIGHT - 86
  brand_x <- left
  if (!is.null(logo)) {
    h <- 84
    graphics::rasterImage(logo$raster, left, brand_y - h / 2, left + h * logo$aspect, brand_y + h / 2)
    brand_x <- left + h * logo$aspect + 14
  }
  graphics::text(brand_x, brand_y + 4, "MycoMap", adj = c(0, 0), font = 2, cex = 1.55, col = k$ink)
  graphics::text(brand_x + 2, brand_y - 2, "ATLAS", adj = c(0, 1), font = 2, cex = 1.1, col = k$green)

  font <- if (isTRUE(italic)) 4 else 2
  fitted <- atlas_card_title(title, inner, font)
  cex <- fitted$cex
  wrapped <- fitted$lines
  line_h <- graphics::strheight("Mg", cex = cex, font = font) * 1.35
  y <- 410
  for (l in wrapped) {
    graphics::text(left, y, l, adj = c(0, 1), font = font, cex = cex, col = k$ink)
    y <- y - line_h
  }
  y <- y - 16
  for (l in utils::head(lines, 3L)) {
    for (w in atlas_card_wrap(l, inner, 1.05, 1, max_lines = 2L)) {
      graphics::text(left, y, w, adj = c(0, 1), cex = 1.05, col = k$soft)
      y <- y - graphics::strheight("Mg", cex = 1.05) * 1.5
    }
  }

  graphics::text(left, 52, sub("^https?://", "", site), adj = c(0, 0.5), font = 2, cex = 1.1, col = k$green)
  if (!is.null(caption) && nzchar(caption)) {
    graphics::text(ATLAS_CARD_WIDTH - 16, 16, caption, adj = c(1, 0), cex = 0.6, col = k$soft)
  }
  invisible(path)
}

# ---- the tags a link preview reads ------------------------------------------
# A link preview runs no script, so it never sees the tags the app sets for a
# page (web/src/lib/pageMeta.ts). The site's own tags sit in web/index.html;
# a species page's come from here: nginx sends link-preview robots, and only
# them, from /taxa/<name> to /share/taxa/<name> (deploy/lightsail/nginx/
# atlas.conf). People and search engines get the app as before.

# The site's card. web/index.html and web/src/lib/pageMeta.ts carry the same
# words (test-card.R checks the three agree).
ATLAS_SHARE_SITE_TITLE <- "MycoMap Atlas: habitat maps for North America's fungi"
ATLAS_SHARE_SITE_DESCRIPTION <- paste(
  "Where North America's fungi are likely to find habitat, modelled only from",
  "DNA-validated MycoMap records and environmental layers. Open to use and check."
)
ATLAS_SHARE_SITE_IMAGE <- "/og-card.png"
ATLAS_SHARE_SITE_IMAGE_ALT <- paste(
  "MycoMap Atlas: habitat maps for North America's fungi, beside a habitat map",
  "of Trametes ochracea"
)

#' Text made safe inside an HTML attribute or element.
atlas_html_escape <- function(x) {
  x <- gsub("&", "&amp;", as.character(x), fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE)
  x <- gsub("\"", "&quot;", x, fixed = TRUE)
  gsub("'", "&#39;", x, fixed = TRUE)
}

#' The site's own card, for a page with nothing of its own to show.
atlas_share_site <- function(origin = atlas_site_origin()) {
  list(status = 200L, title = ATLAS_SHARE_SITE_TITLE, description = ATLAS_SHARE_SITE_DESCRIPTION,
       url = paste0(origin, "/"), image = paste0(origin, ATLAS_SHARE_SITE_IMAGE),
       image_alt = ATLAS_SHARE_SITE_IMAGE_ALT)
}

#' A species page's card: what a preview of /taxa/<requested> shows.
#'
#' taxa, the pull's taxa table; renames, the recorded renames. A name that
#' has changed is shown, and linked, under the name its records have now. A
#' taxon with a map to show (atlas_best_choice) gets its own picture; one
#' without says why, over the site's picture. Counts only: nothing here is a
#' place.
atlas_taxon_share <- function(requested, taxa, renames = NULL, origin = atlas_site_origin(),
                              grid = "draft") {
  match <- atlas_best_match(requested, taxa$scientific_name, renames)
  if (is.null(match)) {
    out <- atlas_share_site(origin)
    out$status <- 404L
    out$title <- "Page not found — MycoMap Atlas"
    out$description <- "Atlas has no DNA-validated records under this name."
    out$url <- paste0(origin, "/taxa/", utils::URLencode(requested, reserved = TRUE))
    out$noindex <- TRUE
    return(out)
  }
  name <- match$name
  row <- atlas_taxon_row(taxa, name)
  records <- suppressWarnings(as.numeric(row$records %||% NA))
  count <- if (is.finite(records)) {
    paste(format(records, big.mark = ","), if (records == 1) "DNA-validated MycoMap record" else "DNA-validated MycoMap records")
  } else {
    "DNA-validated MycoMap records"
  }
  encoded <- utils::URLencode(name, reserved = TRUE)
  out <- atlas_share_site(origin)
  out$title <- paste(name, "— MycoMap Atlas")
  out$url <- paste0(origin, "/taxa/", encoded)
  choice <- atlas_best_choice(name, grid)
  if (is.null(choice)) {
    out$description <- paste0(name, " on MycoMap Atlas: ", count, ". ",
                              atlas_best_reason(row, name, grid)$text)
    return(out)
  }
  out$description <- paste0("Where ", name, " is likely to find habitat in North America, modelled from ",
                            count, ". Suitable habitat, not sightings.")
  out$image <- sprintf("%s/api/taxa/%s/card.png?v=%s", origin, encoded, unname(tools::md5sum(choice$png)))
  out$image_alt <- paste("Habitat map of", name, "in North America, from MycoMap Atlas")
  out
}

#' The page a link preview reads: its tags, and a line and a link for anyone
#' who opens it. Every value is escaped.
atlas_share_html <- function(share) {
  e <- atlas_html_escape
  meta <- function(attr, key, value) sprintf('    <meta %s="%s" content="%s" />', attr, key, e(value))
  tags <- c(
    meta("name", "description", share$description),
    if (isTRUE(share$noindex)) meta("name", "robots", "noindex"),
    meta("property", "og:type", "website"),
    meta("property", "og:site_name", "MycoMap Atlas"),
    meta("property", "og:title", share$title),
    meta("property", "og:description", share$description),
    meta("property", "og:url", share$url),
    meta("property", "og:image", share$image),
    meta("property", "og:image:width", ATLAS_CARD_WIDTH),
    meta("property", "og:image:height", ATLAS_CARD_HEIGHT),
    meta("property", "og:image:alt", share$image_alt),
    meta("name", "twitter:card", "summary_large_image"),
    meta("name", "twitter:title", share$title),
    meta("name", "twitter:description", share$description),
    meta("name", "twitter:image", share$image),
    meta("name", "twitter:image:alt", share$image_alt)
  )
  paste0(
    "<!DOCTYPE html>\n<html lang=\"en\">\n  <head>\n",
    "    <meta charset=\"UTF-8\" />\n",
    "    <title>", e(share$title), "</title>\n",
    sprintf('    <link rel="canonical" href="%s" />\n', e(share$url)),
    paste(tags, collapse = "\n"), "\n",
    "  </head>\n  <body>\n",
    "    <h1>", e(share$title), "</h1>\n",
    "    <p>", e(share$description), "</p>\n",
    sprintf('    <p><a href="%s">%s</a></p>\n', e(share$url), e(share$url)),
    "  </body>\n</html>\n"
  )
}
