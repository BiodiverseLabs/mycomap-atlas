# Measuring whether a new layer earns its place.
#
# A layer is worth adding only if models fitted with it rank held-out ground
# better than models fitted without it. This refits a sample of taxa several
# ways, each way adding one group of new layers to the ones production already
# uses, and scores every way on the same spatial folds.
#
# As in the predictor sweep, everything but the layers is held fixed: one
# training table per taxon — built on every layer, so each arm sees exactly the
# same rows — one set of folds, and production's own design: survey sites with
# effort, blocks as wide as blockCV measures, the guild's predictor order and
# host allowance for Maxent. A difference between two arms for one taxon can
# then only come from the layers, and each taxon is compared with itself.
# Learners run at their untuned settings: tuning every arm would cost ten
# times as much and the arms are compared with each other, not with a map.
#
# Arms whose layers are not built are left out, so the sweep can run on
# whatever has been built so far. Nothing here writes a model. It writes one
# results file under data/layer-sweeps/.

# The layers production fits on: the baseline every arm adds to.
ATLAS_PRODUCTION_LAYERS <- c("elevation", "bioclim", "terrain", "soil", "landcover",
                             "hosts", "foresttype")
ATLAS_BASE_LAYERS <- ATLAS_PRODUCTION_LAYERS

# Each arm: an algorithm, and the layers it may draw predictors from.
# "maxnet" arms go through production's pruning and cap; "rf" uses every
# predictor it is given, as production's random forest does.
#
# "all" means every new group that is built, so a sweep run before the last
# download lands still compares the full set it has.
atlas_layer_sweep_arms <- function(new = ATLAS_NEW_LAYER_GROUPS, built = NULL,
                                   base = ATLAS_BASE_LAYERS) {
  if (!is.null(built)) {
    new <- new[vapply(new, function(ids) all(ids %in% built), logical(1))]
  }
  groups <- lapply(names(new), function(group) {
    list(arm = paste0("+", group), algorithm = "maxnet",
         layers = c(base, new[[group]]))
  })
  everything <- c(base, unlist(new, use.names = FALSE))
  c(
    list(list(arm = "base", algorithm = "maxnet", layers = base)),
    groups,
    list(
      list(arm = "all", algorithm = "maxnet", layers = everything),
      list(arm = "rf:base", algorithm = "rf", layers = base),
      list(arm = "rf:all", algorithm = "rf", layers = everything)
    )
  )
}

# The candidate layers, by the question each one asks.
ATLAS_NEW_LAYER_GROUPS <- list(
  climate = "waterbalance"
)

#' Keep the arms whose layers are all built, and say which were dropped.
atlas_runnable_arms <- function(arms, built) {
  ok <- vapply(arms, function(a) all(a$layers %in% built), logical(1))
  out <- arms[ok]
  attr(out, "skipped") <- vapply(arms[!ok], function(a) a$arm, character(1))
  out
}

#' The predictor columns each layer contributes, from the grid's manifest.
atlas_layer_bands <- function(grid = "draft", manifest = atlas_layer_manifest(grid)) {
  bands <- lapply(manifest, function(x) as.character(unlist(x$bands)))
  names(bands) <- vapply(manifest, function(x) as.character(x$id), character(1))
  bands
}

#' Score one taxon under every arm, on one training table and one set of folds.
atlas_layer_sweep_taxon <- function(name, fingerprint, points, stack, arms,
                                    bands, grid = "draft", n_background = 10000,
                                    buffer_km = 500, folds = 5, block_km = "auto",
                                    regmult = 1, correlation = 0.7,
                                    min_presences = 20,
                                    guilds = atlas_guild_table()) {
  started <- Sys.time()
  training <- atlas_build_training(
    name, grid, n_background = n_background, buffer_km = buffer_km,
    write = FALSE, quiet = TRUE, points = points, stack = stack,
    fingerprint = fingerprint
  )
  presences <- sum(training$presence == 1L)
  if (presences < min_presences) {
    return(list(taxon = name, status = "refused", presences = presences))
  }
  seed <- attr(training, "seed")
  block <- if (atlas_block_is_auto(block_km)) {
    atlas_block_size(training, seed = seed)$block_km
  } else {
    as.numeric(block_km)
  }
  fold_ids <- atlas_spatial_folds(
    training$x, training$y, k = folds, block_km = block, seed = seed,
    presence = training$presence
  )
  guild <- atlas_taxon_guild(name, guilds)
  effort_at <- atlas_effort_level(training)
  bookkeeping <- c("presence", "cell", "x", "y")

  run_arm <- function(arm) {
    arm_started <- Sys.time()
    columns <- intersect(unlist(bands[arm$layers], use.names = FALSE), names(training))
    columns <- c(columns, intersect(ATLAS_EFFORT_COLUMN, names(training)))
    available <- training[, c(bookkeeping, columns), drop = FALSE]
    algo <- atlas_algorithm(arm$algorithm)
    keep <- if (isTRUE(algo$prune)) {
      atlas_choose_predictors(available, threshold = correlation,
                              priority = atlas_predictor_priority(guild),
                              host_share = atlas_host_allowance(guild))
    } else {
      atlas_predictor_columns(available)
    }
    table <- available[, c(bookkeeping, keep), drop = FALSE]
    scores <- atlas_cross_validate(
      table, fold_ids,
      fit = function(train) algo$fit(train, atlas_null_params(algo, train), seed, tuning = TRUE),
      score = algo$score, effort_at = effort_at
    )
    keep <- setdiff(keep, ATLAS_EFFORT_COLUMN)
    list(
      arm = arm$arm,
      predictors = length(keep),
      kept = as.list(keep),
      auc = round(mean(scores$auc, na.rm = TRUE), 4),
      boyce = round(atlas_pooled_boyce(scores), 4),
      folds_scored = sum(!is.na(scores$auc)),
      seconds = round(as.numeric(difftime(Sys.time(), arm_started, units = "secs")), 1)
    )
  }

  list(
    taxon = name, status = "scored", presences = presences,
    band = atlas_presence_band(presences),
    guild = guild, block_km = block,
    dropped = attr(training, "dropped"),
    arms = lapply(arms, run_arm),
    seconds = round(as.numeric(difftime(Sys.time(), started, units = "secs")), 1)
  )
}

#' How many records each new layer cannot describe, where the base layers can.
#'
#' Every arm is fitted on the rows all layers describe, so a layer with holes
#' (a national product with nothing over Mexico, say) shrinks the data for
#' every arm, not just its own. This says by how much, before anything is
#' fitted.
atlas_layer_coverage <- function(points, stack, bands, base = ATLAS_BASE_LAYERS) {
  cells <- unique(points$cell)
  xy <- terra::xyFromCell(atlas_grid_like(stack), cells)
  values <- terra::extract(stack, xy)
  base_cols <- intersect(unlist(bands[base], use.names = FALSE), names(values))
  described <- stats::complete.cases(values[, base_cols, drop = FALSE])
  weight <- as.numeric(table(points$cell)[as.character(cells)])
  others <- setdiff(names(bands), base)
  out <- lapply(others, function(id) {
    cols <- intersect(bands[[id]], names(values))
    missing <- described & !stats::complete.cases(values[, cols, drop = FALSE])
    list(layer = id, records_missing = sum(weight[missing]),
         share_missing = round(sum(weight[missing]) / sum(weight[described]), 4))
  })
  names(out) <- others
  out
}

#' A raster with the stack's geometry, for turning cell numbers into places.
atlas_grid_like <- function(stack) {
  terra::rast(stack, nlyrs = 1)
}

#' Run the layer sweep over a stratified sample of the batch candidates.
atlas_layer_sweep <- function(grid = "draft", per_band = 40, workers = 1L,
                              seed = 1L, min_presences = 20,
                              n_background = 10000, buffer_km = 500,
                              folds = 5, block_km = "auto", regmult = 1,
                              correlation = 0.7, quiet = FALSE,
                              base = ATLAS_BASE_LAYERS,
                              groups = ATLAS_NEW_LAYER_GROUPS,
                              occurrences = NULL, points = NULL,
                              stack = NULL, bands = NULL, taxa = NULL) {
  bands <- bands %||% atlas_layer_bands(grid)
  built <- names(bands)
  unbuilt <- names(groups)[!vapply(groups, function(ids) all(ids %in% built), logical(1))]
  arms <- atlas_runnable_arms(
    atlas_layer_sweep_arms(groups, built = built, base = base), built
  )
  skipped <- c(attr(arms, "skipped"), paste0("+", unbuilt))
  if (!length(arms)) {
    stop("no arm has all its layers built on the ", grid, " grid", call. = FALSE)
  }
  occurrences <- occurrences %||% atlas_read_occurrences()
  points <- points %||% atlas_occurrence_points(occurrences, grid)
  stack <- stack %||% atlas_predictor_stack(grid)
  coverage <- atlas_layer_coverage(points, stack, bands, base = base)
  candidates <- atlas_batch_candidates(points, min_presences, taxa = taxa)
  sample <- atlas_sweep_sample(candidates, per_band = per_band, seed = seed)
  fingerprints <- atlas_fingerprints_for(occurrences, sample$scientific_name)

  args <- list(
    arms = arms, bands = bands, grid = grid, n_background = n_background,
    buffer_km = buffer_km, folds = folds, block_km = block_km,
    regmult = regmult, correlation = correlation, min_presences = min_presences
  )
  settings <- c(args[setdiff(names(args), c("arms", "bands"))],
                list(arms = lapply(arms, function(a) a[c("arm", "algorithm", "layers")]),
                     skipped = as.list(skipped),
                     coverage = coverage, per_band = per_band, seed = seed))
  atlas_run_study(
    kind = "layer-sweeps", file_prefix = "layers", taxon_fn = "atlas_layer_sweep_taxon",
    sample = sample, fingerprints = fingerprints, args = args,
    settings = settings, baseline = "base", grid = grid, workers = workers,
    points = points, stack = stack, quiet = quiet,
    opening = paste0(
      nrow(sample), " taxa sampled from ", nrow(candidates), " candidates (",
      atlas_band_counts(sample), "); arms: ",
      paste(vapply(arms, function(a) a$arm, character(1)), collapse = ", "),
      if (length(skipped)) paste0("; not built, skipped: ", paste(skipped, collapse = ", ")) else "",
      "; records a new layer cannot describe: ",
      paste(vapply(coverage, function(c) sprintf("%s %s", c$layer, c$records_missing),
                   character(1)), collapse = ", ")
    )
  )
}
