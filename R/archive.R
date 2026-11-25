# Archives: releases and layers deposited on Zenodo, versioned, with DOIs.
#
# Two series per grid, each one Zenodo record with many versions:
#
#   models-<grid>   the maps, scores, counts and collection cells of one
#                   release. A new version when a release is archived.
#   layers-<grid>   the predictor rasters every model was fitted on. A new
#                   version only when a layer is rebuilt, so the 2 GB stack is
#                   not deposited again with every release.
#
# Each version has its own DOI, fixed to exactly those files; the record's
# concept DOI always resolves to the newest. A models version names the
# layers version it was fitted on, so a map can be traced to its inputs.
#
# Which release went to which DOI is kept in a ledger in the store,
# archives/<series>.json, pulled with releases so the API can list downloads.
# Sandbox archives keep a separate ledger (series name ending -sandbox) and
# never mix with real DOIs.
#
# A run leaves a draft on Zenodo unless told to publish: publishing mints the
# DOI and can never be undone, so the draft can be checked on zenodo.org
# first. An unchanged release or layer build is never deposited twice.

ATLAS_ARCHIVE_KINDS <- c("models", "layers")

#' The series name: models-production, layers-draft-sandbox, ...
atlas_archive_series <- function(kind, grid, target = "zenodo") {
  kind <- match.arg(kind, ATLAS_ARCHIVE_KINDS)
  paste0(kind, "-", grid, if (identical(target, "sandbox")) "-sandbox" else "")
}

atlas_archive_ledger_key <- function(series) paste0("archives/", series, ".json")

#' The ledger for a series, or an empty one.
atlas_archive_ledger <- function(store, series) {
  key <- atlas_archive_ledger_key(series)
  if (!is.null(store) && store$exists(key)) {
    return(atlas_store_text(store, key))
  }
  # Fields appear once known: JSON has no NULL, and an empty one would read back as {}.
  list(series = series, versions = list())
}

#' Save a ledger to the store and to this machine, where the API reads it.
atlas_archive_save_ledger <- function(store, ledger) {
  atlas_store_json(store, atlas_archive_ledger_key(ledger$series), ledger)
  atlas_write_json(ledger, atlas_path("archives", paste0(ledger$series, ".json")))
  invisible(ledger)
}

#' Every ledger this machine holds, for the API: without the drafts a person
#' deleted on zenodo.org, which the ledger keeps as discarded, and without the
#' description each draft was given, which only the read-back before
#' publishing needs (R/autopublish.R).
atlas_archive_ledgers <- function() {
  files <- list.files(atlas_path("archives"), pattern = "[.]json$", full.names = TRUE)
  lapply(sort(files), function(file) {
    ledger <- jsonlite::fromJSON(file, simplifyVector = FALSE)
    kept <- Filter(function(v) !identical(v$state, "discarded"), ledger$versions %||% list())
    ledger$versions <- lapply(kept, function(v) {
      v$description <- NULL
      v
    })
    ledger
  })
}

#' The layers version a release was fitted on: the one archived from the same
#' layer builds, whatever its state, or NULL when those layers are not archived.
atlas_archive_layers_for <- function(store, grid, layers_key, target = "zenodo") {
  if (is.null(layers_key)) return(NULL)
  ledger <- atlas_archive_ledger(store, atlas_archive_series("layers", grid, target))
  match <- Filter(function(v) identical(v$key, layers_key), ledger$versions)
  if (length(match)) match[[length(match)]] else NULL
}

#' The newest published version in a ledger, or NULL.
atlas_archive_latest <- function(ledger) {
  published <- Filter(function(v) identical(v$state, "published"), ledger$versions)
  if (length(published)) published[[length(published)]] else NULL
}

# ---- bundles -------------------------------------------------------------

#' Write a tar of files, named inside as given, from a root folder.
atlas_archive_tar <- function(tarfile, root, files, compression = "none") {
  old <- setwd(root)
  on.exit(setwd(old), add = TRUE)
  utils::tar(tarfile, files = files, compression = compression, tar = "internal")
  tarfile
}

atlas_archive_checksums <- function(dir, sources) {
  sums <- vapply(unname(sources), atlas_sha256, character(1), USE.NAMES = FALSE)
  writeLines(paste0(sums, "  ", names(sources)), file.path(dir, "CHECKSUMS.sha256"))
  sums
}

#' The files of a bundle, with sizes and hashes. sources maps the name a file
#' has on Zenodo to where it is on this machine.
atlas_archive_file_table <- function(sources) {
  full <- unname(sources)
  data.frame(
    name = names(sources),
    path = full,
    bytes = file.info(full)$size,
    sha256 = vapply(full, atlas_sha256, character(1), USE.NAMES = FALSE),
    stringsAsFactors = FALSE
  )
}

#' Which algorithm a published model path belongs to, or NA. The combined
#' maps (models/<grid>/ensemble/) count as their own, "ensemble".
atlas_archive_algorithm <- function(path, grid) {
  prefix <- paste0("models/", grid, "/")
  if (!startsWith(path, prefix)) return(NA_character_)
  rest <- substring(path, nchar(prefix) + 1L)
  if (!grepl("/", rest, fixed = TRUE)) return("maxnet")
  sub("/.*$", "", rest)
}

# Release files the models bundle leaves out on purpose: path patterns, each
# named with why. Everything else a release publishes goes into some bundle
# file, or the bundle is not built (atlas_archive_plan).
ATLAS_ARCHIVE_EXCLUDE <- c(
  "a model's dissimilarity index (.di.tif, .full.di.tif) stays with the release, for privacy; the bundle carries its 0/1 area-of-applicability mask (.aoa.tif, .full.aoa.tif) instead" =
    "[.]di[.]tif$"
)

#' The 0/1 area-of-applicability mask a bundle carries in place of a model's
#' dissimilarity index: 1 where the index is at or below the model's
#' threshold, 0 where it is above, NA where the map has no cell.
atlas_aoa_mask <- function(index, threshold) {
  mask <- terra::ifel(index <= threshold, 1L, 0L)
  names(mask) <- "aoa"
  mask
}

#' Where a model's mask goes, beside its index: <taxon>.aoa.tif for
#' <taxon>.di.tif, <taxon>.full.aoa.tif for <taxon>.full.di.tif.
atlas_aoa_mask_path <- function(index_path) {
  sub("[.]di[.]tif$", ".aoa.tif", index_path)
}

#' The scores a model's index belongs to, whose applicability threshold its
#' mask is cut at.
atlas_aoa_scores_path <- function(index_path) {
  sub("([.]full)?[.]di[.]tif$", ".json", index_path)
}

#' Write the mask of every index a release holds into the tree a bundle is
#' packed from, cut at each model's own threshold (its scores'
#' applicability$threshold). Returns the release paths of the masks written,
#' with attr(, "unmasked") the indexes left without one because their model
#' keeps no threshold. Nothing is refitted: an existing release gets its masks
#' from the indexes it already holds.
atlas_archive_write_masks <- function(tree, paths) {
  indexes <- paths[grepl("[.]di[.]tif$", paths)]
  written <- character()
  unmasked <- character()
  for (path in indexes) {
    scores <- file.path(tree, atlas_aoa_scores_path(path))
    threshold <- if (file.exists(scores)) {
      as.numeric(jsonlite::fromJSON(scores, simplifyVector = FALSE)$applicability$threshold %||% NA)
    } else {
      NA_real_
    }
    if (length(threshold) != 1L || !is.finite(threshold)) {
      unmasked <- c(unmasked, path)
      next
    }
    out <- atlas_aoa_mask_path(path)
    file <- file.path(tree, out)
    terra::writeRaster(atlas_aoa_mask(terra::rast(file.path(tree, path)), threshold), file,
                       overwrite = TRUE, datatype = "INT1U", NAflag = 255,
                       gdal = c("COMPRESS=DEFLATE", "TILED=YES"))
    # A side file would be a stray file in the bundle, and could make the same
    # release pack to other bytes.
    unlink(paste0(file, ".aux.xml"))
    written <- c(written, out)
  }
  structure(written, unmasked = unmasked)
}

#' Where each of a release's files goes in the models bundle: maps per
#' algorithm (the combined maps as "ensemble"), every model's scores, single
#' files under public names, and the Explore index (converted). Stops, naming
#' them, if any path is private or fits nowhere: a file is never left out
#' silently, and nothing private is ever archived.
atlas_archive_plan <- function(paths, grid = "draft", exclude = ATLAS_ARCHIVE_EXCLUDE) {
  paths <- as.character(paths)
  private <- paths[grepl("(^|/)private/", paths)]
  if (length(private)) {
    stop("a release lists private files, which are never archived: ", paste(utils::head(private, 5), collapse = ", "),
         call. = FALSE)
  }
  # What is left out is decided first, so nothing left out is packed.
  excluded <- character()
  for (pattern in exclude) excluded <- c(excluded, paths[grepl(pattern, paths)])
  placed <- character()
  tars <- list()
  algorithms <- vapply(paths, atlas_archive_algorithm, character(1), grid = grid)
  known <- c(names(ATLAS_ALGORITHMS), "ensemble")
  for (algorithm in known) {
    mine <- paths[algorithms %in% algorithm & grepl("[.](tif|png)$", paths) & !paths %in% excluded]
    if (!length(mine)) next
    tars[[paste0("maps-", algorithm, ".tar")]] <- list(paths = mine, compression = "none")
    placed <- c(placed, mine)
  }
  # Every model's scores and settings, all algorithms and the combined maps',
  # in one small archive.
  scores <- paths[algorithms %in% known & grepl("[.]json$", paths)]
  if (length(scores)) {
    tars[["scores.tar.gz"]] <- list(paths = scores, compression = "gzip")
    placed <- c(placed, scores)
  }
  singles <- c(
    "occurrences/taxa-latest.json" = "taxa.json",
    "occurrences/renames.json" = "renames.json",
    "occurrences/name-merges.json" = "name-merges.json",
    "public/cells.tsv.gz" = "collection-cells-0.1deg.tsv.gz",
    "public/regions.tsv.gz" = "taxa-by-state-province.tsv.gz",
    "public/unvalidated.tsv.gz" = "taxa-not-yet-validated.tsv.gz",
    "public/pull.json" = "pull.json"
  )
  singles[[paste0("layers/", grid, "/manifest.json")]] <- "layers-manifest.json"
  # The location prior: strong maps' ranks by 20 km cell (R/prior.R).
  for (file in ATLAS_PRIOR_FILES) singles[[paste0("prior/", grid, "/", file)]] <- paste0("prior-", file)
  for (benchmark in paths[startsWith(paths, paste0("benchmarks/", grid, "/"))]) {
    singles[[benchmark]] <- "benchmark.json"
  }
  singles <- singles[intersect(names(singles), paths)]
  placed <- c(placed, names(singles))
  here <- paste0("index/", grid, "/here.rds")
  here <- if (here %in% paths) here
  placed <- c(placed, here)
  unplaced <- setdiff(paths, c(placed, excluded))
  if (length(unplaced)) {
    stop("the models bundle has no place for ", length(unplaced), " of the release's files (",
         paste(utils::head(unplaced, 5), collapse = ", "), if (length(unplaced) > 5) ", ..." else "",
         "): give them one in atlas_archive_plan, or list them in ATLAS_ARCHIVE_EXCLUDE with why",
         call. = FALSE)
  }
  list(tars = tars, singles = as.list(singles), here = here, excluded = unique(excluded))
}

#' The Explore index (R/here.R) as a table: one row per (cell, map) with the
#' map's rank there, cell by cell. The same entries as the index, in its order.
atlas_archive_here_table <- function(index) {
  counts <- diff(as.integer(index$start))
  entries <- as.integer(index$model)
  data.frame(
    cell = rep(seq_along(counts), counts),
    taxon = as.character(index$models$taxon[entries]),
    algorithm = as.character(index$models$algorithm[entries]),
    rank = as.integer(index$rank),
    stringsAsFactors = FALSE
  )
}

#' The grid the Explore index's cells are numbered on, so a reader can place
#' them without R.
atlas_archive_here_grid <- function(index) {
  size <- index$cell_km * 1000
  list(
    grid = index$grid, cell_km = index$cell_km, min_rank = index$min_rank, built_at = index$built_at,
    crs = ATLAS_CRS, extent = as.list(ATLAS_GRID_EXTENT),
    ncol = ceiling((ATLAS_GRID_EXTENT[["xmax"]] - ATLAS_GRID_EXTENT[["xmin"]]) / size),
    nrow = ceiling((ATLAS_GRID_EXTENT[["ymax"]] - ATLAS_GRID_EXTENT[["ymin"]]) / size),
    cell = paste("cell = row * ncol + col + 1, where col = floor((x - xmin) / (cell_km * 1000)) and",
                 "row = floor((ymax - y) / (cell_km * 1000)), x and y in metres in crs"),
    rank = paste("the mean percentile rank (0-100) of the map's 5 km cells inside its area of applicability;",
                 "only ranks of min_rank or more are listed"),
    models = nrow(index$models), entries = length(index$model)
  )
}

#' Write the Explore index's table and grid into a bundle directory, and
#' return their names.
atlas_archive_write_here <- function(path, out) {
  index <- readRDS(path)
  table <- file.path(out, "explore-index-20km.tsv.gz")
  grid <- file.path(out, "explore-index-20km.json")
  atlas_write_tsv_gz(atlas_archive_here_table(index), table)
  atlas_write_json(atlas_archive_here_grid(index), grid)
  basename(c(table, grid))
}

#' Build the models bundle for one release: fetch its files from the store,
#' check each against its hash, and pack them into a handful of files, since
#' a Zenodo record holds at most 100. With blocks (the default), the bundle's
#' maps are drawn in whole 50 km blocks in its own tree (R/archiveblocks.R);
#' blocks = FALSE packs the release's maps as they are, for tests of the rest.
atlas_archive_models_bundle <- function(store, grid = "draft", release = NULL,
                                        dir = tempfile("atlas-archive-"), cells_now = NULL,
                                        blocks = TRUE, workers = 1L, quiet = TRUE) {
  manifest <- if (is.null(release)) {
    atlas_current_release(store, grid)
  } else {
    atlas_store_text(store, paste0("releases/", grid, "/", release, ".json"))
  }
  if (is.null(manifest)) stop("nothing has been published for the ", grid, " grid", call. = FALSE)

  tree <- file.path(dir, "tree")
  out <- file.path(dir, "bundle")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  paths <- vapply(manifest$files, function(f) f$path, character(1))
  for (entry in manifest$files) {
    dest <- file.path(tree, entry$path)
    dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
    # This machine usually holds the release already; the store is the fallback.
    local <- file.path(atlas_data_dir(), entry$path)
    if (!(file.exists(local) && identical(atlas_sha256(local), entry$sha256) &&
          file.copy(local, dest, overwrite = TRUE))) {
      store$get(atlas_object_key(entry$sha256), dest)
    }
    if (!identical(atlas_sha256(dest), entry$sha256)) {
      stop("the store's copy of ", entry$path, " does not match its hash", call. = FALSE)
    }
  }

  # The maps drawn in whole blocks, in the tree only, counted by state with
  # the release's own collection cells (so before the cells made now).
  trimmed <- if (isTRUE(blocks)) atlas_archive_block_tree(store, tree, manifest, grid, workers = workers,
                                                           quiet = quiet, dir = dir)

  # The cells as the sources stand now (R/cellsnow.R), in place of the
  # release's own; the release's file stays as it is.
  now <- if (!is.null(cells_now)) atlas_read_cells_now(cells_now, manifest)
  if (!is.null(now) && !file.copy(now$path, file.path(tree, "public", "cells.tsv.gz"), overwrite = TRUE)) {
    stop("could not put the cells made now into the bundle", call. = FALSE)
  }
  release_id <- manifest$id
  files_key <- manifest$files_key

  # The archive is public; the release's own files are not, and keep what the
  # refits read (R/fingerprint.R).
  taxon_hashes <- atlas_archive_withhold(tree, paths, manifest)

  # Each model's 0/1 area-of-applicability mask, in place of its
  # dissimilarity index, which the bundle leaves out (ATLAS_ARCHIVE_EXCLUDE).
  masks <- atlas_archive_write_masks(tree, paths)
  packed <- c(paths, masks)

  # A tar records each file's time. Stamped with the release's own time, the
  # same release always packs to the same bytes, so a resumed upload can see
  # that a file already on Zenodo is the right one.
  stamp <- as.POSIXct(manifest$created_at %||% "2000-01-01T00:00:00Z", format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  Sys.setFileTime(file.path(tree, packed), stamp)

  plan <- atlas_archive_plan(packed, grid)
  names <- character()
  for (name in names(plan$tars)) {
    tar <- plan$tars[[name]]
    atlas_archive_tar(normalizePath(file.path(out, name), mustWork = FALSE), tree, tar$paths,
                      compression = tar$compression)
    names <- c(names, name)
  }
  for (path in names(plan$singles)) {
    file.copy(file.path(tree, path), file.path(out, plan$singles[[path]]))
    names <- c(names, plan$singles[[path]])
  }
  # The Explore index, as a table anyone can read (R/here.R keeps it as R's
  # own .rds), with the grid that places its cells.
  if (!is.null(plan$here)) {
    names <- c(names, atlas_archive_write_here(file.path(tree, plan$here), out))
  }
  manifest <- atlas_archive_public_manifest(manifest)
  if (length(plan$excluded)) {
    manifest$left_out <- list(
      files = length(plan$excluded),
      what = "each model's dissimilarity index (.di.tif, .full.di.tif)",
      why = "Kept with the release, for privacy.",
      instead = paste("each model's 0/1 area-of-applicability mask (.aoa.tif, .full.aoa.tif): 1 where the index",
                      "is at or below the model's threshold (its scores' applicability.threshold), 0 above it"),
      masks = length(masks),
      without_mask = length(attr(masks, "unmasked"))
    )
  }
  if (!is.null(trimmed)) {
    manifest$trimmed <- list(
      blocks_km = ATLAS_BLOCK_KM,
      what = paste("maps are drawn in whole 50 km blocks of a fixed grid: a block is drawn only when its whole",
                   "50 km square lies inside the accessible area"),
      scores = paste("in each model's scores, bounds and regions (counts of the trimmed map's cells by state) are",
                     "the trimmed map's; every other field, md5 among them, is the release's as published"),
      tables = "the prior and Explore tables keep the rows of 20 km cells wholly inside a map's kept blocks",
      maps = trimmed$maps, combined_maps = trimmed$ensembles
    )
  }
  atlas_write_json(manifest, file.path(out, "release.json"))
  names <- c(names, "release.json")
  atlas_archive_refuse_withheld(c(file.path(tree, paths[grepl("[.]json$", paths)]),
                                 file.path(out, names[grepl("[.]json$", names)])),
                               taxon_hashes)
  atlas_archive_refuse_left_out(file.path(out, names), plan$excluded)

  # A version made with cells made now is a new version of the same release:
  # its own name, and a key that tells it from the release's first version.
  list(
    kind = "models", grid = grid, dir = out, trimmed = trimmed,
    version = if (is.null(now)) release_id else paste0(release_id, ".", gsub("-", "", now$summary$checked_on)),
    key = if (is.null(now)) files_key else digest::digest(paste(files_key, now$summary$cells_now$sha256), algo = "sha256"),
    cells_now = now$summary,
    release = manifest, sources = stats::setNames(file.path(out, names), names)
  )
}

#' What the README says of the collection cells, word for word as approved
#' (Steve, 2026-11-07): only for a version whose cells were made now.
atlas_archive_cells_lines <- function(bundle) {
  if (is.null(bundle$cells_now)) return(character())
  km <- format(unname(ATLAS_GRID_RESOLUTIONS[[bundle$grid]]) / 1000)
  c(
    sprintf("This version holds the models of release %s unchanged. Two things differ from that release's own files: each taxon's record-set fingerprint and each model's seed are withheld for privacy, and the collection cells (`collection-cells-0.1deg.tsv.gz`) also leave out records whose source has hidden or obscured their location since the release was made, and Mushroom Observer records the source no longer holds, as the sources said on %s. `release.json` keeps the release's original checksums, so the cells file here differs from its entry there.", sub("^.*-", "", bundle$release$id), bundle$cells_now$checked_on),
    sprintf("Collection locations are given as record counts per 0.1 degree cell; the maps are on a %s km grid. Records from iNaturalist and Mushroom Observer whose location the source hides, obscures or may hide, and Mushroom Observer records the source no longer holds, are left out of the cells; records from the other sources (MyCoPortal, DNA sequence records, GenBank) are counted where recorded.", km)
  )
}

# The pull's summary keeps its fingerprint: the hash of every record at once.
ATLAS_ARCHIVE_KEEPS_FINGERPRINT <- "public/pull.json"

#' Take the private fields out of a release's JSON files in the tree a bundle is
#' packed from. Returns every per-taxon hash seen, for the check at the end.
atlas_archive_withhold <- function(tree, paths, manifest) {
  hashes <- as.character(unlist(lapply(manifest$index, function(e) e$fingerprint)))
  files <- setdiff(paths[grepl("[.]json$", paths)], ATLAS_ARCHIVE_KEEPS_FINGERPRINT)
  key <- paste0('"(', paste(ATLAS_PRIVATE_FIELDS, collapse = "|"), ')"\\s*:')
  for (path in files) {
    file <- file.path(tree, path)
    text <- readChar(file, file.info(file)$size, useBytes = TRUE)
    Encoding(text) <- "UTF-8"
    if (!grepl(key, text, perl = TRUE)) next
    found <- jsonlite::fromJSON(text, simplifyVector = FALSE)
    if (is.list(found)) {
      seen <- rapply(found, function(v) as.character(v), how = "unlist")
      seen <- seen[grepl("(^|[.])fingerprint$", names(seen))]
      hashes <- c(hashes, unname(seen))
    }
    writeBin(charToRaw(enc2utf8(atlas_public_json_text(text))), file)
  }
  unique(hashes)
}

#' The release record as archived: its model index without the private fields,
#' saying so. Its file list still gives each file as the release holds it.
atlas_archive_public_manifest <- function(manifest) {
  manifest$index <- atlas_public_fields(manifest$index)
  manifest$withheld <- list(
    fields = as.list(ATLAS_PRIVATE_FIELDS),
    from = "each model's scores, taxa.json and this file's model index",
    why = "Withheld for privacy.",
    hashes = "The files list gives each file as the release holds it, so these files' hashes differ from the archive's."
  )
  manifest
}

#' The last word before anything is uploaded: no per-taxon hash, under any field
#' name, and no seed, in any JSON the bundle holds.
atlas_archive_refuse_withheld <- function(files, hashes) {
  for (file in unique(files)) {
    if (!file.exists(file)) next
    text <- readChar(file, file.info(file)$size, useBytes = TRUE)
    tokens <- regmatches(text, gregexpr("[0-9a-f]{64}", text, useBytes = TRUE))[[1]]
    seeded <- grepl('"seed"\\s*:', text, perl = TRUE, useBytes = TRUE)
    if (any(tokens %in% hashes) || seeded) {
      stop("a per-taxon fingerprint or seed would have been archived, in ", basename(file), call. = FALSE)
    }
  }
  invisible(TRUE)
}

#' The last word on what is left out: no file the plan left out, and no
#' dissimilarity index under any name, inside any archive the bundle holds.
atlas_archive_refuse_left_out <- function(files, excluded) {
  for (file in unique(files)) {
    if (!file.exists(file) || !grepl("[.]tar([.]gz)?$", file)) next
    inside <- utils::untar(file, list = TRUE)
    bad <- inside[inside %in% excluded | grepl("[.]di[.]tif$", inside)]
    if (length(bad)) {
      stop("a file the bundle leaves out would have been archived, in ", basename(file), ": ",
           paste(utils::head(bad, 3), collapse = ", "), call. = FALSE)
    }
  }
  invisible(TRUE)
}

#' Build the layers bundle from this machine's built layers.
atlas_archive_layers_bundle <- function(grid = "draft", dir = tempfile("atlas-archive-")) {
  layer_dir <- atlas_layer_dir(grid)
  manifest_file <- file.path(layer_dir, "manifest.json")
  if (!file.exists(manifest_file)) stop("no layers are built for the ", grid, " grid", call. = FALSE)
  manifest <- atlas_layer_manifest(grid)
  out <- file.path(dir, "bundle")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  # Uploaded from where they are built: the stack is gigabytes, not worth a copy.
  rasters <- list.files(layer_dir, pattern = "[.]tif$")
  key <- atlas_layers_key(grid, manifest)
  built <- vapply(manifest, function(x) as.character(x$built_at %||% ""), character(1))
  day <- substr(max(c(built, "")), 1, 10)
  list(
    kind = "layers", grid = grid, dir = out,
    version = paste0(grid, "-", if (nzchar(day)) day else "undated", "-", substr(key, 1, 8)),
    key = key, layers = manifest,
    sources = c(stats::setNames(file.path(layer_dir, rasters), rasters),
                "layers-manifest.json" = manifest_file)
  )
}

#' Refuse a bundle Zenodo would refuse, before uploading gigabytes of it.
atlas_archive_check_size <- function(files) {
  if (nrow(files) > ATLAS_ZENODO_MAX_FILES) {
    stop(nrow(files), " files is more than Zenodo's ", ATLAS_ZENODO_MAX_FILES, " per record",
         call. = FALSE)
  }
  total <- sum(files$bytes)
  if (total > ATLAS_ZENODO_MAX_BYTES) {
    stop(sprintf("%.1f GB is more than Zenodo's 50 GB per record; split the series or ask Zenodo for a larger quota",
                 total / 1024^3), call. = FALSE)
  }
  invisible(total)
}

# ---- metadata ------------------------------------------------------------

atlas_archive_template <- function(root = Sys.getenv("ATLAS_ROOT", unset = ".")) {
  path <- file.path(root, "inst", "archive", "zenodo.json")
  if (!file.exists(path)) path <- system.file("archive", "zenodo.json", package = "mycomapatlas")
  jsonlite::fromJSON(path, simplifyVector = FALSE)
}

atlas_html_escape <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  gsub(">", "&gt;", x, fixed = TRUE)
}

#' A README for the bundle, and the same facts as the record's description.
atlas_archive_readme <- function(bundle, files, layers_version = NULL) {
  size <- function(bytes) {
    if (bytes >= 1024^3) sprintf("%.1f GB", bytes / 1024^3) else sprintf("%.1f MB", bytes / 1024^2)
  }
  lines <- c(
    paste0("# ", if (bundle$kind == "models") "MycoMap Atlas habitat models" else "MycoMap Atlas environmental predictors",
           ", ", bundle$grid, " grid"),
    "",
    paste0("Version: ", bundle$version)
  )
  if (bundle$kind == "models") {
    r <- bundle$release
    lines <- c(
      lines,
      paste0("Atlas release: ", r$id, " (", r$created_at, ")"),
      # A release read back from JSON (a kept bundle) may hold its commit as
      # an empty list: only a single string is a commit.
      paste0("Code: https://github.com/BiodiverseLabs/mycomap-atlas",
             if (!is.null(commit <- atlas_json_string(r$commit)) && !is.na(commit)) paste0("/tree/", commit) else ""),
      paste0("Records: ", r$pull$records %||% "?", " DNA-validated collections, ", r$pull$taxa %||% "?",
             " taxa, pulled ", r$pull$pulled_at %||% "?", ", fingerprint ", r$pull$fingerprint %||% "?"),
      paste0("Models: ", paste(sprintf("%s %s", names(r$models), unlist(r$models)), collapse = ", ")),
      if (!is.null(layers_version)) paste0("Fitted on predictors: ", layers_version$version,
                                           if (!is.null(layers_version$doi)) paste0(" (doi:", layers_version$doi, ")") else "")
    )
  }
  lines <- c(
    lines, "",
    "## Files", "",
    paste0("- `", files$name, "` (", vapply(files$bytes, size, character(1)), ")"),
    "- `CHECKSUMS.sha256`: SHA-256 of every file above; check with `sha256sum -c CHECKSUMS.sha256`.",
    ""
  )
  if (bundle$kind == "models") {
    lines <- c(
      lines,
      "`maps-<model>.tar` holds, per taxon, the raw suitability raster (`.tif`) and its area-of-applicability",
      "mask (`.aoa.tif`: 1 where the model's conditions resemble its training sites, at or below its threshold,",
      "0 where they do not), both GeoTIFF on North America Albers Equal Area inside the 500 km accessible area,",
      "and the drawn map (PNG, Web Mercator, coloured by percentile); for strong models, the same three beyond",
      "500 km (`.full.*`). The threshold is in each model's scores (`applicability.threshold`). The dissimilarity",
      "index itself is kept with the release and not archived. The models are Maxent (`maxnet`), random forest",
      "(`rf`), boosted trees (`xgboost`) and ensembles of small models (`esm`).",
      "`maps-ensemble.tar` holds the combined maps: each taxon's passing models together, and where they disagree.",
      "`scores.tar.gz` holds each model's scores on every spatial fold, predictors and settings.",
      "Each taxon's record-set fingerprint and each model's seed are withheld for privacy, from these files and",
      "`taxa.json`. `release.json` says so under `withheld`.",
      "`explore-index-20km.tsv.gz` is the Explore index: for each 20 km cell, every strong map's rank there",
      "(cell, taxon, algorithm, rank); `explore-index-20km.json` gives its grid and how to place a cell.",
      "`renames.json` lists names changed since earlier pulls; `name-merges.json` the spellings merged into one name.",
      "`prior-*` is the location prior: every strong map's ranks by 20 km cell (`prior-ranks.parquet`,",
      "`prior-ranks.tsv.gz`), its taxa (`prior-taxa.tsv`), and the grid with a Python cell lookup (`prior-grid.json`).",
      atlas_archive_cells_lines(bundle),
      atlas_archive_tables_lines(bundle),
      ""
    )
  } else {
    lines <- c(
      lines,
      "Each GeoTIFF is one group of predictors on the Atlas grid (North America Albers Equal Area).",
      "`layers-manifest.json` lists every band with its source, licence, cell size and checksum.",
      "Sources: WorldClim 2.1 (CC BY-SA 4.0), SoilGrids 2.0 (CC BY 4.0), ESA WorldCover 2021 (CC BY 4.0).",
      # The Open Government Licence - Canada asks for this attribution wherever
      # NFI-derived data goes.
      if (any(c("hosts", "hostsdecay", "hostspecies") %in%
              vapply(bundle$layers %||% list(), function(x) as.character(x$id %||% ""), character(1)))) {
        paste("Host trees: USFS FIA BIGMAP 2018 (US public domain); contains information licensed",
              "under the Open Government Licence - Canada (NFI kNN 2011, Natural Resources Canada).")
      },
      ""
    )
  }
  c(lines, "Method: https://atlas.mycomap.org/methods", "Sources and licences: https://atlas.mycomap.org/sources")
}

#' The Zenodo metadata for one version.
atlas_archive_metadata <- function(bundle, readme, template = atlas_archive_template(),
                                   layers_version = NULL, today = Sys.Date()) {
  common <- template$common
  own <- template[[bundle$kind]]
  fill <- function(x) gsub("{grid}", bundle$grid, x, fixed = TRUE)
  related <- c(common$related_identifiers, own$related_identifiers)
  if (!is.null(layers_version$doi)) {
    related <- c(related, list(list(identifier = layers_version$doi, relation = "isDerivedFrom", scheme = "doi")))
  }
  body <- readme[!startsWith(readme, "# ")]
  description <- paste0(
    "<p>", atlas_html_escape(fill(own$summary)), "</p>",
    "<pre>", atlas_html_escape(paste(body, collapse = "\n")), "</pre>"
  )
  metadata <- list(
    upload_type = common$upload_type,
    title = fill(own$title),
    creators = common$creators,
    description = description,
    access_right = common$access_right,
    license = common$license,
    keywords = common$keywords,
    version = bundle$version,
    publication_date = format(today, "%Y-%m-%d"),
    related_identifiers = related
  )
  if (length(common$communities)) metadata$communities <- common$communities
  metadata
}

# ---- archiving -----------------------------------------------------------

#' Deposit a bundle as the next version of its series.
#'
#' Leaves a draft unless publish = TRUE. Skips a bundle whose key matches the
#' newest published version, and refuses while an earlier draft is still
#' waiting, so two drafts never compete for the next version.
atlas_archive_deposit <- function(bundle, store, z, publish = FALSE, dry_run = FALSE,
                                  template = atlas_archive_template(), quiet = FALSE,
                                  resume_draft = NULL) {
  say <- function(...) if (!isTRUE(quiet)) message(...)
  if (identical(bundle$kind, "models") && is.null(bundle$cells_now) && !isTRUE(dry_run)) {
    stop("a models version needs its collection cells made as the sources stand now: ",
         "run cells-now on the machine that holds the pull, then archive with --cells-now", call. = FALSE)
  }
  series <- atlas_archive_series(bundle$kind, bundle$grid, z$target)
  ledger <- atlas_archive_ledger(store, series)

  waiting <- Filter(function(v) identical(v$state, "draft"), ledger$versions)
  if (length(waiting)) {
    stop("version ", waiting[[1]]$version, " of ", series, " is still a draft at ", waiting[[1]]$url,
         ": publish it with archive-publish, or discard it with archive-discard", call. = FALSE)
  }
  latest <- atlas_archive_latest(ledger)
  if (!is.null(latest) && identical(latest$key, bundle$key)) {
    say(series, ": nothing changed since version ", latest$version, " (doi:", latest$doi, "); not archiving")
    return(invisible(ledger))
  }

  readme_path <- file.path(bundle$dir, "README.md")
  layers_version <- if (bundle$kind == "models") {
    atlas_archive_layers_for(store, bundle$grid, bundle$release$layers_key, z$target)
  }
  # The README lists the files; the checksums then cover the README too.
  files <- atlas_archive_file_table(bundle$sources)
  writeLines(atlas_archive_readme(bundle, files, layers_version), readme_path)
  sources <- c(bundle$sources, "README.md" = readme_path)
  atlas_archive_checksums(bundle$dir, sources)
  files <- atlas_archive_file_table(c(sources, "CHECKSUMS.sha256" = file.path(bundle$dir, "CHECKSUMS.sha256")))
  total <- atlas_archive_check_size(files)
  metadata <- atlas_archive_metadata(bundle, readLines(readme_path), template, layers_version)

  if (isTRUE(dry_run)) {
    say(series, " version ", bundle$version, ": ", nrow(files), " files, ",
        sprintf("%.2f GB", total / 1024^3), " -> ", z$target,
        if (is.null(latest)) " (a new record)" else paste0(" (a new version after ", latest$version, ")"))
    for (i in seq_len(nrow(files))) say(sprintf("  %-34s %10.1f MB", files$name[i], files$bytes[i] / 1048576))
    return(invisible(list(ledger = ledger, files = files, metadata = metadata)))
  }

  # An upload that stopped part way leaves its draft in the ledger as
  # uploading: carry on in that draft rather than start a second record.
  unfinished <- Filter(function(v) identical(v$state, "uploading"), ledger$versions)
  if (length(unfinished) && !identical(unfinished[[1]]$key, bundle$key)) {
    stop("an unfinished upload of version ", unfinished[[1]]$version, " of ", series,
         " is on Zenodo at ", unfinished[[1]]$url, "; discard it with archive-discard first",
         call. = FALSE)
  }
  resume_id <- if (length(unfinished)) unfinished[[1]]$deposition_id else resume_draft
  draft <- if (!is.null(resume_id)) {
    found <- z$call("GET", paste0("/deposit/depositions/", resume_id))
    if (isTRUE(found$submitted)) stop("Zenodo record ", resume_id, " is already published", call. = FALSE)
    say(series, ": carrying on in the unfinished draft ", resume_id)
    found
  } else if (is.null(latest)) {
    atlas_zenodo_create(z)
  } else {
    atlas_zenodo_new_version(z, latest$deposition_id)
  }

  # The MD5 is Zenodo's own checksum: what a draft is read back against
  # before it publishes itself (atlas_archive_auto_publish).
  md5 <- vapply(files$path, function(p) digest::digest(file = p, algo = "md5"), character(1), USE.NAMES = FALSE)
  entry <- list(
    version = bundle$version,
    key = bundle$key,
    release = if (bundle$kind == "models") bundle$release$id else NULL,
    layers_version = layers_version$version,
    deposition_id = draft$id,
    url = draft$links$html %||% paste0(sub("/api$", "", z$base), "/deposit/", draft$id),
    state = "uploading",
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    bytes = total,
    # What the draft was given, word for word, so a change made on zenodo.org
    # afterwards is seen before anything publishes.
    title = metadata$title,
    description = metadata$description,
    files = lapply(seq_len(nrow(files)), function(i) {
      list(name = files$name[i], bytes = files$bytes[i], sha256 = files$sha256[i], md5 = md5[i])
    })
  )
  entry <- Filter(Negate(is.null), entry)
  # Written before a byte is uploaded, so a run that dies leaves a draft
  # the next run knows about, never one only Zenodo knows about.
  index <- which(vapply(ledger$versions, function(v) identical(v$state, "uploading"), logical(1)))
  index <- if (length(index)) index[[1]] else length(ledger$versions) + 1L
  ledger$versions[[index]] <- entry
  atlas_archive_save_ledger(store, ledger)

  atlas_zenodo_sync_files(z, draft, files, say)
  atlas_zenodo_set_metadata(z, draft$id, metadata)

  ledger$versions[[index]]$state <- "draft"
  # The grace period before it publishes itself runs from here.
  ledger$versions[[index]]$drafted_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  atlas_archive_save_ledger(store, ledger)
  say(series, " version ", bundle$version, ": draft ready at ", entry$url)

  if (isTRUE(publish)) {
    ledger <- atlas_archive_publish(store, series, z, quiet = quiet)
  }
  invisible(ledger)
}

#' Publish the waiting draft of a series: mints its DOI, permanently.
atlas_archive_publish <- function(store, series, z, quiet = FALSE) {
  ledger <- atlas_archive_ledger(store, series)
  index <- which(vapply(ledger$versions, function(v) identical(v$state, "draft"), logical(1)))
  if (!length(index)) stop(series, " has no draft waiting to be published", call. = FALSE)
  index <- index[[1]]
  entry <- ledger$versions[[index]]
  record <- atlas_zenodo_publish(z, entry$deposition_id)
  entry$state <- "published"
  entry$doi <- record$doi
  entry$record_id <- record$record_id %||% record$id
  entry$url <- record$links$html %||% entry$url
  entry$published_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  ledger$versions[[index]] <- entry
  ledger$concept_doi <- record$conceptdoi %||% ledger$concept_doi
  ledger$concept_recid <- record$conceptrecid %||% ledger$concept_recid
  atlas_archive_save_ledger(store, ledger)
  if (!isTRUE(quiet)) {
    message(series, " version ", entry$version, " published: doi:", entry$doi,
            " (all versions: doi:", ledger$concept_doi, ")")
  }
  invisible(ledger)
}

#' Throw away the waiting draft of a series.
atlas_archive_discard <- function(store, series, z, quiet = FALSE) {
  ledger <- atlas_archive_ledger(store, series)
  index <- which(vapply(ledger$versions, function(v) v$state %in% c("draft", "uploading"), logical(1)))
  if (!length(index)) stop(series, " has no draft to discard", call. = FALSE)
  entry <- ledger$versions[[index[[1]]]]
  atlas_zenodo_discard(z, entry$deposition_id)
  ledger$versions <- ledger$versions[-index[[1]]]
  atlas_archive_save_ledger(store, ledger)
  if (!isTRUE(quiet)) message(series, ": discarded the draft of version ", entry$version)
  invisible(ledger)
}

#' Archive a release, the layers, or both, as the next versions of their series.
#'
#' keep_bundle builds only: the models bundle is kept in that directory with
#' its checksums (atlas_archive_keep_bundle) and nothing goes to Zenodo.
#' from_bundle deposits a bundle kept that way instead of building one, with
#' cells_now, when given, in place of the release's cells. tables adds the
#' training-record and lineage tables made by training-tables
#' (R/trainingtables.R), for the release they are made for only.
atlas_archive <- function(store, grid = "draft", kinds = ATLAS_ARCHIVE_KINDS, release = NULL,
                          z, publish = FALSE, dry_run = FALSE, quiet = FALSE, resume_draft = NULL,
                          cells_now = NULL, blocks = TRUE, workers = 1L, keep_bundle = NULL, from_bundle = NULL,
                          tables = NULL) {
  if (!is.null(keep_bundle) && !identical(as.character(kinds), "models")) {
    stop("a kept bundle is a models bundle: pass --only=models with --keep-bundle", call. = FALSE)
  }
  # Layers first: a models version records which layers version it was fitted on.
  for (kind in intersect(c("layers", "models"), kinds)) {
    bundle <- if (kind == "layers") {
      atlas_archive_layers_bundle(grid)
    } else if (!is.null(from_bundle)) {
      kept <- atlas_archive_read_kept_bundle(from_bundle)
      if (is.null(cells_now)) kept else atlas_archive_bundle_cells_now(kept, cells_now)
    } else {
      atlas_archive_models_bundle(store, grid, release, cells_now = cells_now, blocks = blocks,
                                  workers = workers, quiet = quiet)
    }
    if (is.null(from_bundle)) on.exit(unlink(dirname(bundle$dir), recursive = TRUE), add = TRUE)
    if (kind == "models" && !is.null(tables)) bundle <- atlas_archive_bundle_tables(bundle, tables)
    if (!is.null(keep_bundle)) {
      atlas_archive_keep_bundle(bundle, keep_bundle)
      if (!isTRUE(quiet)) message("models bundle for ", bundle$version, " kept in ", keep_bundle, "; nothing deposited")
      next
    }
    atlas_archive_deposit(bundle, store, z, publish = publish, dry_run = dry_run, quiet = quiet,
                          resume_draft = resume_draft)
  }
  invisible(TRUE)
}

#' A kept bundle with the cells made now (atlas_read_cells_now) in place of
#' the release's own, as a bundle built with them is: its cells file is
#' theirs, and its version, key and README say so. Only the cells file
#' differs, since a bundle's maps and their counts by state are made with
#' the release's own cells either way. The kept files are left as they are.
atlas_archive_bundle_cells_now <- function(bundle, cells_now) {
  if (!is.null(bundle$cells_now)) {
    stop("the kept bundle already holds cells made on ", bundle$cells_now$checked_on %||% "?", call. = FALSE)
  }
  now <- atlas_read_cells_now(cells_now, bundle$release)
  name <- "collection-cells-0.1deg.tsv.gz"
  entry <- Filter(function(f) identical(f$path, "public/cells.tsv.gz"), bundle$release$files %||% list())
  if (!name %in% names(bundle$sources) || !length(entry) ||
      !identical(atlas_sha256(bundle$sources[[name]]), entry[[1]]$sha256)) {
    stop("the kept bundle's cells file is not release ", bundle$release$id, "'s own", call. = FALSE)
  }
  bundle$sources[[name]] <- now$path
  bundle$cells_now <- now$summary
  bundle$version <- paste0(bundle$release$id, ".", gsub("-", "", now$summary$checked_on))
  bundle$key <- digest::digest(paste(bundle$key, now$summary$cells_now$sha256), algo = "sha256")
  bundle
}

#' Keep a built bundle in dir: its files, SHA256SUMS of them, and
#' bundle.json, which says what atlas_archive_read_kept_bundle needs to
#' deposit it later.
atlas_archive_keep_bundle <- function(bundle, dir) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  if (length(list.files(dir))) stop(dir, " is not empty: a bundle is kept in an empty directory", call. = FALSE)
  for (name in names(bundle$sources)) {
    if (!file.copy(bundle$sources[[name]], file.path(dir, name))) stop("could not keep ", name, call. = FALSE)
  }
  sums <- vapply(names(bundle$sources), function(n) atlas_sha256(file.path(dir, n)), "")
  writeLines(paste0(sums, "  ", names(sums)), file.path(dir, "SHA256SUMS"), useBytes = TRUE)
  keep <- bundle[setdiff(names(bundle), c("dir", "sources"))]
  keep$files <- as.list(names(bundle$sources))
  atlas_write_json(keep, file.path(dir, "bundle.json"))
  invisible(dir)
}

#' A bundle kept by atlas_archive_keep_bundle, each file checked against its
#' SHA256SUMS line before it is used.
atlas_archive_read_kept_bundle <- function(dir) {
  meta <- jsonlite::fromJSON(file.path(dir, "bundle.json"), simplifyVector = FALSE)
  sums <- readLines(file.path(dir, "SHA256SUMS"), warn = FALSE)
  listed <- stats::setNames(sub("  .*$", "", sums), sub("^[0-9a-f]+  ", "", sums))
  files <- unlist(meta$files)
  if (!setequal(names(listed), files)) stop("the kept bundle's SHA256SUMS does not list its files", call. = FALSE)
  for (name in files) {
    if (!identical(atlas_sha256(file.path(dir, name)), listed[[name]])) {
      stop("the kept bundle's ", name, " does not match its SHA256SUMS", call. = FALSE)
    }
  }
  # A field kept as null is written as {} and read back as an empty list:
  # read back as null, so a bundle kept without cells made now is still one.
  meta <- lapply(meta, function(v) if (is.list(v) && !length(v)) NULL else v)
  meta <- meta[!vapply(meta, is.null, logical(1))]
  c(meta[setdiff(names(meta), "files")], list(dir = dir, sources = stats::setNames(file.path(dir, files), files)))
}
