# A small world for the new-find tracker: a store with releases whose models
# are real rasters on the draft grid, the pulls their jobs were planned from,
# and a record of when each was promoted.
#
# The rasters cover 20 x 20 cells of 5 km around the grid's origin (latitude
# 40, longitude -96). Their two westmost columns are empty, beyond the
# model's reach; elsewhere suitability rises from west to east, so a find's
# rank is known from its column.

TRACKER_SIZE <- 5000
TRACKER_XMIN <- -50000
TRACKER_YMAX <- 50000

# The centre of column col, row row (both from 1) of the tracker's rasters.
tracker_xy <- function(col, row = 10) {
  cbind(x = TRACKER_XMIN + (col - 0.5) * TRACKER_SIZE, y = TRACKER_YMAX - (row - 0.5) * TRACKER_SIZE)
}

# Longitude and latitude of grid coordinates.
tracker_lonlat <- function(xy) {
  points <- terra::project(terra::vect(xy, crs = ATLAS_CRS), "EPSG:4326")
  terra::crds(points)
}

tracker_raster <- function(values) {
  r <- terra::rast(xmin = TRACKER_XMIN, xmax = -TRACKER_XMIN, ymin = -TRACKER_YMAX, ymax = TRACKER_YMAX,
                   resolution = TRACKER_SIZE, crs = ATLAS_CRS)
  terra::values(r) <- values
  r
}

# Suitability by column (the default rises east; the two westmost columns empty).
tracker_surface <- function(by_col = function(col) col) {
  cols <- rep(1:20, times = 20)
  v <- by_col(cols)
  v[cols <= 2] <- NA
  tracker_raster(v)
}

# A dissimilarity layer: the west half unlike any training site (2), the east like them (0.5).
tracker_dissimilarity <- function() {
  cols <- rep(1:20, times = 20)
  tracker_raster(ifelse(cols <= 10, 2, 0.5))
}

tracker_put <- function(store, file) {
  sha <- atlas_sha256(file)
  store$put(atlas_object_key(sha), file)
  list(sha256 = sha, bytes = file.info(file)$size)
}

tracker_put_raster <- function(store, raster) {
  file <- tempfile(fileext = ".tif")
  terra::writeRaster(raster, file, overwrite = TRUE)
  tracker_put(store, file)
}

tracker_put_json <- function(store, x) {
  file <- tempfile(fileext = ".json")
  atlas_write_json(x, file)
  tracker_put(store, file)
}

# Records of a pull: one row per point, at grid columns/rows, with the
# pull's columns and the first-green date.
tracker_records <- function(taxon, cols, rows = 10, ids = NULL, first_green_on = NA, source = "iNaturalist",
                            record_name = NULL) {
  n <- max(length(cols), length(rows))
  cols <- rep_len(cols, n)
  rows <- rep_len(rows, n)
  ll <- tracker_lonlat(tracker_xy(cols, rows))
  ids <- ids %||% as.character(sample.int(1e8, n))
  out <- data.frame(
    id = ids, observation_id = ids, source = source, scientific_name = rep_len(taxon, n),
    genus = sub(" .*", "", rep_len(taxon, n)), observed_on = "2026-09-01",
    latitude = sprintf("%.6f", ll[, 2]), longitude = sprintf("%.6f", ll[, 1]),
    state = "Kansas", country = "United States", sequence_id = "", updated_at = "2026-10-01",
    first_green_on = rep_len(first_green_on, n), stringsAsFactors = FALSE
  )
  if (!is.null(record_name)) out$record_name <- rep_len(record_name, n)
  out
}

# One model: metrics and raster (and dissimilarity layer) in the store, and
# its index entry and file entries for a release.
tracker_model <- function(store, taxon, algorithm = "maxnet", scheme = "shift", grade = "strong",
                          skill = if (grade %in% c("strong", "weak")) "passed" else "failed",
                          surface = tracker_surface(), dissimilarity = NULL, strength = 0.8, auc = 0.8,
                          fingerprint = paste0("fp-", taxon)) {
  metrics <- list(taxon = taxon, algorithm = algorithm, skill = skill, auc_mean = auc,
                  map_strength = strength, map = "drawn",
                  bounds = list(south = 39.5, west = -96.6, north = 40.5, east = -95.4))
  if (identical(scheme, "shift")) {
    metrics$grade <- grade
    metrics$null <- list(design = ATLAS_NULL_DESIGN)
  }
  if (!is.null(dissimilarity)) metrics$applicability <- list(threshold = 1)
  paths <- atlas_model_relpaths(taxon, "draft", algorithm, c(".json", ".tif", ".di.tif"))
  files <- list(c(list(path = paths[[1]]), tracker_put_json(store, metrics)),
                c(list(path = paths[[2]]), tracker_put_raster(store, surface)))
  if (!is.null(dissimilarity)) files[[3]] <- c(list(path = paths[[3]]), tracker_put_raster(store, dissimilarity))
  entry <- list(taxon = taxon, algorithm = algorithm, fingerprint = fingerprint, settings_key = "s1",
                presences = 30L, map = TRUE, skill = skill)
  if (identical(scheme, "shift")) entry$grade <- grade
  list(entry = entry, files = files)
}

# A combined map for a taxon whose members are given: its JSON and its
# three-layer raster, as atlas_build_ensemble writes them.
tracker_ensemble <- function(store, taxon, members, rank = tracker_surface(function(col) -col)) {
  slug <- gsub("(^-|-$)", "", gsub("[^a-z0-9]+", "-", tolower(taxon)))
  known <- tracker_surface(function(col) rep(1, length(col)))
  stack <- c(rank, rank * 0, known)
  names(stack) <- c("rank", "disagreement", "known")
  meta <- list(members = lapply(members, function(a) list(algorithm = a, weight = 0.3)),
               bounds = list(south = 39.5, west = -96.6, north = 40.5, east = -95.4), map_strength = 0.8)
  list(files = list(
    c(list(path = file.path("models", "draft", "ensemble", paste0(slug, ".json"))), tracker_put_json(store, meta)),
    c(list(path = file.path("models", "draft", "ensemble", paste0(slug, ".tif"))), tracker_put_raster(store, stack))
  ))
}

# Publish a release: its pull as a job input, its manifest, and when it was
# promoted (a write-once promotion record, as the store keeps from the rebuild on).
tracker_release <- function(store, id, pulled_at, promoted_at, pull, models = list(), extra_files = list(),
                            current = TRUE) {
  pull_file <- tempfile(fileext = ".tsv.gz")
  atlas_write_tsv_gz(pull, pull_file)
  job <- paste0("job-", id)
  pull_entry <- c(list(path = "occurrences/occurrences-test.tsv.gz"), tracker_put(store, pull_file))
  atlas_store_json(store, paste0("jobs/draft/", job, "/job.json"), list(id = job, inputs = list(pull_entry)))
  files <- c(unlist(lapply(models, `[[`, "files"), recursive = FALSE), extra_files)
  manifest <- list(id = id, grid = "draft", created_at = promoted_at, job = job,
                   pull = list(pulled_at = pulled_at, records = nrow(pull)),
                   index = lapply(models, `[[`, "entry"), files = files)
  atlas_store_json(store, paste0("releases/draft/", id, ".json"), manifest)
  atlas_store_json(store, atlas_promotion_key(id, "draft", as.POSIXct(promoted_at, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")),
                   list(release = id, grid = "draft", promoted_at = promoted_at))
  if (isTRUE(current)) atlas_store_json(store, "current/draft.json", list(release = id, promoted_at = promoted_at))
  invisible(manifest)
}

# Run the tracker on a pull, in a data directory of its own, with no frozen history.
tracker_run <- function(store, occurrences, dir = machine(), ...) {
  on_machine(dir, atlas_track_new_finds(store, occurrences = occurrences, quiet = TRUE, frozen = "", ...))
}

ledger_row <- function(result, key) result$ledger[result$ledger$key == key, , drop = FALSE]
