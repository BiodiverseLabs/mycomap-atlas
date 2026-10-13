# Paper E12 (grade stability): which models are refitted, and what that
# costs, decided once from the frozen release.
#
# The rule (docs/experiments plan-e12, fixed 2026-10-13):
#   - strata are learner x site band (3-4, 5-19, 20-49, 50+) x grade
#     (strong, weak, failed) in the frozen release; empty cells are skipped;
#   - within each cell, models are put in taxon order, then shuffled by
#     sample.int with seed 1 set afresh for that cell (so a cell's draw never
#     depends on the cells before it), and the first 25 are taken (all, if
#     fewer);
#   - cost: every drawn model's recorded fit time (its shard result's
#     seconds, null test included, one core) times three fits. Applied once:
#     if the 50+ Maxent cells together exceed half the estimated cost, each
#     keeps only its first 10, in the same order;
#   - cells are weighted back to release shares in the analysis.
#
# Read-only: it reads the release, the releases before it and their jobs'
# shard records, and writes a local CSV only.
#
#   ./atlas study-e12-draw --release=<frozen> [--out=e12-draw.csv]

ATLAS_E12_BANDS <- c("3-4" = 3, "5-19" = 5, "20-49" = 20, "50+" = 50)
ATLAS_E12_GRADES <- c("strong", "weak", "failed")
ATLAS_E12_PER_CELL <- 25L
ATLAS_E12_CAPPED <- 10L
ATLAS_E12_SEED <- 1L
ATLAS_E12_FITS <- 3L

#' A model's site band, by its detection sites (the index's presences).
atlas_e12_band <- function(presences) {
  presences <- as.numeric(presences)
  out <- rep(NA_character_, length(presences))
  for (i in seq_along(ATLAS_E12_BANDS)) {
    out[!is.na(presences) & presences >= ATLAS_E12_BANDS[[i]]] <- names(ATLAS_E12_BANDS)[[i]]
  }
  out
}

#' The release's models as strata: every model with a grade the plan
#' counts, its cell, and its place in its cell's seeded order.
atlas_e12_draw <- function(index, per_cell = ATLAS_E12_PER_CELL, seed = ATLAS_E12_SEED,
                           grades = ATLAS_E12_GRADES) {
  field <- function(name, default) vapply(index, function(e) {
    v <- e[[name]]
    if (is.null(v) || !length(v)) default else as.character(v[[1]])
  }, "")
  d <- data.frame(algorithm = field("algorithm", NA_character_), taxon = field("taxon", NA_character_),
                  fingerprint = field("fingerprint", ""), presences = suppressWarnings(as.numeric(field("presences", NA))),
                  grade = field("grade", NA_character_), refused = field("refused", "FALSE") == "TRUE",
                  stringsAsFactors = FALSE)
  d$band <- atlas_e12_band(d$presences)
  left_out <- table(factor(ifelse(d$refused, "refused", ifelse(is.na(d$band), "no band",
                                  ifelse(d$grade %in% grades, "kept", paste("grade", d$grade))))))
  d <- d[!d$refused & !is.na(d$band) & d$grade %in% grades, c("algorithm", "taxon", "fingerprint", "presences",
                                                              "band", "grade"), drop = FALSE]
  d$cell <- paste(d$algorithm, d$band, d$grade, sep = " | ")
  d$rank <- NA_integer_
  # The seed is set afresh for each cell; the caller's random stream is put
  # back afterwards.
  had <- exists(".Random.seed", envir = globalenv(), inherits = FALSE)
  saved <- if (had) get(".Random.seed", envir = globalenv())
  on.exit(if (had) assign(".Random.seed", saved, envir = globalenv()) else
    rm(".Random.seed", envir = globalenv()), add = TRUE)
  for (cell in sort(unique(d$cell))) {
    rows <- which(d$cell == cell)
    rows <- rows[order(d$taxon[rows], method = "radix")]
    set.seed(seed, kind = "Mersenne-Twister", normal.kind = "Inversion", sample.kind = "Rejection")
    d$rank[rows[sample.int(length(rows))]] <- seq_along(rows)
  }
  d$drawn <- d$rank <= per_cell
  d <- d[order(d$cell, d$rank), , drop = FALSE]
  rownames(d) <- NULL
  attr(d, "left_out") <- as.list(left_out)
  d
}

#' Each model's recorded fit time: the seconds its shard result gives, from
#' the job that fitted the release's model (same algorithm, taxon and
#' fingerprint), walking back through the releases before it. Refresh,
#' private and study jobs are skipped: their fits are not the release's.
#' Returns seconds named "algorithm|taxon|fingerprint".
atlas_e12_seconds <- function(store, release, grid = "draft") {
  seconds <- numeric()
  seen <- character()
  visited <- character()
  r <- release
  while (!is.null(r) && !(r$id %||% "") %in% visited) {
    visited <- c(visited, r$id %||% "")
    job_id <- atlas_json_string(r$job)
    if (!is.null(job_id) && !job_id %in% seen) {
      seen <- c(seen, job_id)
      job <- tryCatch(atlas_read_job(store, job_id, grid), error = function(e) NULL)
      if (!is.null(job) && is.null(job$kind)) {
        for (n in seq_len(as.integer(job$shards %||% 0L))) {
          record <- tryCatch(atlas_store_text(store, atlas_shard_key(job_id, n, grid)), error = function(e) NULL)
          for (x in record$results %||% list()) {
            if (!identical(x$status, "fitted") || is.null(x$seconds)) next
            key <- paste(x$algorithm, x$taxon, x$fingerprint %||% "", sep = "|")
            if (is.na(seconds[key])) seconds[[key]] <- as.numeric(x$seconds)
          }
        }
      }
    }
    previous <- atlas_json_string(r$previous)
    key <- if (!is.null(previous)) paste0("releases/", grid, "/", previous, ".json")
    r <- if (!is.null(key) && store$exists(key)) atlas_store_text(store, key)
  }
  seconds
}

#' The draw's cost, and the cap the plan applies once: a drawn model without
#' a recorded time takes its cell's median (else its learner and band's,
#' else every drawn model's), flagged as imputed.
atlas_e12_cost <- function(draw, seconds, fits = ATLAS_E12_FITS, capped = ATLAS_E12_CAPPED,
                           cap_share = 0.5) {
  d <- draw
  key <- paste(d$algorithm, d$taxon, d$fingerprint, sep = "|")
  d$seconds <- unname(seconds[key])
  d$imputed <- is.na(d$seconds)
  fill <- function(group) {
    for (g in unique(group[d$drawn & d$imputed])) {
      known <- d$seconds[group == g & !d$imputed]
      if (length(known)) d$seconds[group == g & d$imputed & is.na(d$seconds)] <<- stats::median(known)
    }
  }
  fill(d$cell)
  fill(paste(d$algorithm, d$band))
  d$seconds[is.na(d$seconds)] <- stats::median(d$seconds[!d$imputed], na.rm = TRUE)
  cpu_hours <- function(rows) sum(d$seconds[rows], na.rm = TRUE) * fits / 3600
  rich_maxent <- d$algorithm == "maxnet" & d$band == "50+"
  before <- cpu_hours(d$drawn)
  rich_share <- if (before > 0) cpu_hours(d$drawn & rich_maxent) / before else 0
  d$sample <- d$drawn
  cap_applied <- rich_share > cap_share
  if (cap_applied) d$sample <- d$drawn & (!rich_maxent | d$rank <= capped)
  list(
    models = d,
    summary = list(
      cells = length(unique(d$cell[d$sample])), drawn = sum(d$drawn), sample = sum(d$sample),
      imputed = sum(d$sample & d$imputed),
      cpu_hours_drawn = round(before, 1), maxent_50_share = round(rich_share, 3),
      cap_applied = cap_applied, cpu_hours = round(cpu_hours(d$sample), 1), fits_per_model = fits,
      by_learner = lapply(split(d[d$sample, ], d$algorithm[d$sample]), function(x) {
        list(models = nrow(x), cpu_hours = round(sum(x$seconds) * fits / 3600, 1))
      })
    )
  )
}

#' The step-0 query: the draw on a release, its recorded times and cost,
#' written to a local CSV (taxon names and numbers only, no places).
atlas_e12_draw_study <- function(store = atlas_store(), release, grid = "draft", out = "e12-draw.csv",
                                 quiet = FALSE) {
  key <- paste0("releases/", grid, "/", release, ".json")
  if (!store$exists(key)) stop("no release ", release, " for the ", grid, " grid", call. = FALSE)
  base <- atlas_store_text(store, key)
  draw <- atlas_e12_draw(base$index)
  cost <- atlas_e12_cost(draw, atlas_e12_seconds(store, base, grid))
  utils::write.csv(cost$models, out, row.names = FALSE)
  if (!isTRUE(quiet)) {
    s <- cost$summary
    message("E12 draw on ", release, ": ", s$drawn, " drawn in ", s$cells, " cells; Maxent 50+ share ",
            s$maxent_50_share, if (s$cap_applied) " > 0.5, capped at 10 each" else "", "; sample ", s$sample,
            " models, ", s$imputed, " with imputed times; ", s$cpu_hours, " CPU-h for ", s$fits_per_model, " fits each")
    for (l in names(s$by_learner)) message("  ", l, ": ", s$by_learner[[l]]$models, " models, ",
                                           s$by_learner[[l]]$cpu_hours, " CPU-h")
    left <- attr(draw, "left_out")
    message("  index entries left out: ", paste(names(left), unlist(left), sep = " ", collapse = ", "))
    message("  written: ", out)
  }
  invisible(cost)
}
