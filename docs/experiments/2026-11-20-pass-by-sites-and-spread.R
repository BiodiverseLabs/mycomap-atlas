# How often a map passes, by its number of sites and their spread, in the
# frozen release (registry entry 2026-11-20-pass-by-sites-and-spread, v2).
# Read-only: the release's index from the store, and its pull fetched by its
# job's own input record into a temporary folder, checked against its hash.
# Writes OUT/sites-spread.json: counts per cell and the exploratory model's
# summary only. No taxon name, record, place or coordinate is written.
#
# On the Atlas box, in the deployed image, with the box's store settings:
#
#   docker run --rm --network host --memory 1g --env-file /etc/atlas/atlas.env \
#     -v "$PWD:/work" -e OUT=/work/out --entrypoint Rscript "$ATLAS_IMAGE" /work/sites_spread.R
#
# Exit 0: written. Exit 1: refused or failed, with the reason; nothing written.

suppressPackageStartupMessages(attach(asNamespace("mycomapatlas"), name = "atlas", warn.conflicts = FALSE))
# The frozen release and its pull. A test may name others; a run on the box
# names neither.
RELEASE <- Sys.getenv("RELEASE", "20261013T191324Z-fa1b4198")
PULL_SHA256 <- Sys.getenv("PULL_SHA256", "7d3c5d7068c6f7dce67ba5e51f4221b49285a073b6d41722c37e54a7a253f9c6")
SITE_BANDS <- list(c(3, 4), c(5, 9), c(10, 19), c(20, 49), c(50, 99), c(100, Inf))
BLOCK_BANDS <- list(c(1, 1), c(2, 2), c(3, 4), c(5, 9), c(10, 19), c(20, Inf))
HULL_BANDS <- list(c(0, 999), c(1000, 9999), c(10000, 99999), c(1e5, 999999), c(1e6, Inf))
BLOCK_KM <- 100
GREY_BELOW <- 20L
# Table 1c (frozen release), the check the sites marginal must reproduce.
TABLE_1C <- list(taxa = c(1655, 1970, 1404, 1012, 276, 52), strong = c(34, 109, 139, 166, 22, 0))

out <- Sys.getenv("OUT")
if (!nzchar(out)) stop("OUT is not set", call. = FALSE)

status <- tryCatch({
  store <- atlas_store()
  manifest <- atlas_store_text(store, paste0("releases/draft/", RELEASE, ".json"))
  job <- atlas_read_job(store, atlas_json_string(manifest$job), "draft")
  pull_entry <- Filter(function(e) grepl("^occurrences/occurrences-.*[.]tsv[.]gz$", e$path), job$inputs)
  if (length(pull_entry) != 1L || !identical(pull_entry[[1]]$sha256, PULL_SHA256)) {
    stop("the release's job does not name the frozen pull (sha256 ", PULL_SHA256, ")", call. = FALSE)
  }
  scratch <- tempfile("sites-spread-")
  dir.create(scratch)
  on.exit(unlink(scratch, recursive = TRUE), add = TRUE)
  Sys.setenv(ATLAS_DATA_DIR = scratch)
  atlas_fetch_entries(store, pull_entry)
  pull <- atlas_read_occurrences(file.path(scratch, pull_entry[[1]]$path))

  # The models: each taxon's largest model's detection sites, and whether any
  # of its models is strong (E16's rule, Table 1c).
  index <- Filter(function(e) !isTRUE(e$refused) && is.numeric(e$presences), manifest$index)
  models <- data.frame(
    taxon = vapply(index, function(e) e$taxon, ""),
    algorithm = vapply(index, function(e) e$algorithm, ""),
    presences = vapply(index, function(e) as.numeric(e$presences), 0),
    strong = vapply(index, function(e) identical(e$grade, "strong"), FALSE),
    stringsAsFactors = FALSE
  )
  taxa <- do.call(rbind, lapply(split(models, models$taxon), function(m) {
    data.frame(taxon = m$taxon[[1]], sites = max(m$presences), strong = any(m$strong), stringsAsFactors = FALSE)
  }))

  # Spread, from the detection sites as the fits build them (5 km sites of
  # the whole pull): occupied 100 km blocks, and the hull of the sites.
  points <- atlas_occurrence_points(pull, "draft")
  sites <- attr(points, "sites")
  of <- split(points$site, points$scientific_name)
  spread <- function(name) {
    s <- unique(of[[name]])
    if (is.null(s) || !length(s)) return(c(blocks = NA_real_, hull_km2 = NA_real_))
    x <- sites$x[match(s, sites$site)]
    y <- sites$y[match(s, sites$site)]
    blocks <- length(unique(atlas_block_labels(x, y, BLOCK_KM)))
    hull <- if (length(s) >= 3L) {
      h <- grDevices::chull(x, y)
      area <- abs(sum(x[h] * c(y[h][-1], y[h][1]) - c(x[h][-1], x[h][1]) * y[h])) / 2
      if (area > 0) area / 1e6 else NA_real_
    } else NA_real_
    c(blocks = blocks, hull_km2 = hull)
  }
  measured <- t(vapply(taxa$taxon, spread, numeric(2)))
  taxa$blocks <- measured[, "blocks"]
  taxa$hull_km2 <- measured[, "hull_km2"]

  band <- function(value, bands) {
    labels <- vapply(bands, function(b) if (is.infinite(b[[2]])) paste0(b[[1]], "+") else
      if (b[[1]] == b[[2]]) format(b[[1]]) else paste0(b[[1]], "-", b[[2]]), "")
    i <- vapply(value, function(v) {
      if (is.na(v)) return(NA_integer_)
      hit <- which(vapply(bands, function(b) v >= b[[1]] && v <= b[[2]], FALSE))
      if (length(hit)) hit[[1]] else NA_integer_
    }, integer(1))
    factor(labels[i], levels = labels)
  }
  wilson <- function(k, n, z = 1.96) {
    if (!n) return(c(NA_real_, NA_real_))
    p <- k / n; d <- 1 + z^2 / n
    c((p + z^2 / (2 * n)) / d - z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / d,
      (p + z^2 / (2 * n)) / d + z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / d)
  }
  grid_of <- function(rows, a, b) {
    cells <- list()
    for (i in levels(a)) for (j in levels(b)) {
      sel <- which(a == i & b == j)
      n <- length(sel); k <- sum(rows$strong[sel])
      ci <- wilson(k, n)
      cells[[length(cells) + 1L]] <- list(sites = i, spread = j, taxa = n, strong = k,
                                          share = if (n) round(k / n, 4) else NULL,
                                          low = if (n) round(ci[[1]], 4) else NULL,
                                          high = if (n) round(ci[[2]], 4) else NULL,
                                          greyed = n < GREY_BELOW)
    }
    cells
  }
  margin <- function(rows, a) lapply(levels(a), function(i) {
    sel <- which(a == i); n <- length(sel); k <- sum(rows$strong[sel]); ci <- wilson(k, n)
    list(band = i, taxa = n, strong = k, share = if (n) round(k / n, 4) else NULL,
         low = if (n) round(ci[[1]], 4) else NULL, high = if (n) round(ci[[2]], 4) else NULL)
  })

  taxa$site_band <- band(taxa$sites, SITE_BANDS)
  taxa$block_band <- band(taxa$blocks, BLOCK_BANDS)
  taxa$hull_band <- band(taxa$hull_km2, HULL_BANDS)
  modelled <- taxa[!is.na(taxa$site_band), , drop = FALSE]

  check <- margin(modelled, modelled$site_band)
  check_ok <- identical(vapply(check, function(m) as.numeric(m$taxa), 0), TABLE_1C$taxa) &&
    identical(vapply(check, function(m) as.numeric(m$strong), 0), TABLE_1C$strong)

  # Per learner (supplement): each model, its own sites, its taxon's blocks.
  models$blocks <- taxa$blocks[match(models$taxon, taxa$taxon)]
  per_learner <- lapply(stats::setNames(nm = sort(unique(models$algorithm))), function(a) {
    m <- models[models$algorithm == a, , drop = FALSE]
    grid_of(m, band(m$presences, SITE_BANDS), band(m$blocks, BLOCK_BANDS))
  })

  # Exploratory: does spread add to sites?
  fit_rows <- modelled[is.finite(modelled$blocks) & modelled$blocks > 0, , drop = FALSE]
  without <- stats::glm(strong ~ log(sites), family = stats::binomial(), data = fit_rows)
  with <- stats::glm(strong ~ log(sites) + log(blocks), family = stats::binomial(), data = fit_rows)
  lr <- as.numeric(2 * (stats::logLik(with) - stats::logLik(without)))
  coefs <- stats::coef(summary(with))
  ci <- stats::confint.default(with)

  result <- list(
    release = RELEASE, pull_sha256 = PULL_SHA256, block_km = BLOCK_KM, greyed_below = GREY_BELOW,
    modelled_taxa = nrow(modelled),
    table_1c_check = list(reproduced = check_ok, by_sites = check),
    grid = grid_of(modelled, modelled$site_band, modelled$block_band),
    by_spread = margin(modelled, modelled$block_band),
    hull = list(grid = grid_of(modelled, modelled$site_band, modelled$hull_band),
                by_hull = margin(modelled, modelled$hull_band),
                without_hull = sum(is.na(modelled$hull_band))),
    per_learner = per_learner,
    exploratory = list(
      model = "strong ~ log(sites) + log(blocks), against strong ~ log(sites); taxa, binomial",
      taxa = nrow(fit_rows), lr = round(lr, 3),
      p = signif(stats::pchisq(lr, df = 1, lower.tail = FALSE), 4),
      coefficients = lapply(rownames(coefs), function(r) list(term = r, estimate = round(coefs[r, 1], 4),
                                                             low = round(ci[r, 1], 4), high = round(ci[r, 2], 4)))
    )
  )
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  atlas_write_json(result, file.path(out, "sites-spread.json"))
  cat(sprintf("%d modelled taxa; Table 1c reproduced: %s; written %s\n", nrow(modelled), check_ok,
              file.path(out, "sites-spread.json")))
  0L
}, error = function(e) {
  cat("STOP: ", conditionMessage(e), "\n", sep = "")
  1L
})
quit(save = "no", status = status)
