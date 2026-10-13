# What sequence names change (paper E9): the atlas names a record by its
# approved DNA sequence, not by the name its observer gave it. How different
# are the maps under the record's own name?
#
# The record-name release is built by the private-release job with
# --record-names (the method lane's hindcast job kind): the frozen pull's
# records relabelled by their own name with production's spelling merges,
# and every taxon whose record set changes fitted and graded in full. This
# file only compares. For each taxon and learner the two releases share, the
# maps are compared over the cells both cover: Spearman's rank correlation,
# and Schoener's D on suitability normalised to sum to one (Warren et al.
# 2008); and the grades are set side by side. The two pulls give the label
# accounting: how each record's label differs, by source, and which taxa
# split, merge, appear or vanish.
#
# Nothing here writes a model or a release: one results file under
# data/compare-studies/<grid>/.

#' A record's key in a pull: source and observation.
atlas_e9_keys <- function(occurrences) {
  paste(occurrences$source, occurrences$observation_id, sep = ":")
}

#' The record-name pull's labels in the DNA pull's row order, matched by
#' record key; a record the record-name pull does not hold gets NA.
atlas_e9_align <- function(dna, record) {
  as.character(record$scientific_name)[match(atlas_e9_keys(dna), atlas_e9_keys(record))]
}

#' Whether a label can be a taxon: present and species level.
atlas_e9_modelled <- function(labels) {
  !is.na(labels) & atlas_species_level(labels)
}

#' How each record's label differs between the two namings: "same",
#' "spelling" (one taxon, another spelling), "species" (another species of
#' the same genus), "genus" (another genus) or "no_taxon" (no species-level
#' name of its own), by source.
atlas_e9_label_changes <- function(dna, record) {
  a <- as.character(dna$scientific_name)
  b <- atlas_e9_align(dna, record)
  genus <- function(x) tolower(sub(" .*$", "", x))
  kind <- ifelse(!atlas_e9_modelled(b), "no_taxon",
                 ifelse(a == b, "same",
                        ifelse(atlas_name_key(a) == atlas_name_key(b), "spelling",
                               ifelse(genus(a) == genus(b), "species", "genus"))))
  table <- as.data.frame(table(source = dna$source, change = factor(kind, levels = c(
    "same", "spelling", "species", "genus", "no_taxon"))), stringsAsFactors = FALSE)
  names(table)[names(table) == "Freq"] <- "records"
  list(per_record = kind, by_source = table)
}

#' How the taxa change: split (a DNA taxon whose records go to two or more
#' record-name taxa), merged (a record-name taxon fed by two or more DNA
#' taxa), gained and lost (names under one labelling only).
atlas_e9_taxon_changes <- function(dna, record) {
  a <- as.character(dna$scientific_name)
  b <- atlas_e9_align(dna, record)
  modelled <- atlas_e9_modelled(b)
  forward <- tapply(b[modelled], a[modelled], function(x) length(unique(x)))
  backward <- tapply(a[modelled], b[modelled], function(x) length(unique(x)))
  dna_names <- unique(a)
  record_names <- unique(b[modelled])
  list(
    split = sort(names(forward)[forward > 1L]),
    merged = sort(names(backward)[backward > 1L]),
    gained = sort(setdiff(record_names, dna_names)),
    lost = sort(setdiff(dna_names, record_names)),
    counts = list(dna_taxa = length(dna_names), record_taxa = length(record_names),
                  split = sum(forward > 1L), merged = sum(backward > 1L),
                  gained = length(setdiff(record_names, dna_names)),
                  lost = length(setdiff(dna_names, record_names)))
  )
}

#' Names under both labellings whose record sets differ, with the records
#' each gains and loses under record names.
atlas_e9_changed_taxa <- function(dna, record) {
  a <- split(atlas_e9_keys(dna), as.character(dna$scientific_name))
  b <- split(atlas_e9_keys(record), as.character(record$scientific_name))
  both <- intersect(names(a), names(b))
  both <- both[atlas_e9_modelled(both)]
  rows <- lapply(both, function(name) {
    gained <- length(setdiff(b[[name]], a[[name]]))
    lost <- length(setdiff(a[[name]], b[[name]]))
    data.frame(taxon = name, records_dna = length(a[[name]]), records_record = length(b[[name]]),
               gained = gained, lost = lost, changed = gained + lost > 0L, stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, rows)
  if (is.null(out)) {
    out <- data.frame(taxon = character(), records_dna = integer(), records_record = integer(),
                      gained = integer(), lost = integer(), changed = logical(), stringsAsFactors = FALSE)
  }
  out[order(out$taxon), , drop = FALSE]
}

#' Two maps of one taxon compared over the cells both give a value: cells,
#' Spearman's rank correlation, and Schoener's D of the suitabilities each
#' normalised to sum to one. The rasters must share the grid; each is
#' extended to the other's extent, never resampled.
atlas_e9_compare_maps <- function(first, second) {
  extent <- terra::union(terra::ext(first), terra::ext(second))
  a <- terra::extend(first[[1]], extent)
  b <- terra::extend(second[[1]], extent)
  if (!isTRUE(terra::compareGeom(a, b, stopOnError = FALSE))) {
    stop("the two maps are not on one grid", call. = FALSE)
  }
  va <- terra::values(a, mat = FALSE)
  vb <- terra::values(b, mat = FALSE)
  both <- is.finite(va) & is.finite(vb)
  n <- sum(both)
  if (n < 10L) return(list(cells = n, spearman = NA_real_, schoener_d = NA_real_))
  va <- va[both]
  vb <- vb[both]
  rho <- if (stats::sd(va) > 0 && stats::sd(vb) > 0) {
    suppressWarnings(stats::cor(va, vb, method = "spearman"))
  } else {
    NA_real_
  }
  d <- if (sum(va) > 0 && sum(vb) > 0) 1 - 0.5 * sum(abs(va / sum(va) - vb / sum(vb))) else NA_real_
  list(cells = n, spearman = rho, schoener_d = d)
}

#' One model of a release: its grade, detection sites and, when drawn, its
#' raster. NULL when the release has no such model. raster_of(view, path)
#' gives a local copy of a release file, or NULL.
atlas_e9_model <- function(view, taxon, algorithm, raster_of = atlas_tracker_file) {
  entry <- Filter(function(e) identical(e$taxon, taxon) && identical(e$algorithm, algorithm), view$entries)
  if (!length(entry)) return(NULL)
  tif <- raster_of(view, atlas_model_relpaths(taxon, view$grid, algorithm, ".tif")[[1]], ".tif")
  list(grade = as.character(entry[[1]]$grade %||% "untested"),
       presences = suppressWarnings(as.integer(entry[[1]]$presences %||% NA)),
       raster = if (!is.null(tif)) terra::rast(tif))
}

#' Every taxon and learner modelled in the record-name release, set against
#' the same taxon and learner in the frozen release: the grade under each,
#' and the two maps' Spearman and Schoener's D where both are drawn. A model
#' with no counterpart is a row too, with the missing side left empty.
atlas_e9_compare_releases <- function(frozen, record, raster_of = atlas_tracker_file) {
  pairs <- unique(do.call(rbind, lapply(record$entries, function(e) {
    data.frame(taxon = as.character(e$taxon), algorithm = as.character(e$algorithm),
               stringsAsFactors = FALSE)
  })))
  if (is.null(pairs)) return(data.frame())
  rows <- lapply(seq_len(nrow(pairs)), function(i) {
    taxon <- pairs$taxon[[i]]
    algorithm <- pairs$algorithm[[i]]
    a <- atlas_e9_model(frozen, taxon, algorithm, raster_of)
    b <- atlas_e9_model(record, taxon, algorithm, raster_of)
    compared <- if (!is.null(a$raster) && !is.null(b$raster)) {
      atlas_e9_compare_maps(a$raster, b$raster)
    } else {
      list(cells = 0L, spearman = NA_real_, schoener_d = NA_real_)
    }
    data.frame(taxon = taxon, algorithm = algorithm,
               grade_dna = a$grade %||% NA_character_, grade_record = b$grade %||% NA_character_,
               presences_dna = a$presences %||% NA_integer_, presences_record = b$presences %||% NA_integer_,
               cells = compared$cells, spearman = round(compared$spearman, 4),
               schoener_d = round(compared$schoener_d, 4), stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out[order(out$taxon, out$algorithm), , drop = FALSE]
}

#' What happened to every model of the frozen release under record names,
#' so the comparisons have their denominator: refitted (the record-name
#' release fitted it again: its record set changed), unchanged (its record
#' set is the same, so the job skipped it: identical by construction), lost
#' (its taxon has no records under record names), and new (a record-name
#' model with no frozen model of that taxon and learner). unchanged is the
#' job's own count (summary.json filter$models_unchanged); the rest come from
#' the two indexes and the record-name pull's names.
atlas_e9_model_counts <- function(frozen_entries, record_entries, record_names, unchanged) {
  key <- function(entries) vapply(entries, function(e) paste(e$algorithm, e$taxon, sep = ""), "")
  taxa <- function(entries) vapply(entries, function(e) as.character(e$taxon), "")
  frozen <- key(frozen_entries)
  record <- key(record_entries)
  lost <- !taxa(frozen_entries) %in% record_names
  refitted <- frozen %in% record
  counts <- list(frozen_models = length(frozen), refitted = sum(refitted), unchanged = as.integer(unchanged),
                 lost = sum(lost & !refitted), new = sum(!record %in% frozen))
  counts$unaccounted <- counts$frozen_models - counts$refitted - counts$unchanged - counts$lost
  counts
}

#' The record-name job's own summary of the private release, or NULL.
atlas_e9_summary <- function(store, record) {
  path <- tempfile(fileext = ".json")
  ok <- tryCatch({
    store$get(paste0(ATLAS_BENCHMARK_PREFIX, "/", record, "/summary.json"), path)
    TRUE
  }, error = function(e) FALSE)
  if (!ok || !file.exists(path)) return(NULL)
  jsonlite::fromJSON(path, simplifyVector = FALSE)
}

#' Grade changes: DNA-name grade by record-name grade.
atlas_e9_grade_changes <- function(compared) {
  levels <- c("strong", "weak", "failed", "untested")
  as.data.frame(table(dna = factor(compared$grade_dna, levels = levels),
                      record = factor(compared$grade_record, levels = levels)),
                stringsAsFactors = FALSE)
}

#' Compare the frozen release with the record-name release and write the
#' results file: counts and per-model scores, never a record.
atlas_e9_study <- function(store = atlas_store(), frozen, record, grid = "draft", quiet = FALSE,
                           frozen_view = NULL, record_view = NULL) {
  started <- Sys.time()
  frozen_view <- frozen_view %||% atlas_tracker_view(store, frozen, grid)
  record_view <- record_view %||% atlas_tracker_view(store, record, grid)
  compared <- atlas_e9_compare_releases(frozen_view, record_view)
  dna <- atlas_tracker_release_pull(store, frozen_view$manifest, grid, frozen_view$cache)
  relabelled <- atlas_tracker_release_pull(store, record_view$manifest, grid, record_view$cache)
  changed <- atlas_e9_changed_taxa(dna, relabelled)
  summary <- atlas_e9_summary(store, record)
  unchanged <- summary$filter$models_unchanged %||% summary$counts$models_unchanged %||% NA_integer_
  models <- atlas_e9_model_counts(frozen_view$entries, record_view$entries,
                                  unique(as.character(relabelled$scientific_name)), unchanged)
  stamp <- format(started, "%Y%m%dT%H%M%SZ", tz = "UTC")
  path <- atlas_path("compare-studies", grid, paste0("e9-", frozen, "-vs-", record, "-", stamp, ".json"),
                     create = TRUE)
  result <- list(
    started_at = format(started, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    settings = list(frozen = frozen, record = record, grid = grid),
    labels = atlas_e9_label_changes(dna, relabelled)$by_source,
    taxa = atlas_e9_taxon_changes(dna, relabelled)$counts,
    changed_taxa = list(changed = sum(changed$changed), unchanged = sum(!changed$changed)),
    # Every frozen model accounted for: the maps below are the refitted ones,
    # and unchanged models are identical by construction (Spearman 1, D 1).
    models = models,
    records_not_species_level = summary$filter$records_not_species_level %||% NA_integer_,
    grades = atlas_e9_grade_changes(compared),
    maps = compared,
    seconds = round(as.numeric(difftime(Sys.time(), started, units = "secs")), 1)
  )
  atlas_write_json(result, path)
  if (!isTRUE(quiet)) {
    message("E9: ", models$refitted, " refitted, ", models$unchanged, " unchanged, ", models$lost,
            " lost of ", models$frozen_models, " frozen models; ", nrow(compared), " compared; median Spearman ",
            round(stats::median(compared$spearman, na.rm = TRUE), 3), ", median Schoener's D ",
            round(stats::median(compared$schoener_d, na.rm = TRUE), 3), " -> ", path)
  }
  invisible(c(result, list(path = path)))
}
