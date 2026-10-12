# The one map to show for a taxon, for apps that show a single map per species
# (Mobile F's "Atlas mode", 2026-10-11): GET /api/taxa/<name>/best-map and the
# whole list at GET /api/maps/best. The shape is fixed by
# inst/api/fixtures/best-map.json, which the tests hold the answers to.
#
# Only a strong map makes a claim (R/map.R, atlas_map_grade), so:
#   - two or more strong maps: their combined map (R/ensemble.R);
#   - one strong map, or two or more whose combined map is missing: the one
#     drawn strongest (map_strength, its margin over the shifted nulls), then
#     the best blocked AUC. Never AUC alone: on the virtual-species test bed it
#     picked the truly best method only 38% of the time (method lane,
#     2026-10-11). No algorithm is preferred, so a 3-19-site taxon's
#     small-model ensemble is its single map when it is strong;
#   - none: nothing, and the answer says why.
# Only grade == "strong" counts (atlas_metrics_grade), never skill: a fit from
# before 2026-10-08 can say skill passed and still be weak.
# Weak maps are left out for now; ATLAS_BEST_MAP_SHOWS_WEAK turns them into a
# faint answer (grade weak, opacity 0.25) if Steve chooses that.
#
# Works from the model JSON and map PNGs alone: the box pulls releases without
# their rasters, so nothing here may need a .tif.

#' Whether a weak map may be the answer when no map is strong (drawn faint).
ATLAS_BEST_MAP_SHOWS_WEAK <- FALSE

#' Why a taxon has no map to show.
ATLAS_BEST_MAP_REASONS <- c("too_few_sites", "no_strong_model", "not_modelled")

#' The fewest independent places any map is fitted from (the small-model
#' ensemble's minimum).
ATLAS_BEST_MAP_MIN_SITES <- 3L

#' Opacity of a strong map at strength 0 and 1, and of a faint one: the site's
#' Map strength defaults (web/src/components/MapStrength.tsx), as fractions.
ATLAS_OPACITY_FAINT <- 0.25
ATLAS_OPACITY_STANDARD <- 0.80

ATLAS_BEST_MAP_LEGEND <- list(
  ramp = list("#f7f7e8", "#94c440", "#2e5a17"),
  low = "Lowest-rated ground",
  high = "Highest-rated ground",
  hatch = "No data like it: conditions unlike any surveyed site"
)

atlas_best_map_attribution <- function(origin = atlas_site_origin()) {
  paste0("Map © MycoMap Atlas, CC BY-SA 4.0. Built on WorldClim 2.1 and the sources at ",
         origin, "/sources")
}

#' A provisional name: a DNA lineage with a code, as web/src/pages/Taxon.tsx
#' isProvisionalName decides it.
atlas_is_provisional_name <- function(name) {
  is.character(name) && length(name) == 1L &&
    grepl("[\"'‘’“”]|\\bsp\\.|-[A-Z]{2,}[0-9]|\\b[A-Z]{2,}[0-9]{2}\\b", name, perl = TRUE)
}

#' A PNG's width and height from its header, or NULL when it is not one.
atlas_png_size <- function(path) {
  if (!file.exists(path)) return(NULL)
  con <- file(path, "rb")
  on.exit(close(con), add = TRUE)
  head <- readBin(con, "raw", 24L)
  signature <- as.raw(c(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a))
  if (length(head) < 24L || !identical(head[1:8], signature)) return(NULL)
  int <- function(bytes) sum(as.numeric(bytes) * 256^(3:0))
  c(width = int(head[17:20]), height = int(head[21:24]))
}

#' Bounds as react-native-maps and most clients want them: longitudes within
#' -180..180. A map drawn past the antimeridian (its west below -180, as maps
#' centred east of 0 are; R/map.R) keeps its shape: its west wraps east of
#' 180, so west > east, and crosses says so.
atlas_wrap_bounds <- function(bounds) {
  num <- function(x) as.numeric(x %||% NA)
  b <- list(south = num(bounds$south), west = num(bounds$west),
            north = num(bounds$north), east = num(bounds$east))
  wrap <- function(lon) ((lon + 180) %% 360) - 180
  crosses <- is.finite(b$west) && is.finite(b$east) && (b$west < -180 || b$east > 180)
  b$west <- round(wrap(b$west), 4)
  b$east <- round(if (is.finite(b$east) && b$east == 180) 180 else wrap(b$east), 4)
  b$south <- round(b$south, 4)
  b$north <- round(b$north, 4)
  list(bounds = b, crosses = crosses)
}

#' A model's skill: blocked AUC, Boyce, and how far its AUC sits above its null
#' models' in null standard deviations.
atlas_model_skill <- function(metrics) {
  num <- function(x) if (is.numeric(x) && length(x) == 1L && is.finite(x)) x else NA_real_
  null <- if (is.list(metrics$null)) metrics$null else list()
  observed <- num(null$observed_auc)
  spread <- num(null$auc_sd)
  z <- if (is.finite(observed) && is.finite(num(null$auc_mean)) && is.finite(spread) && spread > 0) {
    (observed - num(null$auc_mean)) / spread
  } else NA_real_
  list(auc = num(metrics$auc_mean), boyce = num(metrics$boyce %||% metrics$boyce_mean), null_z = z)
}

atlas_opacity <- function(strength, grade) {
  if (!identical(grade, "strong")) return(ATLAS_OPACITY_FAINT)
  s <- if (is.numeric(strength) && length(strength) == 1L && is.finite(strength)) min(1, max(0, strength)) else 1
  round(ATLAS_OPACITY_FAINT + (ATLAS_OPACITY_STANDARD - ATLAS_OPACITY_FAINT) * s, 2)
}

#' The rule itself, on models already read: which map stands for a taxon.
#'
#' models is a list named by algorithm of list(metrics, grade), holding only
#' models that have a map; ensemble is the combined map's JSON, or NULL when
#' it has none. Returns kind, algorithm (NULL for the ensemble), members and,
#' for the ensemble, the members' weights; or NULL. The site reads models
#' from its data directory (atlas_best_choice); the new-find tracker reads
#' them from a past release in the store (R/tracker.R), so the two can never
#' choose differently.
atlas_best_rule <- function(models, ensemble = NULL, show_weak = ATLAS_BEST_MAP_SHOWS_WEAK) {
  strong <- Filter(function(m) identical(m$grade, "strong"), models)

  # The combined map, while two or more of its members are still strong.
  if (is.list(ensemble) && !is.null(ensemble$bounds)) {
    members <- Filter(function(m) is.list(m) && m$algorithm %in% names(strong), ensemble$members %||% list())
    if (length(members) >= 2L) {
      weights <- vapply(members, function(m) as.numeric(m$weight %||% 0), numeric(1))
      if (sum(weights) <= 0) weights <- rep(1, length(members))
      return(list(kind = "ensemble", algorithm = NULL,
                  members = vapply(members, function(m) m$algorithm, character(1)),
                  weights = weights, grade = "strong"))
    }
  }

  pick <- function(candidates) {
    if (!length(candidates)) return(NULL)
    finite <- function(x) { x[!is.finite(x)] <- -Inf; x }
    strength <- finite(vapply(candidates, function(m) as.numeric(m$metrics$map_strength %||% NA), numeric(1)))
    auc <- finite(vapply(candidates, function(m) atlas_model_skill(m$metrics)$auc, numeric(1)))
    best <- order(-strength, -auc, names(candidates))[[1]]
    list(kind = "model", algorithm = names(candidates)[[best]], members = names(candidates)[[best]],
         grade = candidates[[best]]$grade)
  }
  chosen <- pick(strong)
  if (is.null(chosen) && isTRUE(show_weak)) {
    chosen <- pick(Filter(function(m) identical(m$grade, "weak"), models))
  }
  chosen
}

#' The map to show for a taxon, or NULL. The rule is atlas_best_rule.
#'
#' Returns kind ("ensemble" or "model"), algorithm (NULL for the ensemble),
#' members, grade, skill, the PNG's path, its bounds and its map strength.
atlas_best_choice <- function(name, grid = "draft", show_weak = ATLAS_BEST_MAP_SHOWS_WEAK) {
  models <- list()
  for (algorithm in names(ATLAS_ALGORITHMS)) {
    metrics <- atlas_read_metrics(name, grid, algorithm)
    png <- atlas_model_path(name, grid, ".png", algorithm)
    if (is.null(metrics) || !file.exists(png) || is.null(metrics$bounds)) next
    models[[algorithm]] <- list(metrics = metrics, png = png, grade = atlas_metrics_grade(metrics))
  }
  json <- atlas_ensemble_path(name, grid, ".json")
  png <- atlas_ensemble_path(name, grid, ".png")
  ensemble <- if (file.exists(json) && file.exists(png)) {
    tryCatch(jsonlite::fromJSON(json, simplifyVector = FALSE), error = function(e) NULL)
  }
  rule <- atlas_best_rule(models, ensemble, show_weak)
  if (is.null(rule)) return(NULL)

  if (identical(rule$kind, "ensemble")) {
    weights <- rule$weights
    skills <- lapply(rule$members, function(a) atlas_model_skill(models[[a]]$metrics))
    mean_of <- function(field) {
      v <- vapply(skills, function(s) s[[field]], numeric(1))
      ok <- is.finite(v)
      if (any(ok)) sum(v[ok] * weights[ok]) / sum(weights[ok]) else NA_real_
    }
    zs <- vapply(skills, function(s) s$null_z, numeric(1))
    return(list(
      kind = "ensemble", algorithm = NULL, members = rule$members, grade = "strong",
      skill = list(auc = mean_of("auc"), boyce = mean_of("boyce"),
                   null_z = if (any(is.finite(zs))) min(zs[is.finite(zs)]) else NA_real_),
      png = png, bounds = ensemble$bounds, strength = as.numeric(ensemble$map_strength %||% NA)
    ))
  }
  m <- models[[rule$algorithm]]
  list(kind = "model", algorithm = rule$algorithm, members = rule$members,
       grade = m$grade, skill = atlas_model_skill(m$metrics), png = m$png,
       bounds = m$metrics$bounds, strength = as.numeric(m$metrics$map_strength %||% NA))
}

#' Why a taxon has nothing to show: too_few_sites, no_strong_model or
#' not_modelled, with a sentence a visitor can read.
atlas_best_reason <- function(row, name, grid = "draft") {
  if (is.null(row)) {
    return(list(reason = "not_modelled", text = "Atlas has no DNA-validated records under this name."))
  }
  localities <- suppressWarnings(as.integer(row$localities %||% NA))
  fitted <- any(vapply(names(ATLAS_ALGORITHMS), function(a) {
    file.exists(atlas_model_path(name, grid, ".json", a))
  }, logical(1)))
  if (!fitted && is.finite(localities) && localities < ATLAS_BEST_MAP_MIN_SITES) {
    places <- if (localities == 1L) "place" else "places"
    return(list(reason = "too_few_sites",
                text = sprintf("Found at %d independent %s so far; a first map needs %d.",
                               localities, places, ATLAS_BEST_MAP_MIN_SITES)))
  }
  if (fitted) {
    return(list(reason = "no_strong_model",
                text = paste("None of its maps has yet shown it beats clustered collecting,",
                             "so there is no map to make a claim with.")))
  }
  list(reason = "not_modelled", text = "Enough records for a first map, but it has not been fitted yet.")
}

#' Which taxon a request means, and how it was matched: exact, spelling (case
#' and punctuation), folded (author citations and rank words, as a pull
#' merges names), renamed, or NULL.
atlas_best_match <- function(requested, names, renames = NULL) {
  direct <- atlas_resolve_name(requested, names, NULL)
  if (!is.null(direct)) {
    return(list(name = direct$name, how = if (identical(direct$how, "current")) "exact" else "spelling"))
  }
  if (is.character(requested) && length(requested) == 1L && nzchar(requested)) {
    hit <- names[atlas_name_key(names) == atlas_name_key(requested)]
    if (length(hit) == 1L) return(list(name = hit, how = "folded"))
  }
  renamed <- atlas_resolve_name(requested, names, renames)
  if (!is.null(renamed)) return(list(name = renamed$name, how = "renamed"))
  NULL
}

atlas_best_release <- function(grid = "draft") {
  release <- atlas_status_release(grid)
  list(id = release$id %||% NULL, built_at = release$createdAt %||% NULL)
}

#' The overlay a chosen map is shown with: its versioned URL, wrapped bounds,
#' pixel size and opacity. The version is the PNG's md5, so it changes exactly
#' when the picture is redrawn.
atlas_best_overlay <- function(name, choice, origin = atlas_site_origin()) {
  version <- unname(tools::md5sum(choice$png))
  size <- atlas_png_size(choice$png)
  encoded <- utils::URLencode(name, reserved = TRUE)
  url <- if (identical(choice$kind, "ensemble")) {
    sprintf("%s/api/taxa/%s/ensemble.png?v=%s", origin, encoded, version)
  } else {
    sprintf("%s/api/taxa/%s/map.png?algorithm=%s&v=%s", origin, encoded, choice$algorithm, version)
  }
  wrapped <- atlas_wrap_bounds(choice$bounds)
  # Where the combined map's members disagree, for an app that offers it.
  disagreement <- sub("[.]png$", ".disagreement.png", choice$png)
  disagreement_url <- if (identical(choice$kind, "ensemble") && file.exists(disagreement)) {
    sprintf("%s/api/taxa/%s/ensemble.png?layer=disagreement&v=%s", origin, encoded,
            unname(tools::md5sum(disagreement)))
  }
  list(url = url, disagreement_url = disagreement_url, bounds = wrapped$bounds,
       crosses_antimeridian = wrapped$crosses,
       width = if (is.null(size)) NA_integer_ else as.integer(size[["width"]]),
       height = if (is.null(size)) NA_integer_ else as.integer(size[["height"]]),
       opacity = atlas_opacity(choice$strength, choice$grade))
}

atlas_best_caption <- function(name, grade) {
  parts <- c(sprintf("Suitable habitat for %s, ranked within its own range.", name),
             "Suitable habitat, not a sighting; not for foraging.",
             atlas_grade_note(grade),
             if (atlas_is_provisional_name(name)) {
               "A provisional name: a DNA lineage without a published species name yet."
             })
  paste(parts, collapse = " ")
}

#' The whole answer to GET /api/taxa/<name>/best-map.
#'
#' taxa is the pull's per-taxon table (scientific_name, localities, ...);
#' renames the renames table. Never holds a coordinate or a record: only a
#' map's bounds, which its PNG covers anyway.
atlas_best_map_answer <- function(requested, taxa, renames = NULL, grid = "draft",
                                  origin = atlas_site_origin(), show_weak = ATLAS_BEST_MAP_SHOWS_WEAK) {
  names <- if (is.data.frame(taxa)) taxa$scientific_name else character()
  match <- atlas_best_match(requested, names, renames)
  name <- match$name %||% NULL
  row <- if (!is.null(name)) atlas_taxon_row(taxa, name) else NULL
  choice <- if (!is.null(name)) atlas_best_choice(name, grid, show_weak) else NULL
  why <- if (is.null(choice)) atlas_best_reason(row, name %||% "", grid)
  label <- function(choice) {
    if (identical(choice$kind, "ensemble")) "All passing models together" else ATLAS_ALGORITHMS[[choice$algorithm]]$label
  }
  reason_why <- function(choice) {
    if (identical(choice$kind, "ensemble")) {
      "Two or more of its maps beat clustered collecting, so this is their combined map."
    } else if (identical(choice$grade, "strong")) {
      "One of its maps beat clustered collecting: the one with the best skill on held-out ground."
    } else {
      "None of its maps beat clustered collecting; this is the one with the best skill on held-out ground, shown faint."
    }
  }
  round_or_null <- function(x, digits) if (is.finite(x)) round(x, digits) else NULL
  list(
    requested = requested,
    taxon = name,
    matched_by = match$how %||% NULL,
    release = atlas_best_release(grid),
    available = !is.null(choice),
    reason = why$reason %||% NULL,
    reason_text = why$text %||% NULL,
    choice = if (!is.null(choice)) list(
      kind = choice$kind, algorithm = choice$algorithm, members = as.list(choice$members),
      grade = choice$grade, why = reason_why(choice), label = label(choice),
      skill = list(auc = round_or_null(choice$skill$auc, 3), boyce = round_or_null(choice$skill$boyce, 3),
                   null_z = round_or_null(choice$skill$null_z, 2))
    ),
    overlay = if (!is.null(choice)) atlas_best_overlay(name, choice, origin),
    legend = if (!is.null(choice)) ATLAS_BEST_MAP_LEGEND,
    caption = if (!is.null(choice)) atlas_best_caption(name, choice$grade),
    provisional = !is.null(name) && atlas_is_provisional_name(name),
    page_url = if (!is.null(name)) sprintf("%s/taxa/%s", origin, utils::URLencode(name, reserved = TRUE)),
    # The 0.1 degree collection cells, offered whether or not there is a map.
    cells_url = if (!is.null(name)) sprintf("%s/api/taxa/%s/cells", origin, utils::URLencode(name, reserved = TRUE)),
    attribution = atlas_best_map_attribution(origin),
    license_url = ATLAS_MAP_LICENSE_URL
  )
}

#' The whole answer to GET /api/maps/best: every taxon with a map to show,
#' once per release. models is atlas_model_index's table (taxon, presences).
atlas_best_maps <- function(models, grid = "draft", origin = atlas_site_origin(),
                            show_weak = ATLAS_BEST_MAP_SHOWS_WEAK) {
  taxa <- if (is.data.frame(models) && nrow(models)) sort(unique(models$taxon)) else character()
  presences <- if (is.data.frame(models) && nrow(models)) tapply(models$presences, models$taxon, max, na.rm = TRUE) else NULL
  items <- list()
  for (name in taxa) {
    choice <- atlas_best_choice(name, grid, show_weak)
    if (is.null(choice)) next
    overlay <- atlas_best_overlay(name, choice, origin)
    p <- if (!is.null(presences)) suppressWarnings(as.integer(presences[[name]])) else NA_integer_
    items[[length(items) + 1L]] <- c(
      list(taxon = name, kind = choice$kind, algorithm = choice$algorithm, grade = choice$grade,
           presences = if (is.finite(p)) p else NULL, provisional = atlas_is_provisional_name(name)),
      overlay
    )
  }
  list(release = atlas_best_release(grid), grading = ATLAS_NULL_DESIGN, count = length(items),
       legend = ATLAS_BEST_MAP_LEGEND, attribution = atlas_best_map_attribution(origin),
       license_url = ATLAS_MAP_LICENSE_URL, items = items)
}
