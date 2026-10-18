# The new-find tracker: how the maps stand up to records validated after them.
#
# Every day, records whose first green validation falls on that day are
# scored against the map that was live when the day began (Steve,
# 2026-10-12). Atlas trains on green records only, so a record first green on
# day D cannot have trained the release live at the start of D: its pull was
# taken before D. Mostly, then, a find tests the map on ground it had not seen.
#
# A find is a row of the newest pull with a first_green_on date (R/firstgreen.R):
# the pull's own eligibility, place, name and DNA-naming rules have already
# chosen it, and nothing is asked of mycomap.org again. It is scored under the
# naming of the release it is scored against: a release fitted on record names
# (before the sequence-name rule) by the record's own name, a later one by its
# DNA name (R/labels.R). Spellings fold and renames resolve as they do for a
# visitor's search (atlas_best_match).
#
# What a find is scored on is the release's own stored model rasters, read
# from the store, ranked the way the drawn map is (atlas_map_layers): ground
# inside the area of applicability, ranked from 0 to 1, so a find's rank is
# the share of the map's ground it beats. A strong taxon is scored on the map
# an app shows for it (atlas_best_rule); any other taxon on the mean rank of
# its models that hold the cell inside their area. A find in ground no model
# applies to is "outside the area of applicability"; in ground beyond every
# model's 500 km reach, "beyond reach". Neither is given a rank.
#
# Finds cluster where people already collect, so a find beside a known site
# mostly tests the map's memory. Each find also says whether it is a new site
# for its taxon (over ATLAS_SITE_KM from every record of the taxon in that
# release's pull), whether its 5 km cell held any record at all (new area),
# and how far it is from the nearest known site. And the uniform chance line
# (50% of finds in the top half) is joined by an effort-corrected one: the
# taxon's map is read at the cells of every other taxon's finds in the same
# window, which is where people were looking (method lane, 2026-10-12).
#
# Privacy. A record id leads straight to the record's coordinates, so the
# per-find ledger is PRIVATE, like the trained-ids lists (R/trained.R): it is
# kept under the store's private/ prefix and the box's data/private/, and
# never reaches a release, the API, Zenodo, the repository or the sitemap.
# What is published is counts and shares, with small counts withheld. The
# ledger holds no coordinates either, only the record's model-grid cell.
#
# The tracker reads releases and pulls and writes only its own files. It is
# in no fingerprint and no fit setting, and a failed run only warns.
#
#   private/tracker/<grid>/ledger.tsv.gz   one row per find           PRIVATE
#   private/tracker/<grid>/runs.tsv.gz     each run, and the live release
#   tracker/<grid>/summary.json            the published aggregates

# The first day finds are counted from: the first day release
# 20261002T041943Z (promoted 2026-10-02 04:19 UTC) was live from the start.
ATLAS_TRACKER_SINCE <- "2026-10-03"

ATLAS_TRACKER_PRIVATE_PREFIX <- "private/tracker"
ATLAS_TRACKER_PUBLIC_PREFIX <- "tracker"

# A private side column of the pull, when .org records it: how each verdict
# came about (validation_priority_events on .org): organic (a validator's own
# choice, and anything unknown), triage (the triage card), priority_sort (the
# priority-sorted list) or auto (validated automatically). Empty today;
# plumbed like first_green_on, outside every fingerprint, and never published
# per record. Organic and empty finds are evaluated; every other channel is a
# population of its own (steered towards new ground, or chosen by no one), so
# each is held out of the evaluation and counted in its own row. A value .org
# adds later is held out too, as "other", until it is named here.
ATLAS_TRACKER_CHANNEL_FIELD <- "channel"
ATLAS_TRACKER_EVALUATED_CHANNELS <- c("organic")
ATLAS_TRACKER_HELD_CHANNELS <- c("triage", "priority_sort", "auto")

# Per-taxon tallies below this many finds say "fewer than 5" and no more.
ATLAS_TRACKER_MIN_TAXON <- 5L
# A pooled share is shown from this many ranked places, Boyce from the next.
ATLAS_TRACKER_MIN_SHARE <- 30L
ATLAS_TRACKER_MIN_BOYCE <- 50L
# Distance bands to the nearest known site of the taxon, in km.
ATLAS_TRACKER_BANDS_KM <- c(100, 500)

# A find's outcome, in the ledger.
ATLAS_TRACKER_STATUSES <- c(
  scored = "scored against the release's maps",
  no_map = "its taxon is in the release without a map",
  not_in_release = "its name is not in the release",
  in_release_pull = "already in the release's pull (never scored)",
  no_release = "no release was live at the start of its day"
)

ATLAS_TRACKER_LEDGER_FIELDS <- c(
  "key", "source", "observation_id", "first_green_on", "observed_on",
  "pulled_name", "pulled_naming", "channel", "taxon", "matched_by",
  "release", "release_promoted_at", "scheme", "naming", "status", "grade",
  "kind", "rank", "place", "aoa",
  paste0("rank_", names(ATLAS_ALGORITHMS)), paste0("place_", names(ATLAS_ALGORITHMS)),
  "nearest_km", "band", "new_site", "new_area", "cell", "map_version",
  "scored_at", "retracted_on", "retracted_why"
)

# ---- where things live -----------------------------------------------------

atlas_tracker_key <- function(grid = "draft", file = "ledger.tsv.gz") {
  paste0(ATLAS_TRACKER_PRIVATE_PREFIX, "/", grid, "/", file)
}

atlas_tracker_summary_key <- function(grid = "draft") {
  paste0(ATLAS_TRACKER_PUBLIC_PREFIX, "/", grid, "/summary.json")
}

atlas_tracker_local <- function(grid = "draft", file = "ledger.tsv.gz") {
  atlas_path("private", "tracker", grid, file)
}

#' The published aggregates on this machine: what GET /api/tracker serves.
atlas_tracker_summary_path <- function(grid = "draft") {
  atlas_path("tracker", grid, "summary.json")
}

#' Where fetched releases, pulls and rasters are kept by hash. ATLAS_TRACKER_CACHE
#' moves it, so a dry run can work with the data directory mounted read-only.
atlas_tracker_cache_dir <- function() {
  explicit <- Sys.getenv("ATLAS_TRACKER_CACHE", unset = "")
  if (nzchar(explicit)) explicit else atlas_path("private", "tracker", "cache")
}

atlas_tracker_promotions_file <- function(grid = "draft", root = Sys.getenv("ATLAS_ROOT", unset = ".")) {
  name <- paste0("promotions-", grid, ".json")
  path <- file.path(root, "inst", "tracker", name)
  if (!file.exists(path)) path <- system.file("tracker", name, package = "mycomapatlas")
  path
}

# ---- tables ----------------------------------------------------------------

atlas_tracker_empty_ledger <- function() {
  out <- as.data.frame(matrix(character(), nrow = 0, ncol = length(ATLAS_TRACKER_LEDGER_FIELDS)),
                       stringsAsFactors = FALSE)
  names(out) <- ATLAS_TRACKER_LEDGER_FIELDS
  atlas_tracker_types(out)
}

#' Columns as their types: the ledger is written as text.
atlas_tracker_types <- function(ledger) {
  for (f in setdiff(ATLAS_TRACKER_LEDGER_FIELDS, names(ledger))) ledger[[f]] <- rep(NA, nrow(ledger))
  numeric_fields <- c("rank", paste0("rank_", names(ATLAS_ALGORITHMS)), "nearest_km", "cell")
  logical_fields <- c("new_site", "new_area")
  for (f in ATLAS_TRACKER_LEDGER_FIELDS) {
    v <- ledger[[f]]
    ledger[[f]] <- if (f %in% numeric_fields) {
      suppressWarnings(as.numeric(v))
    } else if (f %in% logical_fields) {
      if (is.logical(v)) v else as.logical(toupper(as.character(v)))
    } else {
      as.character(v)
    }
  }
  ledger[, ATLAS_TRACKER_LEDGER_FIELDS, drop = FALSE]
}

atlas_tracker_read_table <- function(path) {
  if (is.null(path) || !file.exists(path)) return(NULL)
  utils::read.delim(gzfile(path, encoding = "UTF-8"), sep = "\t", quote = "", comment.char = "",
                    colClasses = "character", na.strings = "", check.names = FALSE,
                    stringsAsFactors = FALSE, encoding = "UTF-8")
}

#' A private table: the store's copy when there is a store (a data directory
#' is replaced whole at a release cutover, the store is not), else this
#' machine's.
atlas_tracker_load <- function(store, grid, file) {
  local <- atlas_tracker_local(grid, file)
  if (!is.null(store) && store$exists(atlas_tracker_key(grid, file))) {
    dir.create(dirname(local), recursive = TRUE, showWarnings = FALSE)
    store$get(atlas_tracker_key(grid, file), local)
  }
  atlas_tracker_read_table(local)
}

atlas_tracker_save <- function(store, grid, file, table) {
  local <- atlas_tracker_local(grid, file)
  atlas_write_tsv_gz(table, local)
  if (!is.null(store)) store$put(atlas_tracker_key(grid, file), local)
  invisible(local)
}

# ---- which release was live ------------------------------------------------

#' Every promotion known, oldest first: release, promoted_at. From the frozen
#' history (inst/tracker), the write-once promotion records the store keeps
#' from the rebuild on (atlas_promotion_history), the live pointer, and what each run of the tracker saw.
atlas_tracker_promotions <- function(store = NULL, grid = "draft", runs = NULL,
                                     frozen = atlas_tracker_promotions_file(grid)) {
  rows <- list()
  add <- function(release, at) {
    ok <- is.character(release) & nzchar(release) & !is.na(release) & is.character(at) & !is.na(at)
    if (any(ok)) rows[[length(rows) + 1L]] <<- data.frame(release = release[ok], promoted_at = at[ok],
                                                          stringsAsFactors = FALSE)
  }
  if (length(frozen) == 1L && nzchar(frozen) && file.exists(frozen)) {
    known <- jsonlite::fromJSON(frozen, simplifyVector = TRUE)$promotions
    if (is.data.frame(known)) add(known$release, known$promoted_at)
  }
  if (!is.null(store)) {
    # The write-once record every promotion leaves (atlas_promote_release).
    history <- tryCatch(atlas_promotion_history(store, grid), error = function(e) NULL)
    if (is.data.frame(history) && nrow(history)) add(history$release, history$promoted_at)
    pointer <- paste0("current/", grid, ".json")
    if (store$exists(pointer)) {
      record <- atlas_store_text(store, pointer)
      add(as.character(record$release %||% NA), as.character(record$promoted_at %||% NA))
    }
  }
  if (is.data.frame(runs) && nrow(runs)) add(runs$current_release, runs$current_promoted_at)
  if (!length(rows)) return(data.frame(release = character(), promoted_at = character()))
  out <- unique(do.call(rbind, rows))
  out <- out[order(out$promoted_at, out$release), , drop = FALSE]
  rownames(out) <- NULL
  out
}

#' The start of a day, as an ISO time in UTC.
atlas_tracker_day_start <- function(day) {
  # paste0 would turn no days into one: a run with no new finds must have none.
  if (!length(day)) return(character())
  paste0(as.character(day), "T00:00:00Z")
}

#' The release live when a day began, or NA: the last promotion before it.
atlas_tracker_live_at <- function(days, promotions) {
  starts <- atlas_tracker_day_start(days)
  vapply(starts, function(start) {
    before <- promotions$release[promotions$promoted_at < start]
    if (length(before)) before[[length(before)]] else NA_character_
  }, character(1), USE.NAMES = FALSE)
}

# ---- a release, read from the store ----------------------------------------

#' A stored object on this machine, fetched once and kept by its hash.
atlas_tracker_object <- function(store, sha, ext = "", cache = atlas_tracker_cache_dir()) {
  path <- file.path(cache, "objects", substr(sha, 1, 2), paste0(sha, ext))
  if (!file.exists(path)) {
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    part <- paste0(path, ".part")
    store$get(atlas_object_key(sha), part)
    if (!identical(atlas_sha256(part), sha)) {
      unlink(part)
      stop("the store's object ", sha, " does not match its hash", call. = FALSE)
    }
    file.rename(part, path)
  }
  path
}

atlas_tracker_manifest <- function(store, id, grid, cache = atlas_tracker_cache_dir()) {
  path <- file.path(cache, "releases", grid, paste0(id, ".json"))
  if (!file.exists(path)) {
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    key <- paste0("releases/", grid, "/", id, ".json")
    # A private release (R/hindcast.R) is read from where it is kept, so the
    # paper's scoring reads it as it reads a release; it is never listed,
    # promoted or served.
    private <- atlas_benchmark_key(id, "release.json")
    if (!store$exists(key) && store$exists(private)) key <- private
    store$get(key, path)
  }
  jsonlite::fromJSON(path, simplifyVector = FALSE)
}

#' The pull a release was planned from: its job's private input in the store.
atlas_tracker_release_pull <- function(store, manifest, grid, cache = atlas_tracker_cache_dir()) {
  atlas_read_occurrences(atlas_tracker_release_pull_file(store, manifest, grid, cache))
}

#' The local copy of a release's pull, fetched once and kept by hash.
atlas_tracker_release_pull_file <- function(store, manifest, grid, cache = atlas_tracker_cache_dir()) {
  job <- atlas_json_string(manifest$job)
  if (is.null(job)) stop("release ", manifest$id, " names no job, so its pull is unknown", call. = FALSE)
  path <- file.path(cache, "jobs", grid, paste0(job, ".json"))
  if (!file.exists(path)) {
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    store$get(paste0("jobs/", grid, "/", job, "/job.json"), path)
  }
  inputs <- jsonlite::fromJSON(path, simplifyVector = FALSE)$inputs %||% list()
  pull <- Filter(function(e) grepl("^occurrences/occurrences-.*[.]tsv[.]gz$", e$path %||% ""), inputs)
  if (length(pull) != 1L) stop("job ", job, " lists no single pull", call. = FALSE)
  atlas_tracker_object(store, pull[[1]]$sha256, ".tsv.gz", cache)
}

#' Model-grid coordinates and cell of points: the cell the release's rasters
#' share (they are all on one grid).
atlas_tracker_place <- function(lat, lng, grid = "draft") {
  lat <- suppressWarnings(as.numeric(lat))
  lng <- suppressWarnings(as.numeric(lng))
  xy <- atlas_albers(lat, lng)
  cell <- atlas_here_cell(xy[, "x"], xy[, "y"], atlas_resolution(grid) / 1000)
  data.frame(lat = lat, lng = lng, x = xy[, "x"], y = xy[, "y"], cell = cell)
}

#' A cell's centre on the model grid.
atlas_tracker_cell_xy <- function(cell, grid = "draft") {
  size <- atlas_resolution(grid)
  ncol <- ceiling((ATLAS_GRID_EXTENT[["xmax"]] - ATLAS_GRID_EXTENT[["xmin"]]) / size)
  row <- (cell - 1) %/% ncol
  col <- (cell - 1) %% ncol
  cbind(x = ATLAS_GRID_EXTENT[["xmin"]] + (col + 0.5) * size,
        y = ATLAS_GRID_EXTENT[["ymax"]] - (row + 0.5) * size)
}

#' Everything about one release that scoring needs, read once per run.
#' With pull = FALSE the view holds the release's maps and index but not its
#' records: enough for the summary's per-taxon tallies, at a fraction of the
#' memory.
atlas_tracker_view <- function(store, id, grid = "draft", cache = atlas_tracker_cache_dir(), pull = TRUE) {
  manifest <- atlas_tracker_manifest(store, id, grid, cache)
  files <- manifest$files %||% list()
  shas <- stats::setNames(vapply(files, function(f) f$sha256, ""), vapply(files, function(f) f$path, ""))
  entries <- Filter(function(e) !isTRUE(e$refused), manifest$index %||% list())
  pull_file <- atlas_tracker_release_pull_file(store, manifest, grid, cache)
  columns <- strsplit(readLines(gzfile(pull_file), n = 1L, warn = FALSE), "\t")[[1]]
  pull <- if (isTRUE(pull)) {
    atlas_read_occurrences(pull_file)
  } else {
    data.frame(source = character(), observation_id = character(), scientific_name = character(),
               latitude = character(), longitude = character(), stringsAsFactors = FALSE)
  }
  placed <- atlas_tracker_place(pull$latitude, pull$longitude, grid)
  renames <- if (!is.na(shas["occurrences/renames.json"])) {
    atlas_read_renames(atlas_tracker_object(store, shas[["occurrences/renames.json"]], ".json", cache))
  }
  index_taxa <- vapply(entries, function(e) e$taxon, "")
  view <- new.env(parent = emptyenv())
  view$id <- id
  view$grid <- grid
  view$store <- store
  view$cache <- cache
  view$shas <- shas
  view$entries <- entries
  # Its other fields (id, job, previous, purpose, validated_through, ...) for
  # the studies that read a release through this view (R/study*.R) and for
  # atlas_tracker_release_pull. Its files and index, the bulk, are held above
  # as shas and entries.
  view$manifest <- manifest[setdiff(names(manifest), c("files", "index"))]
  view$pulled_at <- as.character(manifest$pull$pulled_at %||% NA)
  # Shifted-null grades are recorded in a release's index from the rebuild
  # on; before, the index says only whether a map passed (skill).
  view$scheme <- if (any(vapply(entries, function(e) !is.null(e$grade), logical(1)))) "shift" else "skill"
  # A pull named by the DNA keeps each record's own name beside it.
  view$naming <- if ("record_name" %in% columns) "sequence" else "record"
  view$pull <- data.frame(key = paste(pull$source, pull$observation_id, sep = ":"),
                          taxon = pull$scientific_name, lat = placed$lat, lng = placed$lng,
                          cell = placed$cell, stringsAsFactors = FALSE)
  view$cells <- unique(placed$cell[!is.na(placed$cell)])
  view$names <- sort(unique(c(pull$scientific_name, index_taxa)))
  view$modelled <- unique(index_taxa)
  view$renames <- renames
  view
}

atlas_tracker_file <- function(view, path, ext) {
  sha <- view$shas[path]
  if (is.na(sha)) return(NULL)
  atlas_tracker_object(view$store, sha[[1]], ext, view$cache)
}

#' One drawn map's layers: rank (inside the area of applicability), whether
#' the cell has a value, and the grid to find cells on: the raster's geometry
#' only, without its values, so a map costs its two vectors and no more.
atlas_tracker_layers <- function(suitability, dissimilarity = NULL, threshold = NULL) {
  layers <- atlas_map_layers(suitability, dissimilarity, threshold)
  list(raster = terra::rast(suitability, nlyrs = 1),
       rank = terra::values(layers[["rank"]], mat = FALSE),
       outside = terra::values(layers[["outside"]], mat = FALSE))
}

#' The version of what a taxon's maps draw in a release, from the manifest
#' alone: each model's raster and applicability layer by hash, its grade, and
#' the combined map. A map redrawn without a refit (a refinish) is a new
#' version, so its tally starts again. NULL when the taxon has no map there.
atlas_tracker_version <- function(view, taxon) {
  parts <- character()
  for (entry in Filter(function(e) identical(e$taxon, taxon), view$entries)) {
    paths <- atlas_model_relpaths(taxon, view$grid, entry$algorithm, c(".tif", ".di.tif"))
    if (is.na(view$shas[paths[[1]]])) next
    parts <- c(parts, paste(entry$algorithm, view$shas[[paths[[1]]]], view$shas[paths[[2]]] %|NA|% "",
                            entry$grade %||% entry$skill %||% ""))
  }
  if (!length(parts)) return(NULL)
  slug <- gsub("(^-|-$)", "", gsub("[^a-z0-9]+", "-", tolower(taxon)))
  parts <- c(parts, paste("ensemble", view$shas[file.path("models", view$grid, "ensemble", paste0(slug, ".tif"))] %|NA|% ""))
  substr(digest::digest(sort(parts), algo = "sha256"), 1, 16)
}

#' A taxon's maps in a release: each model's layers, the grades, and the map
#' that stands for it; list(none = TRUE) when it has no map in the release.
#' Only the last taxon asked for is kept: a taxon's maps run to tens of MB,
#' and a backfill scores hundreds of taxa on a box with 1 GB to spare
#' (2026-10-14: keeping them all was killed for memory).
#'
#' With at, a two-column matrix of grid coordinates, each model is read,
#' looked up at those points and let go before the next: the answer holds the
#' lookups (hit) and no raster, so a taxon costs one model's grid at a time.
#' That is how a run scores (atlas_tracker_rank_window); nothing is kept on
#' the view.
atlas_tracker_maps <- function(view, taxon, at = NULL) {
  if (is.null(at) && identical(view$last_taxon, taxon)) return(view$last_maps)
  if (is.null(at)) {
    view$last_taxon <- NULL
    view$last_maps <- NULL
  }
  invisible(gc(FALSE))
  grid <- view$grid
  models <- list()
  for (entry in Filter(function(e) identical(e$taxon, taxon), view$entries)) {
    algorithm <- entry$algorithm
    paths <- atlas_model_relpaths(taxon, grid, algorithm, c(".json", ".tif", ".di.tif"))
    json <- atlas_tracker_file(view, paths[[1]], ".json")
    tif <- atlas_tracker_file(view, paths[[2]], ".tif")
    if (is.null(json) || is.null(tif)) next
    metrics <- jsonlite::fromJSON(json, simplifyVector = FALSE)
    di <- atlas_tracker_file(view, paths[[3]], ".tif")
    threshold <- suppressWarnings(as.numeric(metrics$applicability$threshold %||% NA))
    aoa <- !is.null(di) && length(threshold) == 1L && is.finite(threshold)
    layers <- if (is.null(at)) {
      atlas_tracker_layers(terra::rast(tif), if (aoa) terra::rast(di), if (aoa) threshold)
    } else {
      list(hit = atlas_tracker_rank_points(terra::rast(tif), at[, 1], at[, 2],
                                           if (aoa) terra::rast(di), if (aoa) threshold))
    }
    if (!is.null(at)) invisible(gc(FALSE))
    models[[algorithm]] <- c(layers, list(metrics = metrics, aoa = aoa,
                                          grade = atlas_metrics_grade(metrics),
                                          skill = if (is.character(metrics$skill)) metrics$skill else "untested"))
  }
  if (!length(models)) {
    if (!is.null(at)) return(list(none = TRUE))
    view$last_taxon <- taxon
    view$last_maps <- list(none = TRUE)
    return(view$last_maps)
  }
  grade <- if (identical(view$scheme, "shift")) {
    atlas_tracker_best_of(vapply(models, `[[`, "", "grade"), c("strong", "weak", "failed", "untested"))
  } else {
    atlas_tracker_best_of(vapply(models, `[[`, "", "skill"), c("passed", "failed", "untested"))
  }
  # The map an app shows, for a strong taxon; drawable models only, as there.
  choice <- NULL
  ensemble <- NULL
  if (identical(view$scheme, "shift")) {
    drawable <- Filter(function(m) !is.null(m$metrics$bounds), models)
    slug <- gsub("(^-|-$)", "", gsub("[^a-z0-9]+", "-", tolower(taxon)))
    ens_json <- atlas_tracker_file(view, file.path("models", grid, "ensemble", paste0(slug, ".json")), ".json")
    ens_meta <- if (!is.null(ens_json)) tryCatch(jsonlite::fromJSON(ens_json, simplifyVector = FALSE), error = function(e) NULL)
    choice <- atlas_best_rule(drawable, ens_meta, show_weak = FALSE)
    if (identical(choice$kind, "ensemble")) {
      ens_tif <- atlas_tracker_file(view, file.path("models", grid, "ensemble", paste0(slug, ".tif")), ".tif")
      if (is.null(ens_tif)) {
        # A release that lists the combined map's JSON without its raster:
        # score on the best single strong map instead.
        choice <- atlas_best_rule(drawable, NULL, show_weak = FALSE)
      } else {
        stack <- terra::rast(ens_tif)
        ens_aoa <- any(vapply(models[choice$members], `[[`, logical(1), "aoa"))
        ensemble <- if (is.null(at)) {
          # Drawn as atlas_build_ensemble draws it: ranked again over the cells
          # some member applies to; "outside" where a member reaches but none applies.
          outside <- terra::ifel(is.na(stack[["rank"]]) & !is.na(stack[["known"]]), 1, 0)
          c(atlas_tracker_layers(stack[["rank"]], outside, 0.5),
            list(known = terra::values(stack[["known"]], mat = FALSE), aoa = ens_aoa))
        } else {
          # Its rank layer holds values only where some member applies, so
          # ranking it as it stands is the drawing's ranking.
          list(hit = atlas_tracker_rank_points(stack[["rank"]], at[, 1], at[, 2],
                                               reach = terra::values(stack[["known"]], mat = FALSE)),
               aoa = ens_aoa)
        }
      }
    }
  }
  out <- list(none = FALSE, models = models, grade = grade, choice = choice, ensemble = ensemble,
              version = atlas_tracker_version(view, taxon))
  if (!is.null(at)) return(out)
  view$last_taxon <- taxon
  view$last_maps <- out
  out
}

`%|NA|%` <- function(x, y) if (length(x) != 1L || is.na(x)) y else unname(x)

atlas_tracker_best_of <- function(values, order) {
  hit <- order[order %in% values]
  if (length(hit)) hit[[1]] else utils::tail(order, 1)
}

#' The drawn map's rank and place at points, without drawing it: the same
#' answer as atlas_tracker_lookup(atlas_tracker_layers(...)), the ranks of
#' atlas_map_layers with ties averaged, but from the values sorted once rather
#' than a ranked copy of the whole grid, so a model costs its values and one
#' sorted vector. reach, when given (a combined map's "known" layer), says
#' which cells a member reaches.
atlas_tracker_rank_points <- function(suitability, x, y, dissimilarity = NULL, threshold = NULL, reach = NULL) {
  values <- terra::values(suitability, mat = FALSE)
  has_value <- is.finite(values)
  outside <- rep(FALSE, length(values))
  if (!is.null(dissimilarity) && length(threshold) == 1L && is.finite(threshold)) {
    index <- terra::values(dissimilarity, mat = FALSE)
    outside <- has_value & is.finite(index) & index > threshold
    rm(index)
  }
  inside <- has_value & !outside
  cell <- terra::cellFromXY(suitability, cbind(x, y))
  sorted <- sort(values[inside])
  n <- length(sorted)
  hit <- !is.na(cell) & inside[ifelse(is.na(cell), 1L, cell)]
  v <- values[cell[hit]]
  rank <- rep(NA_real_, length(x))
  if (n == 1L) {
    rank[hit] <- 1
  } else if (n > 1L) {
    below <- findInterval(v, sorted, left.open = TRUE)
    upto <- findInterval(v, sorted)
    rank[hit] <- (below + (upto - below + 1) / 2 - 1) / (n - 1)
  }
  reached <- if (is.null(reach)) has_value else is.finite(reach)
  reached <- !is.na(cell) & reached[ifelse(is.na(cell), 1L, cell)]
  list(rank = rank, place = ifelse(is.finite(rank), "inside", ifelse(reached, "outside_aoa", "beyond_reach")))
}

#' Where points fall on one map's layers: rank (NA unless inside) and place,
#' "inside", "outside_aoa" or "beyond_reach".
atlas_tracker_lookup <- function(layers, x, y, known = NULL) {
  cell <- terra::cellFromXY(layers$raster, cbind(x, y))
  rank <- ifelse(is.na(cell), NA_real_, layers$rank[cell])
  reached <- if (is.null(known)) {
    !is.na(cell) & is.finite(layers$outside[ifelse(is.na(cell), 1L, cell)])
  } else {
    !is.na(cell) & is.finite(known[ifelse(is.na(cell), 1L, cell)])
  }
  place <- ifelse(is.finite(rank), "inside", ifelse(reached, "outside_aoa", "beyond_reach"))
  list(rank = rank, place = place)
}

#' A taxon's scores at points in one release: the headline rank and place,
#' the kind of map it came from, and each model's own.
atlas_tracker_score <- function(maps, x, y) {
  per_model <- lapply(maps$models, function(m) atlas_tracker_lookup(m, x, y))
  ensemble <- if (!is.null(maps$ensemble)) atlas_tracker_lookup(maps$ensemble, x, y, known = maps$ensemble$known)
  atlas_tracker_headline(maps, per_model, ensemble, length(x))
}

#' The same, from maps read at their points (atlas_tracker_maps with at).
atlas_tracker_score_at <- function(maps) {
  per_model <- lapply(maps$models, `[[`, "hit")
  atlas_tracker_headline(maps, per_model, maps$ensemble$hit, length(per_model[[1]]$rank))
}

#' The headline score from each model's lookup (and the combined map's).
atlas_tracker_headline <- function(maps, per_model, ensemble, n) {
  if (!is.null(ensemble)) {
    return(list(rank = ensemble$rank, place = ensemble$place, kind = rep("ensemble", n),
                aoa = rep(maps$ensemble$aoa, n), per_model = per_model))
  }
  if (!is.null(maps$choice)) {
    hit <- per_model[[maps$choice$algorithm]]
    return(list(rank = hit$rank, place = hit$place, kind = rep("best_model", n),
                aoa = rep(maps$models[[maps$choice$algorithm]]$aoa, n), per_model = per_model))
  }
  ranks <- do.call(cbind, lapply(per_model, `[[`, "rank"))
  places <- do.call(cbind, lapply(per_model, `[[`, "place"))
  inside <- rowSums(is.finite(ranks)) > 0
  rank <- ifelse(inside, rowSums(ranks, na.rm = TRUE) / pmax(1, rowSums(is.finite(ranks))), NA_real_)
  place <- ifelse(inside, "inside", ifelse(rowSums(places == "outside_aoa") > 0, "outside_aoa", "beyond_reach"))
  list(rank = rank, place = place, kind = rep("mean", n),
       aoa = rep(any(vapply(maps$models, `[[`, logical(1), "aoa")), n), per_model = per_model)
}

#' The distance band of a nearest-site distance in km.
atlas_tracker_band <- function(km) {
  low <- ATLAS_TRACKER_BANDS_KM[[1]]
  high <- ATLAS_TRACKER_BANDS_KM[[2]]
  ifelse(is.na(km), "none",
         ifelse(km < low, sprintf("under_%d", low),
                ifelse(km < high, sprintf("%d_%d", low, high), sprintf("%d_plus", high))))
}

# ---- scoring finds ---------------------------------------------------------

#' The finds in a pull: rows first green on or after since that the ledger
#' does not hold yet.
atlas_tracker_finds <- function(occurrences, since = ATLAS_TRACKER_SINCE, done = character()) {
  if (!ATLAS_FIRST_GREEN_FIELD %in% names(occurrences)) {
    stop("the pull has no ", ATLAS_FIRST_GREEN_FIELD, " column: pull again with this version", call. = FALSE)
  }
  day <- occurrences[[ATLAS_FIRST_GREEN_FIELD]]
  key <- paste(occurrences$source, occurrences$observation_id, sep = ":")
  keep <- !is.na(day) & day >= since & !key %in% done
  out <- occurrences[keep, , drop = FALSE]
  out$key <- key[keep]
  out[order(out[[ATLAS_FIRST_GREEN_FIELD]], out$key), , drop = FALSE]
}

#' The name a find goes by in a release: its DNA name in a release named by
#' DNA, its record's own name in one from before.
atlas_tracker_name_in <- function(finds, naming) {
  if (identical(naming, "record") && "record_name" %in% names(finds)) finds$record_name else finds$scientific_name
}

#' Score finds against one release. Returns ledger rows.
atlas_tracker_score_release <- function(finds, view, promoted_at, scored_at, pulled_naming) {
  rows <- atlas_tracker_match(finds, view, promoted_at, scored_at, pulled_naming)
  atlas_tracker_rank_window(view, rows, rows[rows$status %in% "scored", , drop = FALSE])$rows
}

#' Everything about finds in a release that needs no raster: whether its pull
#' already holds them, the name and taxon they go by there, whether the taxon
#' has a map (status "scored" means it will be), the nearest known site, and
#' the find's grid point (columns .x and .y, which the ranking uses and the
#' ledger does not keep).
atlas_tracker_match <- function(finds, view, promoted_at, scored_at, pulled_naming) {
  grid <- view$grid
  rows <- atlas_tracker_types(data.frame(key = finds$key, stringsAsFactors = FALSE))
  rows$source <- finds$source
  rows$observation_id <- finds$observation_id
  rows$first_green_on <- finds[[ATLAS_FIRST_GREEN_FIELD]]
  rows$observed_on <- finds$observed_on
  if (ATLAS_TRACKER_CHANNEL_FIELD %in% names(finds)) rows$channel <- finds[[ATLAS_TRACKER_CHANNEL_FIELD]]
  rows$pulled_name <- finds$scientific_name
  rows$pulled_naming <- pulled_naming
  rows$release <- view$id
  rows$release_promoted_at <- promoted_at
  rows$scheme <- view$scheme
  rows$naming <- view$naming
  rows$scored_at <- scored_at
  placed <- atlas_tracker_place(finds$latitude, finds$longitude, grid)
  rows$cell <- placed$cell
  rows$.x <- placed$x
  rows$.y <- placed$y

  # The guard behind the date rule: a find its release already holds is
  # never scored against it.
  leaked <- finds$key %in% view$pull$key
  rows$status[leaked] <- "in_release_pull"

  names_in <- atlas_tracker_name_in(finds, view$naming)
  for (i in which(!leaked)) {
    match <- if (!is.na(names_in[[i]])) atlas_best_match(names_in[[i]], view$names, view$renames)
    if (is.null(match)) {
      rows$taxon[i] <- names_in[[i]]
      rows$status[i] <- "not_in_release"
      next
    }
    rows$taxon[i] <- match$name
    rows$matched_by[i] <- match$how
  }
  todo <- which(!leaked & is.na(rows$status))
  for (taxon in unique(rows$taxon[todo])) {
    mine <- todo[rows$taxon[todo] == taxon]
    known <- view$pull[view$pull$taxon == taxon, , drop = FALSE]
    # The nearest known site of the taxon, and whether the find is a new site
    # for it (Atlas's survey-site spacing) or new ground for anyone.
    nearest <- vapply(mine, function(i) {
      if (!nrow(known) || !is.finite(placed$lat[i])) return(NA_real_)
      min(atlas_km_between(placed$lat[i], placed$lng[i], known$lat, known$lng))
    }, numeric(1))
    rows$nearest_km[mine] <- round(nearest, 1)
    rows$band[mine] <- atlas_tracker_band(nearest)
    rows$new_site[mine] <- is.na(nearest) | nearest > ATLAS_SITE_KM
    rows$new_area[mine] <- !placed$cell[mine] %in% view$cells
    rows$status[mine] <- if (atlas_tracker_has_map(view, taxon)) "scored" else "no_map"
  }
  rows
}

#' Whether a taxon has a map in a release: a model with its metrics and raster.
atlas_tracker_has_map <- function(view, taxon) {
  for (entry in Filter(function(e) identical(e$taxon, taxon), view$entries)) {
    paths <- atlas_model_relpaths(taxon, view$grid, entry$algorithm, c(".json", ".tif"))
    if (!is.na(view$shas[paths[[1]]]) && !is.na(view$shas[paths[[2]]])) return(TRUE)
  }
  FALSE
}

#' Rank the new finds of a release window, and work out the window's effort
#' baseline (atlas_tracker_target_group) in the same pass: each taxon's maps
#' are read once, at its new finds and at the cells of every other taxon's
#' finds in the window. window is every live scored find of the release,
#' rows the new ones (from atlas_tracker_match). Returns the ranked rows and
#' the window's baseline.
atlas_tracker_rank_window <- function(view, rows, window, grid = view$grid) {
  tg <- list(per_find = data.frame(key = character(), tg_percentile = numeric(), stringsAsFactors = FALSE),
             hist = list())
  for (taxon in unique(window$taxon)) {
    mine <- which(rows$taxon %in% taxon & rows$status %in% "scored")
    others <- unique(window$cell[window$taxon != taxon & !is.na(window$cell)])
    if (!length(mine) && !length(others)) next
    tg_xy <- if (length(others)) atlas_tracker_cell_xy(others, grid) else matrix(numeric(), 0, 2)
    at <- rbind(cbind(rows$.x[mine], rows$.y[mine]), tg_xy)
    maps <- atlas_tracker_maps(view, taxon, at = at)
    if (isTRUE(maps$none)) next
    scores <- atlas_tracker_score_at(maps)
    if (length(mine)) {
      k <- seq_along(mine)
      rows$grade[mine] <- maps$grade
      rows$kind[mine] <- scores$kind[k]
      rows$rank[mine] <- round(scores$rank[k], 4)
      rows$place[mine] <- scores$place[k]
      rows$aoa[mine] <- ifelse(scores$aoa[k], "known", "unknown")
      rows$map_version[mine] <- maps$version
      for (algorithm in names(scores$per_model)) {
        rows[[paste0("rank_", algorithm)]][mine] <- round(scores$per_model[[algorithm]]$rank[k], 4)
        rows[[paste0("place_", algorithm)]][mine] <- scores$per_model[[algorithm]]$place[k]
      }
    }
    if (length(others)) {
      ranks <- scores$rank[length(mine) + seq_len(nrow(tg_xy))]
      ranks <- ranks[is.finite(ranks)]
      if (length(ranks)) {
        tg$hist[[taxon]] <- tabulate(pmin(100L, floor(ranks * 100) + 1L), nbins = 100L)
        # Every live find of the taxon in the window: earlier ones keep the
        # rank they were scored with, new ones take theirs from this pass.
        own <- window[window$taxon == taxon, c("key", "rank"), drop = FALSE]
        fresh <- match(own$key, rows$key[mine])
        own$rank[!is.na(fresh)] <- round(scores$rank[fresh[!is.na(fresh)]], 4)
        own <- own[is.finite(own$rank), , drop = FALSE]
        if (nrow(own)) {
          pct <- vapply(own$rank, function(r) (sum(ranks < r) + 0.5 * sum(ranks == r)) / length(ranks), numeric(1))
          tg$per_find <- rbind(tg$per_find, data.frame(key = own$key, tg_percentile = pct, stringsAsFactors = FALSE))
        }
      }
    }
    rm(maps, scores)
  }
  rows$.x <- NULL
  rows$.y <- NULL
  list(rows = rows, tg = tg)
}

#' Mark finds the newest pull no longer holds, or holds under another name,
#' as retracted; a find that comes back is restored. A find whose place was
#' corrected into another cell is retracted as moved, and scored again where
#' it is now (atlas_tracker_done leaves it out of what is done). Retracted
#' finds are left out of every count but one.
atlas_tracker_retract <- function(ledger, occurrences, today, grid = "draft") {
  if (!nrow(ledger)) return(ledger)
  key <- paste(occurrences$source, occurrences$observation_id, sep = ":")
  naming_now <- if ("record_name" %in% names(occurrences)) "sequence" else "record"
  now <- match(ledger$key, key)
  gone <- is.na(now)
  # A name is compared only with a name of the same kind: the record name a
  # find was pulled under against the record name it has now, and so on.
  record_now <- if (naming_now == "sequence") occurrences$record_name[now] else occurrences$scientific_name[now]
  current <- ifelse(ledger$pulled_naming == "record", record_now, occurrences$scientific_name[now])
  comparable <- !gone & (ledger$pulled_naming == naming_now | ledger$pulled_naming == "record")
  renamed <- comparable & !is.na(current) &
    atlas_name_key(current) != atlas_name_key(ledger$pulled_name)
  cell_now <- atlas_tracker_place(occurrences$latitude[now], occurrences$longitude[now], grid)$cell
  moved <- !gone & !is.na(ledger$cell) & !is.na(cell_now) & cell_now != ledger$cell
  why <- ifelse(gone, "no longer in the pull", ifelse(renamed, "renamed", ifelse(moved, "moved", NA_character_)))
  newly <- !is.na(why) & is.na(ledger$retracted_on)
  ledger$retracted_on[newly] <- as.character(today)
  ledger$retracted_why[!is.na(why)] <- why[!is.na(why)]
  back <- is.na(why) & !is.na(ledger$retracted_on)
  ledger$retracted_on[back] <- NA_character_
  ledger$retracted_why[back] <- NA_character_
  ledger
}

#' The finds the ledger is done with: every key it holds, except one whose
#' rows were all retracted as moved, which is scored again at its new place.
atlas_tracker_done <- function(ledger) {
  moved <- !is.na(ledger$retracted_why) & ledger$retracted_why == "moved"
  unique(ledger$key[!moved])
}

# ---- the effort-corrected baseline -----------------------------------------

#' For each scored find, where it sits among the cells of every other taxon's
#' finds in the same release window, read through its own taxon's map: the
#' share of those cells its rank beats (ties half). 0.5 is no better than
#' knowing where people look. Also each taxon's histogram of those ranks in
#' 100 bins, for the effort-corrected Boyce index. Worked out with a window's
#' ranks (atlas_tracker_rank_window) and saved under the window's finds, so
#' it is worked out again only when they change; missing names the windows
#' with no saved baseline for their finds as they are now.
atlas_tracker_target_group <- function(ledger, grid = "draft", cache = atlas_tracker_cache_dir()) {
  per_find <- data.frame(key = character(), tg_percentile = numeric(), stringsAsFactors = FALSE)
  hist <- list()
  missing <- character()
  live <- atlas_tracker_window(ledger)
  for (release in unique(live$release)) {
    path <- atlas_tracker_window_path(live[live$release == release, , drop = FALSE], release, grid, cache)
    if (!file.exists(path)) {
      missing <- c(missing, release)
      next
    }
    result <- readRDS(path)
    per_find <- rbind(per_find, result$per_find)
    for (taxon in names(result$hist)) hist[[paste(release, taxon, sep = "\x1f")]] <- result$hist[[taxon]]
  }
  list(per_find = per_find, hist = hist, missing = missing)
}

#' The finds a window's baseline is made from: live, scored, placed.
atlas_tracker_window <- function(ledger, release = NULL) {
  keep <- ledger$status %in% "scored" & is.na(ledger$retracted_on) & !is.na(ledger$cell)
  if (!is.null(release)) keep <- keep & ledger$release %in% release
  ledger[keep, , drop = FALSE]
}

#' Where a window's baseline is saved: under a hash of its finds.
atlas_tracker_window_path <- function(window, release, grid = "draft", cache = atlas_tracker_cache_dir()) {
  stamp <- substr(digest::digest(list(sort(paste(window$key, window$taxon, window$cell))), algo = "sha256"), 1, 16)
  file.path(cache, "target-group", grid, paste0(release, "-", stamp, ".rds"))
}

# ---- statistics ------------------------------------------------------------

#' Hirzel et al. (2006)'s continuous Boyce index on ranks in 0..1: moving
#' windows 0.1 wide in steps of 0.01, the ratio of observed to expected share
#' in each, and Spearman's rho of the ratio against the window's centre.
#' expected is a 100-bin histogram; NULL for the uniform expectation that a
#' rank scale over equal-area cells has by construction.
atlas_tracker_boyce <- function(ranks, expected = NULL) {
  ranks <- ranks[is.finite(ranks)]
  if (length(ranks) < 2L) return(NA_real_)
  observed <- tabulate(pmin(100L, floor(ranks * 100) + 1L), nbins = 100L)
  observed <- observed / sum(observed)
  expected <- if (is.null(expected)) rep(1 / 100, 100) else expected / sum(expected)
  starts <- 0:90
  ratio <- vapply(starts, function(s) {
    bins <- (s + 1):(s + 10)
    e <- sum(expected[bins])
    if (e <= 0) NA_real_ else sum(observed[bins]) / e
  }, numeric(1))
  centre <- (starts + 5) / 100
  ok <- is.finite(ratio)
  if (sum(ok) < 3L || stats::sd(ratio[ok]) == 0) return(NA_real_)
  round(suppressWarnings(stats::cor(ratio[ok], centre[ok], method = "spearman")), 3)
}

#' Wilson's interval for a share.
atlas_tracker_wilson <- function(k, n, z = 1.96) {
  if (!n) return(c(NA_real_, NA_real_))
  p <- k / n
  centre <- (p + z^2 / (2 * n)) / (1 + z^2 / n)
  half <- z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / (1 + z^2 / n)
  round(c(max(0, centre - half), min(1, centre + half)), 3)
}

#' One row of the published table, from the finds that make it. A place is
#' a taxon's 5 km cell in a release window: several finds of a taxon in one
#' cell are one place, so a single foray cannot fill a row on its own.
atlas_tracker_row <- function(finds, tg, hist) {
  units <- finds[!duplicated(paste(finds$release, finds$taxon, finds$cell)), , drop = FALSE]
  ranked <- units$rank[is.finite(units$rank)]
  n <- nrow(units)
  k <- length(ranked)
  show <- k >= ATLAS_TRACKER_MIN_SHARE
  share <- function(x) if (show) round(mean(x), 3) else NULL
  top_half <- sum(ranked >= 0.5)
  top_tenth <- sum(ranked >= 0.9)
  pct <- tg$tg_percentile[match(units$key, tg$key)]
  pct <- pct[is.finite(pct)]
  effort <- NULL
  if (k >= ATLAS_TRACKER_MIN_BOYCE && length(hist)) {
    # Each taxon's expected ranks, weighted by how many of its places count.
    pooled <- numeric(100)
    for (i in which(is.finite(units$rank))) {
      h <- hist[[paste(units$release[i], units$taxon[i], sep = "\x1f")]]
      if (!is.null(h) && sum(h)) pooled <- pooled + h / sum(h)
    }
    if (sum(pooled)) effort <- atlas_tracker_boyce(ranked, pooled)
  }
  list(
    places = n,
    finds = nrow(finds),
    ranked = k,
    top_half = share(ranked >= 0.5),
    top_half_ci = if (show) atlas_tracker_wilson(top_half, k),
    top_tenth = share(ranked >= 0.9),
    top_tenth_ci = if (show) atlas_tracker_wilson(top_tenth, k),
    mean_rank = share(ranked),
    mean_rank_p = if (show) signif(suppressWarnings(stats::wilcox.test(ranked, mu = 0.5, exact = FALSE)$p.value), 3),
    top_tenth_p = if (show) signif(stats::binom.test(top_tenth, k, 0.1, alternative = "greater")$p.value, 3),
    beats_effort = if (length(pct) >= ATLAS_TRACKER_MIN_SHARE) round(mean(pct), 3),
    beats_effort_n = length(pct),
    outside_aoa = if (n >= ATLAS_TRACKER_MIN_SHARE) round(mean(units$place == "outside_aoa"), 3),
    beyond_reach = if (n >= ATLAS_TRACKER_MIN_SHARE) round(mean(units$place == "beyond_reach"), 3),
    aoa = if (!n) NULL else if (all(units$aoa == "known")) "known" else if (all(units$aoa == "unknown")) "unknown" else "mixed",
    boyce = if (k >= ATLAS_TRACKER_MIN_BOYCE) atlas_tracker_boyce(ranked),
    boyce_effort = effort
  )
}

ATLAS_TRACKER_GRADES <- list(shift = c("strong", "weak", "failed", "untested"),
                             skill = c("passed", "failed", "untested"))

#' The subsets each row is split into: all finds, new sites for their taxon
#' and sites already known, and the distance bands.
atlas_tracker_subsets <- function(finds) {
  bands <- atlas_tracker_band(c(0, ATLAS_TRACKER_BANDS_KM[[1]], ATLAS_TRACKER_BANDS_KM[[2]], NA))
  out <- list(all = rep(TRUE, nrow(finds)),
              new_site = finds$new_site %in% TRUE,
              known_site = finds$new_site %in% FALSE)
  for (b in bands) out[[paste0("band_", b)]] <- finds$band %in% b
  out
}

# ---- the published summary -------------------------------------------------

#' Everything published about the finds: counts and shares, never a record.
#'
#' current is the live release's view (for the per-taxon tallies); tg the
#' effort baseline. Each published row covers places (taxon x 5 km cell x
#' release); per-taxon tallies count finds.
atlas_tracker_summary <- function(ledger, current = NULL, tg = list(per_find = NULL, hist = list()),
                                  grid = "draft", since = ATLAS_TRACKER_SINCE, generated_at = Sys.time(),
                                  pulled_at = NULL) {
  live <- ledger[is.na(ledger$retracted_on), , drop = FALSE]
  scored <- live[live$status == "scored", , drop = FALSE]
  # Finds that came through a steered or automatic channel are held out of
  # every evaluation row and shown on their own, one row per channel.
  evaluated <- is.na(scored$channel) | !nzchar(scored$channel) | scored$channel %in% ATLAS_TRACKER_EVALUATED_CHANNELS
  held <- scored[!evaluated, , drop = FALSE]
  held$channel <- ifelse(held$channel %in% ATLAS_TRACKER_HELD_CHANNELS, held$channel, "other")
  scored <- scored[evaluated, , drop = FALSE]
  counts <- function(x) stats::setNames(as.list(as.integer(table(factor(x, levels = names(ATLAS_TRACKER_STATUSES))))),
                                        names(ATLAS_TRACKER_STATUSES))
  strong_word <- function(scheme) if (identical(scheme, "shift")) "strong" else "passed"

  rows <- list()
  for (scheme in intersect(c("shift", "skill"), unique(scored$scheme))) {
    mine <- scored[scored$scheme == scheme, , drop = FALSE]
    for (release in c("all", sort(unique(mine$release)))) {
      in_release <- if (release == "all") mine else mine[mine$release == release, , drop = FALSE]
      for (grade in c("any", ATLAS_TRACKER_GRADES[[scheme]])) {
        in_grade <- if (grade == "any") in_release else in_release[in_release$grade %in% grade, , drop = FALSE]
        if (!nrow(in_grade)) next
        # By release, the whole row only: per release and subset the counts are too small.
        subsets <- atlas_tracker_subsets(in_grade)
        if (release != "all") subsets <- subsets["all"]
        for (subset in names(subsets)) {
          part <- in_grade[subsets[[subset]], , drop = FALSE]
          if (!nrow(part)) next
          rows[[length(rows) + 1L]] <- c(list(scheme = scheme, release = release, grade = grade, subset = subset),
                                         atlas_tracker_row(part, tg$per_find, tg$hist))
        }
      }
    }
  }

  for (scheme in intersect(c("shift", "skill"), unique(held$scheme))) {
    for (channel in intersect(c(ATLAS_TRACKER_HELD_CHANNELS, "other"), held$channel[held$scheme == scheme])) {
      part <- held[held$scheme == scheme & held$channel == channel, , drop = FALSE]
      rows[[length(rows) + 1L]] <- c(list(scheme = scheme, release = "all", grade = "any",
                                          subset = paste0("channel_", channel)),
                                     atlas_tracker_row(part, tg$per_find, tg$hist))
    }
  }

  # The line a visitor sees first: new sites for strong (or, before the
  # rebuild, passing) maps, under the live release's scheme.
  headline <- NULL
  scheme_now <- if (!is.null(current)) current$scheme else if (nrow(scored)) utils::tail(scored$scheme, 1)
  if (!is.null(scheme_now)) {
    pick <- Filter(function(r) r$scheme == scheme_now && r$release == "all" &&
                     r$grade == strong_word(scheme_now) && r$subset == "new_site", rows)
    if (length(pick)) {
      r <- pick[[1]]
      headline <- list(scheme = scheme_now, grade = r$grade, subset = "new_site", places = r$places,
                       ranked = r$ranked, top_half = r$top_half, top_half_chance = 0.5,
                       beats_effort = r$beats_effort, effort_chance = 0.5)
    }
  }

  # Per taxon, on its page: finds since the map it shows now was made.
  taxa <- list()
  if (!is.null(current) && nrow(scored)) {
    for (taxon in sort(unique(scored$taxon[scored$taxon %in% current$modelled]))) {
      version <- atlas_tracker_version(current, taxon)
      if (is.null(version)) next
      mine <- scored[scored$taxon == taxon & scored$map_version %in% version, , drop = FALSE]
      if (!nrow(mine)) next
      shown <- nrow(mine) >= ATLAS_TRACKER_MIN_TAXON
      taxa[[length(taxa) + 1L]] <- list(
        taxon = taxon,
        since = min(mine$first_green_on),
        finds = if (shown) nrow(mine),
        finds_text = if (shown) as.character(nrow(mine)) else sprintf("fewer than %d", ATLAS_TRACKER_MIN_TAXON),
        top_half = if (shown) sum(mine$rank >= 0.5, na.rm = TRUE),
        outside = if (shown) sum(mine$place != "inside"),
        new_sites = if (shown) sum(mine$new_site %in% TRUE)
      )
    }
  }

  coverage <- NULL
  if (nrow(live)) {
    counted <- live[live$status %in% c("scored", "no_map", "not_in_release"), , drop = FALSE]
    with_map <- counted$status == "scored"
    coverage <- list(finds = nrow(counted), with_map = sum(with_map),
                     with_strong_map = sum(with_map & counted$grade %in% c("strong", "passed")))
  }

  list(
    grid = grid,
    generated_at = format(generated_at, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    status = if (nrow(ledger)) "tracking" else "not_started",
    # The newest pull the run read: scoring stops while the nightly pull is
    # off, and the site says so.
    pulled_at = pulled_at,
    since = since,
    latest_find_on = if (nrow(live)) max(live$first_green_on) else NULL,
    current_release = if (!is.null(current)) list(id = current$id, scheme = current$scheme, naming = current$naming),
    min_taxon_finds = ATLAS_TRACKER_MIN_TAXON,
    min_ranked_for_share = ATLAS_TRACKER_MIN_SHARE,
    min_ranked_for_boyce = ATLAS_TRACKER_MIN_BOYCE,
    finds = list(total = nrow(ledger), by_status = counts(live$status),
                 held_out = stats::setNames(lapply(c(ATLAS_TRACKER_HELD_CHANNELS, "other"),
                                                   function(ch) sum(held$channel == ch)),
                                            c(ATLAS_TRACKER_HELD_CHANNELS, "other")),
                 retracted = sum(!is.na(ledger$retracted_on))),
    coverage = coverage,
    headline = headline,
    releases = lapply(unique(scored$release), function(id) {
      r <- scored[scored$release == id, , drop = FALSE]
      list(id = id, scheme = r$scheme[[1]], naming = r$naming[[1]], promoted_at = r$release_promoted_at[[1]],
           from = min(r$first_green_on), to = max(r$first_green_on))
    }),
    rows = rows,
    taxa = taxa
  )
}

#' Written with nulls as null: a withheld share is null, not an empty object.
atlas_tracker_write_json <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(jsonlite::toJSON(x, auto_unbox = TRUE, pretty = TRUE, na = "null", null = "null", digits = NA), path)
  invisible(path)
}

#' The published summary on this machine, or NULL before the first run.
atlas_read_tracker_summary <- function(grid = "draft") {
  path <- atlas_tracker_summary_path(grid)
  if (!file.exists(path)) return(NULL)
  tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE), error = function(e) NULL)
}

#' What GET /api/tracker answers: the summary, or not_started before there is one.
atlas_tracker_answer <- function(grid = "draft") {
  summary <- atlas_read_tracker_summary(grid)
  if (is.null(summary)) {
    return(list(grid = grid, status = "not_started", since = ATLAS_TRACKER_SINCE, rows = list(), taxa = list()))
  }
  summary
}

#' One taxon's tally, for /api/taxa/<name>: NULL when it has none.
atlas_tracker_for <- function(summary, name) {
  if (is.null(summary)) return(NULL)
  for (t in summary$taxa %||% list()) {
    # A withheld count is left out, not sent as null.
    if (identical(t$taxon, name)) return(Filter(Negate(is.null), t[setdiff(names(t), "taxon")]))
  }
  NULL
}

# ---- a run -----------------------------------------------------------------

#' Score every new find, update the private ledger and publish the summary.
#'
#' Reads the newest local pull and the store; asks mycomap.org nothing. A
#' find is scored once, against the release live when its day began, and
#' never again; a later run only marks it retracted if the pull drops it.
atlas_track_new_finds <- function(store = NULL, grid = "draft", since = ATLAS_TRACKER_SINCE,
                                  occurrences = NULL, dry_run = FALSE, quiet = FALSE,
                                  now = Sys.time(), frozen = atlas_tracker_promotions_file(grid)) {
  say <- function(...) if (!isTRUE(quiet)) message(...)
  if (is.null(store)) stop("the tracker reads releases from a store: pass --store or set ATLAS_STORE", call. = FALSE)
  occurrences <- occurrences %||% atlas_read_occurrences()
  # Only the columns a run reads: the pull is held for the whole run.
  occurrences <- occurrences[, intersect(c("source", "observation_id", "scientific_name", "record_name",
                                           "latitude", "longitude", "observed_on", ATLAS_FIRST_GREEN_FIELD,
                                           ATLAS_TRACKER_CHANNEL_FIELD), names(occurrences)), drop = FALSE]
  manifest <- atlas_read_manifest()
  today <- format(now, "%Y-%m-%d", tz = "UTC")
  stamp <- format(now, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

  ledger <- atlas_tracker_load(store, grid, "ledger.tsv.gz")
  ledger <- if (is.null(ledger)) atlas_tracker_empty_ledger() else atlas_tracker_types(ledger)
  runs <- atlas_tracker_load(store, grid, "runs.tsv.gz")
  pointer <- paste0("current/", grid, ".json")
  current_pointer <- if (store$exists(pointer)) atlas_store_text(store, pointer)
  promotions <- atlas_tracker_promotions(store, grid, runs, frozen)

  # Retractions first, so a find that moved is scored again in this run.
  ledger <- atlas_tracker_retract(ledger, occurrences, today, grid)
  finds <- atlas_tracker_finds(occurrences, since, atlas_tracker_done(ledger))
  pulled_naming <- if ("record_name" %in% names(occurrences)) "sequence" else "record"
  say(sprintf("%d new finds first green since %s", nrow(finds), since))
  added <- list()
  live_at <- atlas_tracker_live_at(finds[[ATLAS_FIRST_GREEN_FIELD]], promotions)
  none <- is.na(live_at)
  if (any(none)) {
    rows <- atlas_tracker_types(data.frame(key = finds$key[none], stringsAsFactors = FALSE))
    rows$source <- finds$source[none]
    rows$observation_id <- finds$observation_id[none]
    rows$first_green_on <- finds[[ATLAS_FIRST_GREEN_FIELD]][none]
    rows$status <- "no_release"
    rows$scored_at <- stamp
    added[[length(added) + 1L]] <- rows
  }
  # One release at a time, its view let go before the next: the releases
  # with new finds, and any whose baseline is not saved for its finds now
  # (a retraction changed them, or this machine's cache is new).
  stale <- atlas_tracker_target_group(ledger, grid)$missing
  for (id in unique(c(live_at[!none], stale))) {
    mine <- finds[!none & live_at %in% id, , drop = FALSE]
    view <- atlas_tracker_view(store, id, grid)
    # The release's pull must be older than every day it scores.
    early <- mine[[ATLAS_FIRST_GREEN_FIELD]] <= substr(view$pulled_at, 1, 10)
    if (any(early)) {
      stop("release ", id, " was pulled on ", view$pulled_at, ", not before every find scored against it",
           call. = FALSE)
    }
    at <- promotions$promoted_at[promotions$release == id]
    rows <- if (nrow(mine)) {
      atlas_tracker_match(mine, view, at[[length(at)]], stamp, pulled_naming)
    } else {
      cbind(atlas_tracker_empty_ledger(), .x = numeric(), .y = numeric())
    }
    window <- rbind(atlas_tracker_window(ledger, id), atlas_tracker_window(rows[, ATLAS_TRACKER_LEDGER_FIELDS, drop = FALSE]))
    ranked <- atlas_tracker_rank_window(view, rows, window, grid)
    path <- atlas_tracker_window_path(window, id, grid)
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    saveRDS(ranked$tg, path)
    if (nrow(mine)) {
      added[[length(added) + 1L]] <- ranked$rows
      say(sprintf("  %d finds against release %s (%s scheme, %s names)", nrow(mine), id, view$scheme, view$naming))
    }
    rm(view, ranked, rows, window)
    invisible(gc(FALSE))
  }
  if (length(added)) ledger <- rbind(ledger, do.call(rbind, added))

  current <- if (!is.null(current_pointer$release)) atlas_tracker_view(store, current_pointer$release, grid, pull = FALSE)
  tg <- atlas_tracker_target_group(ledger, grid)
  if (length(tg$missing)) warning("no effort baseline for release ", paste(tg$missing, collapse = ", "), call. = FALSE)
  summary <- atlas_tracker_summary(ledger, current, tg, grid, since, now,
                                   pulled_at = as.character(manifest$pulled_at %||% NA))

  run <- data.frame(ran_at = stamp, pull = as.character(manifest$file %||% NA),
                    pulled_at = as.character(manifest$pulled_at %||% NA),
                    current_release = as.character(current_pointer$release %||% NA),
                    current_promoted_at = as.character(current_pointer$promoted_at %||% NA),
                    new_finds = nrow(finds), ledger = nrow(ledger), stringsAsFactors = FALSE)
  if (isTRUE(dry_run)) {
    say("dry run: nothing written")
    return(invisible(list(ledger = ledger, summary = summary, run = run)))
  }
  atlas_tracker_save(store, grid, "ledger.tsv.gz", ledger)
  atlas_tracker_save(store, grid, "runs.tsv.gz", rbind(runs, run))
  path <- atlas_tracker_summary_path(grid)
  atlas_tracker_write_json(summary, path)
  store$put(atlas_tracker_summary_key(grid), path)
  say(sprintf("ledger %d finds (%d scored); summary at %s", nrow(ledger), sum(ledger$status == "scored"), path))
  invisible(list(ledger = ledger, summary = summary, run = run))
}

#' A run that cannot fail anything else: the tracker is bookkeeping, and a
#' failure is said aloud as a warning, never an error.
atlas_track_new_finds_quietly <- function(...) {
  tryCatch(atlas_track_new_finds(...), error = function(e) {
    warning("the new-find tracker did not run: ", conditionMessage(e), call. = FALSE)
    invisible(NULL)
  })
}
