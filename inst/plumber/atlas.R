# Development API for the Atlas web app.
#
# It serves what the pull wrote, and never an exact coordinate: the map
# endpoint aggregates to ATLAS_PUBLIC_DEGREES, which is the rule published
# rasters follow too.

root <- Sys.getenv("ATLAS_ROOT", unset = ".")

if (requireNamespace("mycomapatlas", quietly = TRUE)) {
  library(mycomapatlas)
} else {
  for (file in list.files(file.path(root, "R"), pattern = "[.][Rr]$", full.names = TRUE)) {
    source(file)
  }
}

cache <- new.env(parent = emptyenv())

# Links written into downloaded files and pictures point at this site.
site_origin <- atlas_site_origin()

cached_occurrences <- function() {
  if (is.null(cache$occurrences)) {
    cache$occurrences <- atlas_read_occurrences()
  }
  cache$occurrences
}

# On a machine that holds a release but never made the pull, there are no
# occurrences; the collection cells come from what the release published.
cached_cells_source <- function() {
  if (is.null(cache$cells_source)) {
    occurrences <- tryCatch(cached_occurrences(), error = function(e) NULL)
    cache$cells_source <- list(
      occurrences = occurrences,
      public = if (is.null(occurrences)) atlas_read_public_cells() else NULL
    )
  }
  cache$cells_source
}

cached_taxa <- function() {
  if (is.null(cache$taxa)) {
    # The pull already wrote this; recomputing 17k fingerprints per boot is
    # pure waste. Fall back to computing them if the file is missing or empty.
    path <- atlas_path("occurrences", "taxa-latest.json")
    from_file <- if (file.exists(path)) {
      jsonlite::fromJSON(path, simplifyVector = TRUE)
    } else {
      NULL
    }
    cache$taxa <- if (is.data.frame(from_file) && nrow(from_file)) {
      from_file
    } else {
      atlas_taxon_fingerprints(cached_occurrences())
    }
  }
  cache$taxa
}

#* @filter cors
function(req, res) {
  # The web app reaches this through vite's proxy, which is same-origin, so
  # nothing normal depends on these headers. On a laptop they exist for a
  # browser opened straight at the dev server, and only for origins on the
  # allowlist; the public server sets ATLAS_ALLOWED_ORIGINS=* so any site can
  # build on the API.
  origin <- atlas_allowed_origin(req$HTTP_ORIGIN)
  if (!is.null(origin)) {
    res$setHeader("Access-Control-Allow-Origin", origin)
    res$setHeader("Access-Control-Expose-Headers", atlas_exposed_headers())
    res$setHeader("Vary", "Origin")
  }
  if (identical(req$REQUEST_METHOD, "OPTIONS")) {
    res$setHeader("Access-Control-Allow-Methods", "GET, OPTIONS")
    res$setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization")
    res$status <- 200L
    return(list())
  }
  plumber::forward()
}

# Tests replace what reaches the network or the clock by defining
# atlas_service_overrides in the environment this file is read into:
# introspect (the call to .org), now, and the download services.
overrides <- get0("atlas_service_overrides", ifnotfound = list())
introspect <- overrides$introspect %||% atlas_introspect_http
clock <- overrides$now %||% function() as.numeric(Sys.time())
download_services <- atlas_download_services(overrides$download %||% list())
release_cache <- new.env(parent = emptyenv())

signin_config <- atlas_signin_config()
access_config <- atlas_access_config()
access_state <- atlas_access_state()
for (alert in c(signin_config$problems, atlas_access_alerts(access_config))) message(alert)

# Read the taxa and every model's summary once at boot, so the first person
# to search is not the one who waits while thousands of files are read.
# Plumber answers one request at a time; a slow first search stalls everyone.
invisible(tryCatch({
  cache$search_index <- atlas_search_index(cached_taxa())
  cache$models_draft <- new.env(parent = emptyenv())
  cache$search_mapped <- atlas_search_mapped(atlas_model_index("draft", cache$models_draft))
  cache$search_mapped_at <- as.numeric(Sys.time())
}, error = function(e) NULL))

# Every taxon's 0.1 degree collection cells, for "recorded nearby": built from
# the pull on a machine that has it, read from the release everywhere else.
cached_all_cells <- function() {
  if (is.null(cache$all_cells)) {
    source <- cached_cells_source()
    cache$all_cells <- if (!is.null(source$occurrences)) {
      atlas_public_cells_table(source$occurrences)
    } else {
      source$public
    }
  }
  cache$all_cells
}

invisible(tryCatch({
  cache$here_index <- atlas_read_here_index("draft")
  cached_all_cells()
}, error = function(e) NULL))

#* After every answer: an error is never left with a cacheable header.
#* @plumber
function(pr) {
  # After serialisation the answer is value, a list with status and headers:
  # changing res then would change nothing that is sent.
  pr$registerHooks(list(postserialize = function(req, res, value) {
    if (startsWith(req$PATH_INFO %||% "", "/api/") && is.list(value) && !is.null(value$status)) {
      settled <- atlas_settle_cache_control(value$status, value$headers[["Cache-Control"]])
      if (!is.null(settled)) value$headers[["Cache-Control"]] <- settled
    }
    value
  }))
}

#* @filter access
function(req, res) {
  if (identical(req$REQUEST_METHOD, "OPTIONS") || !startsWith(req$PATH_INFO, "/api/")) {
    return(plumber::forward())
  }
  access_state$served <- if (is.null(access_state$served)) 1 else access_state$served + 1
  if (access_state$served %% 1000 == 0) atlas_rate_sweep(access_state)

  decision <- atlas_access_decision(req, access_state, access_config, now = clock(),
                                    transport = introspect, signin = signin_config)
  req$atlas_identity <- decision$identity
  for (name in names(decision$headers)) {
    res$setHeader(name, decision$headers[[name]])
  }
  if (!is.null(decision$status)) {
    res$status <- decision$status
    res$setHeader("Content-Type", "application/json")
    res$body <- as.character(jsonlite::toJSON(decision$body, auto_unbox = TRUE))
    return(res)
  }
  cache_control <- atlas_cache_control(req$PATH_INFO, req$QUERY_STRING)
  if (!is.null(cache_control)) res$setHeader("Cache-Control", cache_control)
  plumber::forward()
}

# ---- signing in ------------------------------------------------------------
# Browser routes, outside /api: they redirect and set cookies (R/auth.R).

#* Start signing in: go to mycomap.org, which sends the browser back to the callback.
#* @get /auth/dev-bridge/start
function(req, res, returnTo = "/") {
  atlas_send(res, atlas_signin_start(signin_config, returnTo, now = clock()))
}

#* Back from mycomap.org with a signed token: check it, start a session.
#* @get /auth/dev-bridge/callback
function(req, res, token = "") {
  atlas_send(res, atlas_signin_callback(req, signin_config, token, now = clock()))
}

#* Sign out: clear this site's session cookie.
#* @post /auth/logout
function(req, res) {
  atlas_send(res, atlas_signout(req, signin_config))
}

#* Whether the caller is signed in, and how.
#* @get /api/me
#* @serializer unboxedJSON
function(req) {
  atlas_me(req$atlas_identity, signin_config)
}

#* This API's OpenAPI description: the file the developer page is drawn from.
#* @get /api/openapi.json
#* @serializer contentType list(type = "application/json")
function() {
  path <- atlas_openapi_path(root)
  readBin(path, "raw", file.info(path)$size)
}

#* Every dataset, package and paper Atlas is built on, and every file it makes.
#* @get /api/sources
#* @serializer contentType list(type = "application/json")
function() {
  path <- atlas_sources_path(root)
  readBin(path, "raw", file.info(path)$size)
}

#* The versioned archives on Zenodo: every version of each series, with DOIs.
#* @get /api/downloads
#* @serializer unboxedJSON
function() {
  list(series = atlas_archive_ledgers())
}

#* What the last pull holds.
#* @get /api/status
#* @serializer unboxedJSON
function() {
  manifest <- atlas_status_manifest()
  if (is.null(manifest)) {
    return(list(ready = FALSE))
  }
  out <- list(
    ready = TRUE,
    pulledAt = manifest$pulled_at,
    records = manifest$records,
    taxa = manifest$taxa,
    fingerprint = manifest$fingerprint
  )
  # A full pull has no since date. Leave the field out rather than shipping an
  # NA, which serialises as an empty object.
  since <- manifest$since
  if (length(since) && !is.na(since)) {
    out$since <- as.character(since)
  }
  # The release the maps come from, and the records it was built from. The
  # box pulls every night before fitting, so the newest pull above can be
  # ahead of the maps; the release is what to cite.
  release <- atlas_status_release()
  if (!is.null(release)) out$release <- release
  out
}

#* Environmental layers: what is registered, and what of it is built.
#* @param grid draft or production
#* @get /api/layers
#* @serializer unboxedJSON
function(grid = "draft") {
  list(grid = grid, layers = atlas_layer_overview(grid))
}

#* Find taxa and genera by what someone typed, forgiving typos and spellings.
#* @param q What was typed
#* @param limit Most species to return
#* @get /api/search
#* @serializer unboxedJSON
function(q = "", limit = 10) {
  if (is.null(cache$search_index)) {
    cache$search_index <- atlas_search_index(cached_taxa())
  }
  # Which taxa have maps changes only when a batch or a release lands, and
  # checking thousands of model files takes a second or two on every
  # keystroke. So it is refreshed at most once a minute.
  now <- as.numeric(Sys.time())
  if (is.null(cache$search_mapped) || now - cache$search_mapped_at > 60) {
    if (is.null(cache$models_draft)) {
      cache$models_draft <- new.env(parent = emptyenv())
    }
    cache$search_mapped <- atlas_search_mapped(atlas_model_index("draft", cache$models_draft))
    cache$search_mapped_at <- now
  }
  limit <- min(50L, max(1L, suppressWarnings(as.integer(limit)), na.rm = TRUE))
  atlas_search(cache$search_index, substr(as.character(q), 1L, 200L), cache$search_mapped, limit = limit)
}

#* What could grow here: every mapped taxon a place suits, best first.
#* @param lat Latitude
#* @param lng Longitude
#* @param limit Most taxa to return
#* @param min_score Leave out taxa scoring below this, from 0 to 1
#* @param nearby_km How far to look for collections
#* @get /api/here
#* @serializer unboxedJSON
function(lat, lng, limit = 50, min_score = 0, nearby_km = 25, res) {
  if (is.null(cache$here_index)) {
    cache$here_index <- atlas_read_here_index("draft")
  }
  if (is.null(cache$here_index)) {
    res$status <- 503L
    return(list(error = "the place index has not been built: ./atlas build-here-index"))
  }
  number <- function(x, default) {
    value <- suppressWarnings(as.numeric(x))
    if (length(value) != 1L || !is.finite(value)) default else value
  }
  lat <- number(lat, NA_real_)
  lng <- number(lng, NA_real_)
  if (!is.finite(lat) || !is.finite(lng) || abs(lat) > 90 || abs(lng) > 180) {
    res$status <- 400L
    return(list(error = "lat and lng must be a point on Earth"))
  }
  atlas_here(
    cache$here_index, lat, lng,
    cells = cached_all_cells(), taxa = cached_taxa(),
    limit = as.integer(min(1000, max(1, number(limit, 50)))),
    min_score = min(1, max(0, number(min_score, 0))),
    nearby_km = min(100, max(1, number(nearby_km, 25)))
  )
}

#* Taxa with their record and locality counts.
#* @param search Part of a scientific name
#* @param min_localities Smallest number of independent localities
#* @param limit Page size
#* @param offset Rows to skip
#* @get /api/taxa
#* @serializer unboxedJSON
function(search = "", min_localities = 0, limit = 100, offset = 0) {
  rows <- cached_taxa()
  rows <- rows[rows$localities >= as.numeric(min_localities), , drop = FALSE]
  if (nzchar(search)) {
    keep <- grepl(tolower(search), tolower(rows$scientific_name), fixed = TRUE)
    rows <- rows[keep, , drop = FALSE]
  }
  total <- nrow(rows)
  offset <- max(0, as.integer(offset))
  limit <- max(1, as.integer(limit))
  page <- if (offset >= total) rows[0, , drop = FALSE] else {
    rows[seq(offset + 1, min(total, offset + limit)), , drop = FALSE]
  }
  list(total = total, items = page)
}

#* One taxon's counts.
#* @get /api/taxa/<name>
#* @serializer unboxedJSON
function(name, res) {
  row <- atlas_taxon_row(cached_taxa(), atlas_decode_name(name))
  if (is.null(row)) {
    res$status <- 404L
    return(list(error = "no such taxon in the current pull"))
  }
  row
}

#* Every fitted model, newest first, as a light summary. The full record of
#* one model is at /api/taxa/<name>/model.
#* @param grid draft or production
#* @get /api/models
#* @serializer contentType list(type = "application/json")
function(grid = "draft") {
  key <- paste0("models_", grid)
  if (is.null(cache[[key]])) {
    cache[[key]] <- new.env(parent = emptyenv())
  }
  # Checking thousands of model files took seconds; the list changes only
  # when a release is pulled, so it is rebuilt at most once a minute.
  atlas_memo_json(cache, paste0("models_json_", grid), function() {
    list(grid = grid, models = atlas_model_index(grid, cache[[key]]))
  })
}

#* The models Atlas fits, with the labels people see.
#* @get /api/algorithms
#* @serializer unboxedJSON
function() {
  atlas_algorithm_labels()
}

#* The newest model benchmark: every model scored on the same folds.
#* @get /api/benchmarks/latest
#* @serializer unboxedJSON
function(grid = "draft", res) {
  study <- atlas_latest_study("benchmarks", grid, prefix = "models")
  if (is.null(study)) {
    res$status <- 404L
    return(list(error = "no benchmark has been run yet"))
  }
  study
}

#* One taxon's fitted model: its scores, settings and map bounds.
#* @param algorithm maxnet (default), xgboost, rf or esm
#* @get /api/taxa/<name>/model
#* @serializer unboxedJSON
function(name, grid = "draft", algorithm = "maxnet", res) {
  algorithm <- atlas_request_algorithm(algorithm)
  if (is.null(algorithm)) {
    res$status <- 400L
    return(list(error = "unknown algorithm"))
  }
  path <- atlas_model_path(atlas_decode_name(name), grid, ".json", algorithm)
  if (!file.exists(path)) {
    res$status <- 404L
    return(list(error = "no model for this taxon yet"))
  }
  jsonlite::fromJSON(path, simplifyVector = FALSE)
}

#* A taxon's suitability map, ready to lay over a slippy map.
#* @param algorithm maxnet (default), xgboost, rf or esm
#* @get /api/taxa/<name>/map.png
#* @serializer contentType list(type = "image/png")
function(name, grid = "draft", algorithm = "maxnet", res) {
  algorithm <- atlas_request_algorithm(algorithm)
  if (is.null(algorithm)) {
    res$status <- 400L
    return(raw())
  }
  path <- atlas_model_path(atlas_decode_name(name), grid, ".png", algorithm)
  if (!file.exists(path)) {
    res$status <- 404L
    return(raw())
  }
  res$setHeader("Link", ATLAS_MAP_LICENSE_LINK)
  readBin(path, "raw", file.info(path)$size)
}

#* A taxon's ensemble: its passing models averaged, with where they disagree.
#* @get /api/taxa/<name>/ensemble
#* @serializer unboxedJSON
function(name, grid = "draft", res) {
  path <- atlas_ensemble_path(atlas_decode_name(name), grid, ".json")
  if (!file.exists(path)) {
    res$status <- 404L
    return(list(error = "no ensemble for this taxon: fewer than two of its models passed"))
  }
  jsonlite::fromJSON(path, simplifyVector = FALSE)
}

#* A taxon's ensemble map, or where its members disagree, as an image.
#* @param layer map (default) or disagreement
#* @get /api/taxa/<name>/ensemble.png
#* @serializer contentType list(type = "image/png")
function(name, grid = "draft", layer = "map", res) {
  extension <- switch(layer, map = ".png", disagreement = ".disagreement.png", NULL)
  if (is.null(extension)) {
    res$status <- 400L
    return(raw())
  }
  path <- atlas_ensemble_path(atlas_decode_name(name), grid, extension)
  if (!file.exists(path)) {
    res$status <- 404L
    return(raw())
  }
  res$setHeader("Link", ATLAS_MAP_LICENSE_LINK)
  readBin(path, "raw", file.info(path)$size)
}

#* A taxon's suitability raster as a GeoTIFF. Needs a session or a token.
#* @param algorithm maxnet (default), xgboost, rf or esm
#* @get /api/taxa/<name>/raster.tif
function(name, grid = "draft", algorithm = "maxnet", req, res) {
  atlas_send(res, atlas_raster_response(
    req$atlas_identity, atlas_decode_name(name), grid, algorithm,
    download_services, release_cache, now = clock()
  ))
}

#* A taxon's map as one picture for a spreadsheet, document or slide:
#* Natural Earth land and state lines under the map, the collections, the
#* name, a legend and the source. Excel shows it with =IMAGE(url).
#* @param algorithm maxnet, xgboost, rf or esm; the taxon's main map when left out
#* @param width 600, 900, 1200 (default) or 1600 pixels
#* @param points 0 to leave out the collections
#* @get /api/taxa/<name>/image.png
function(name, algorithm = "", width = "1200", points = "1", res) {
  decoded <- atlas_decode_name(name)
  row <- atlas_taxon_row(cached_taxa(), decoded)
  chosen <- atlas_image_algorithm(decoded, algorithm)
  if (is.null(row) || is.null(chosen)) {
    res$status <- if (is.null(row)) 404L else 400L
    return(res)
  }
  width <- as.integer(width)
  width <- if (is.na(width)) 1200L else ATLAS_IMAGE_WIDTHS[[which.min(abs(ATLAS_IMAGE_WIDTHS - width))]]
  show_points <- !identical(points, "0")
  metrics_path <- atlas_model_path(decoded, "draft", ".json", chosen)
  metrics <- if (file.exists(metrics_path)) jsonlite::fromJSON(metrics_path, simplifyVector = FALSE) else NULL
  if (!is.null(metrics)) metrics$algorithm <- chosen
  source <- cached_cells_source()
  cells <- atlas_taxon_cells(decoded, source$occurrences, source$public)
  # Drawn once per map version, size and choice; a later request reads the file.
  key <- digest::digest(list(decoded, chosen, metrics$map_drawn_at %||% metrics$built_at,
                             width, show_points, nrow(cells), sum(cells$records)))
  dir <- file.path(tempdir(), "atlas-images")
  dir.create(dir, showWarnings = FALSE)
  path <- file.path(dir, paste0(key, ".png"))
  if (!file.exists(path)) {
    atlas_write_map_image(path, decoded, metrics, atlas_model_path(decoded, "draft", ".png", chosen),
                          cells, records = row$records, width = width, points = show_points,
                          site = site_origin)
  }
  res$status <- 200L
  res$setHeader("Content-Type", "image/png")
  res$body <- readBin(path, "raw", file.info(path)$size)
  res
}

#* Where a taxon has been collected, aggregated to the public grid.
#* @get /api/taxa/<name>/cells
#* @serializer unboxedJSON
function(name) {
  decoded <- atlas_decode_name(name)
  source <- cached_cells_source()
  cells <- atlas_taxon_cells(decoded, source$occurrences, source$public)
  list(name = decoded, degrees = ATLAS_PUBLIC_DEGREES, cells = cells)
}

# ---- states and provinces ----------------------------------------------------

# Every taxon by state, province and territory: built from the pull where this
# machine has it, read from the release everywhere else.
cached_regions <- function() {
  if (is.null(cache$regions)) {
    source <- cached_cells_source()
    cache$regions <- if (!is.null(source$occurrences)) {
      atlas_region_table(source$occurrences)
    } else {
      atlas_read_public_regions()
    }
  }
  cache$regions
}

# Recorded and predicted together (R/predictions.R): the record table, and
# what every map that beat its null models says about each state. Rebuilt
# when the model index has read new files, looked at once every few minutes.
cached_region_status <- function() {
  recorded <- cached_regions()
  if (is.null(recorded)) return(NULL)
  now <- as.numeric(Sys.time())
  if (is.null(cache$region_status) || now - (cache$region_status_checked %||% 0) > 300) {
    if (is.null(cache$models_draft)) cache$models_draft <- new.env(parent = emptyenv())
    atlas_model_index("draft", cache$models_draft)
    reads <- cache$models_draft$reads %||% 0L
    if (is.null(cache$region_status) || !identical(cache$region_status_reads, reads)) {
      predictions <- atlas_region_predictions(atlas_model_region_rows(cache$models_draft))
      cache$region_status <- atlas_region_status(recorded, predictions)
      cache$region_mapped <- unique(predictions$taxon)
      cache$region_status_reads <- reads
    }
    cache$region_status_checked <- now
  }
  cache$region_status
}

# Built at boot: from the pull it takes several seconds, and plumber answers
# one request at a time.
invisible(tryCatch(cached_region_status(), error = function(e) NULL))

NO_REGIONS <- "no region table on this server yet"

#* Every state, province and territory with validated records, with how many
#* taxa each holds and how many more its maps call likely.
#* @get /api/regions
#* @serializer unboxedJSON
function(res) {
  table <- cached_region_status()
  if (is.null(table)) {
    res$status <- 503L
    return(list(error = NO_REGIONS))
  }
  list(regions = atlas_regions_summary(table))
}

#* Where one taxon has been recorded, and where its maps say it is likely,
#* by state, province or territory.
#* @get /api/taxa/<name>/regions
#* @serializer unboxedJSON
function(name, res) {
  decoded <- atlas_decode_name(name)
  table <- cached_region_status()
  if (is.null(table)) {
    res$status <- 503L
    return(list(error = NO_REGIONS))
  }
  rows <- atlas_checklist(table, taxon = decoded)
  list(
    name = decoded,
    mapped = decoded %in% cache$region_mapped,
    min_share = ATLAS_REGION_MIN_SHARE,
    regions = rows[, c("country", "region", "code", "records", "localities",
                       "model", "suitable_share", "reach_share"), drop = FALSE]
  )
}

#* Taxa by state or province as a CSV that opens in Excel: everything, one
#* region, one country, or one taxon. Recorded taxa, and those the maps call
#* likely without a record yet.
#* @param region A region code such as US-IN or CA-BC, its name, or a country code (US, CA, MX)
#* @param taxon An exact scientific name
#* @get /api/checklist.csv
function(region = "", taxon = "", res) {
  table <- cached_region_status()
  if (is.null(table)) {
    return(atlas_send(res, list(status = 503L, body = list(error = NO_REGIONS))))
  }
  taxon <- atlas_decode_name(taxon)
  rows <- atlas_checklist(table, region, taxon)
  if (is.null(rows)) {
    return(atlas_send(res, list(status = 404L, body = list(error = "no such state, province or country in the records"))))
  }
  res$status <- 200L
  res$setHeader("Content-Type", "text/csv; charset=utf-8")
  res$setHeader("Content-Disposition",
                paste0("attachment; filename=\"", atlas_checklist_filename(region, taxon), "\""))
  res$body <- atlas_checklist_csv(rows, site_origin)
  res
}
