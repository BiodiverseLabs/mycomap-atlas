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
# The same sweep asks whether the design itself earns its place. Three arms
# are fitted on production's layers the way Atlas used to fit, and scored
# exactly as every other arm is, on the held-out survey sites:
#
#   base:no-effort   survey sites, but effort is not a predictor
#   base:per-record  the design before survey sites: every non-detection site
#                    repeated once for each record collected there, no effort
#   +hosts:flat      host trees in the order of a fungus of unknown guild
#
# The old design is judged by the new design's yardstick, held-out sites each
# counted once with effort held fixed. That is the yardstick the maps are for:
# ranking ground, not ranking how often ground was visited.
#
# Arms whose layers are not built are left out, so the sweep can run on
# whatever has been built so far. Nothing here writes a model. It writes one
# results file under data/layer-sweeps/.

# The layers production fits on today: the baseline every arm adds to.
ATLAS_BASE_LAYERS <- c("elevation", "bioclim", "terrain", "soil", "landcover")

# Each arm: an algorithm, and the layers it may draw predictors from.
# "maxnet" arms go through production's pruning and cap; "rf" uses every
# predictor it is given, as production's random forest does.
#
# "all" means every new group that is built, so a sweep run before the last
# download lands still compares the full set it has.
atlas_layer_sweep_arms <- function(new = ATLAS_NEW_LAYER_GROUPS, built = NULL,
                                   base = ATLAS_BASE_LAYERS, method = FALSE) {
  if (!is.null(built)) {
    new <- new[vapply(new, function(ids) all(ids %in% built), logical(1))]
  }
  groups <- lapply(names(new), function(group) {
    list(arm = paste0("+", group), algorithm = "maxnet",
         layers = c(base, new[[group]]))
  })
  # The two host layers are rivals: "all" takes the first of them that is built.
  rivals <- intersect(ATLAS_RIVAL_LAYERS, unlist(new, use.names = FALSE))
  everything <- setdiff(c(base, unlist(new, use.names = FALSE)), rivals[-1])
  flat <- if ("hosts" %in% names(new)) {
    list(list(arm = "+hosts:flat", algorithm = "maxnet", layers = c(base, new$hosts),
              guild_order = FALSE))
  }
  designs <- if (isTRUE(method)) {
    unlist(lapply(c("maxnet", "rf"), function(algorithm) {
      prefix <- if (algorithm == "rf") "rf:base" else "base"
      lapply(setdiff(ATLAS_SWEEP_DESIGNS, "sites"), function(design) {
        list(arm = paste0(prefix, ":", design), algorithm = algorithm, layers = base,
             design = design)
      })
    }), recursive = FALSE)
  }
  c(
    list(list(arm = "base", algorithm = "maxnet", layers = base)),
    groups,
    flat,
    list(
      list(arm = "all", algorithm = "maxnet", layers = everything),
      list(arm = "rf:base", algorithm = "rf", layers = base),
      list(arm = "rf:all", algorithm = "rf", layers = everything)
    ),
    designs
  )
}

# The arms whose predictors and layers are measured for what each was worth
# on held-out ground (R/importance.R): both learners, on everything.
ATLAS_IMPORTANCE_ARMS <- c("all", "rf:all")

# How an arm's training rows are made. "sites" is production's design.
ATLAS_SWEEP_DESIGNS <- c("sites", "no-effort", "per-record")

#' An arm's training rows under its design, from the survey-site rows.
#'
#' "sites" leaves them alone. "no-effort" takes the effort column away.
#' "per-record" is the design before survey sites: each non-detection site is
#' repeated once for every record collected there (effort is
#' log(1 + records)), at most n_background rows drawn from the repeats, each
#' detection site counted once, and no effort column.
atlas_design_rows <- function(train, design = "sites", n_background = 10000, seed = 1L) {
  design <- match.arg(design, ATLAS_SWEEP_DESIGNS)
  if (design == "sites" || !ATLAS_EFFORT_COLUMN %in% names(train)) {
    return(train)
  }
  effort <- train[[ATLAS_EFFORT_COLUMN]]
  train[[ATLAS_EFFORT_COLUMN]] <- NULL
  if (design == "no-effort") {
    return(train)
  }
  found <- which(train$presence == 1L)
  others <- which(train$presence == 0L)
  records <- pmax(1L, as.integer(round(expm1(effort[others]))))
  repeated <- rep(others, times = records)
  if (length(repeated) > n_background) {
    set.seed(seed)
    repeated <- sort(repeated[sample.int(length(repeated), n_background)])
  }
  out <- train[c(found, repeated), , drop = FALSE]
  rownames(out) <- NULL
  out
}

# Layers that answer the same question two ways; only one goes into "all".
ATLAS_RIVAL_LAYERS <- c("hosts", "hosts_wilson")

# The candidate layers, by the question each one asks.
ATLAS_NEW_LAYER_GROUPS <- list(
  forest = "foresttype",
  hosts = "hosts",
  hosts_wilson = "hosts_wilson",
  climate = "waterbalance",
  bedrock = "bedrock",
  landform = "landform"
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
                                    guilds = atlas_guild_table(),
                                    importance = ATLAS_IMPORTANCE_ARMS) {
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
  effort_column <- intersect(ATLAS_EFFORT_COLUMN, names(training))
  bookkeeping <- c("presence", "cell", "x", "y")

  run_arm <- function(arm) {
    arm_started <- Sys.time()
    columns <- intersect(unlist(bands[arm$layers], use.names = FALSE), names(training))
    design <- arm$design %||% "sites"
    ordered_as <- if (isFALSE(arm$guild_order)) ATLAS_GUILD_UNKNOWN else guild
    available <- training[, c(bookkeeping, columns, effort_column), drop = FALSE]
    algo <- atlas_algorithm(arm$algorithm)
    keep <- if (isTRUE(algo$prune)) {
      atlas_choose_predictors(available, threshold = correlation,
                              priority = atlas_predictor_priority(ordered_as),
                              host_share = atlas_host_allowance(ordered_as))
    } else {
      atlas_predictor_columns(available)
    }
    # The effort column stays in the table so a design can count records from
    # it; atlas_design_rows takes it out of the designs that fit without it.
    table <- available[, c(bookkeeping, union(keep, effort_column)), drop = FALSE]
    fit_arm <- function(train) {
      rows <- atlas_design_rows(train, design, n_background = n_background, seed = seed)
      algo$fit(rows, atlas_null_params(algo, rows), seed, tuning = TRUE)
    }
    scores <- if (arm$arm %in% importance) {
      atlas_cross_validate_importance(
        table, fold_ids, fit = fit_arm, score = algo$score, effort_at = effort_at,
        layers = bands[arm$layers], seed = seed
      )
    } else {
      atlas_cross_validate(table, fold_ids, fit = fit_arm, score = algo$score,
                           effort_at = effort_at)
    }
    measured <- attr(scores, "importance")
    keep <- setdiff(keep, ATLAS_EFFORT_COLUMN)
    list(
      arm = arm$arm,
      design = design,
      predictors = length(keep),
      kept = as.list(keep),
      auc = round(mean(scores$auc, na.rm = TRUE), 4),
      boyce = round(atlas_pooled_boyce(scores), 4),
      folds_scored = sum(!is.na(scores$auc)),
      importance = if (is.null(measured)) NULL else {
        lapply(seq_len(nrow(measured)), function(i) as.list(measured[i, ]))
      },
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
                              correlation = 0.7, quiet = FALSE, method = TRUE,
                              base = ATLAS_BASE_LAYERS,
                              groups = ATLAS_NEW_LAYER_GROUPS,
                              occurrences = NULL, points = NULL,
                              stack = NULL, bands = NULL, taxa = NULL) {
  bands <- bands %||% atlas_layer_bands(grid)
  built <- names(bands)
  unbuilt <- names(groups)[!vapply(groups, function(ids) all(ids %in% built), logical(1))]
  arms <- atlas_runnable_arms(
    atlas_layer_sweep_arms(groups, built = built, base = base, method = method), built
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
                list(arms = lapply(arms, function(a) {
                       c(a[c("arm", "algorithm", "layers")],
                         list(design = a$design %||% "sites",
                              guild_order = !isFALSE(a$guild_order)))
                     }),
                     design = atlas_design(),
                     skipped = as.list(skipped),
                     coverage = coverage, per_band = per_band, seed = seed))
  result <- atlas_run_study(
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
  # What each predictor and layer was worth, beside the results.
  importance <- atlas_importance_summary(result$taxa)
  result$importance <- importance
  result$importance_path <- sub("layers-([^/]*)[.]json$", "importance-\\1.json", result$path)
  atlas_write_json(list(arms = as.list(ATLAS_IMPORTANCE_ARMS), repeats = ATLAS_IMPORTANCE_REPEATS,
                        summary = importance), result$importance_path)
  invisible(result)
}
