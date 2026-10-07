# How much each predictor, and each layer, matters to a model.
#
# Measured the way the models are scored: on ground the model never saw. For
# every spatial fold, a predictor's values are shuffled among the held-out
# sites and the sites are scored again; the fall in blocked AUC is what the
# model owed to that predictor there (Breiman 2001; Fisher, Rudin & Dominici
# 2019). Shuffling every band of a layer together, row by row, gives the
# layer's share, which is not the sum of its bands': correlated bands cover
# for one another when only one is shuffled.
#
# It is measured on held-out sites, never the training sites. A model that
# has memorised noise in a predictor leans on it heavily where it was fitted
# and gains nothing from it elsewhere; importance on training data would
# report the memorising as importance. A fall of zero, or a rise, on held-out
# ground is what an overfitted predictor looks like.
#
# Effort is left out: it is held at one value whenever a model is scored.
#
# Every production fit measures this on its own outer folds, and keeps it with
# the model (atlas_fit_taxon, importance = TRUE), so a taxon's page can say
# what its maps rest on, dataset by dataset and variable by variable.

# Times each predictor is shuffled in each fold. Two left one shuffle's luck
# in the answer: on Laccaria laccata's forest the elevation layer read -0.010
# and its only predictor, elevation, +0.005, the same measurement twice.
ATLAS_IMPORTANCE_REPEATS <- 5L

#' Fall in held-out AUC when columns are shuffled, for one fitted model.
#'
#' groups is a named list, name -> the columns shuffled together. Returns a
#' named vector, one fall per group; NA when the held-out sites cannot be
#' scored.
atlas_permutation_falls <- function(model, test, groups, score,
                                    repeats = ATLAS_IMPORTANCE_REPEATS, seed = 1L) {
  columns <- atlas_predictor_columns(test)
  found <- test$presence == 1L
  auc_of <- function(data) {
    scores <- score(model, data[, columns, drop = FALSE])
    atlas_auc(scores[found], scores[!found])
  }
  whole <- auc_of(test)
  set.seed(seed)
  vapply(groups, function(shuffled) {
    shuffled <- intersect(shuffled, columns)
    if (!length(shuffled) || !is.finite(whole) || nrow(test) < 2L) {
      return(NA_real_)
    }
    falls <- vapply(seq_len(repeats), function(r) {
      mixed <- test
      # One order for every column of the group: the rows move together.
      mixed[, shuffled] <- test[sample.int(nrow(test)), shuffled, drop = FALSE]
      whole - auc_of(mixed)
    }, numeric(1))
    mean(falls)
  }, numeric(1))
}

#' Cross-validate, and measure what each predictor and layer was worth.
#'
#' Scores exactly as atlas_cross_validate does, with the same fits, and adds
#' attr(, "importance"): a data frame of kind ("predictor" or "layer"), name
#' and fall, the mean fall in held-out AUC over the folds that could be
#' scored. layers is a named list, layer -> its columns.
atlas_cross_validate_importance <- function(training, folds, fit, score,
                                            effort_at = atlas_effort_level(training),
                                            layers = list(),
                                            repeats = ATLAS_IMPORTANCE_REPEATS, seed = 1L) {
  fitted <- list()
  scores <- atlas_cross_validate(
    training, folds,
    fit = function(train) {
      model <- fit(train)
      fitted[[length(fitted) + 1L]] <<- list(model = model, cells = train$cell)
      model
    },
    score = score, effort_at = effort_at
  )
  predictors <- setdiff(atlas_predictor_columns(training), ATLAS_EFFORT_COLUMN)
  layers <- lapply(layers, intersect, predictors)
  layers <- layers[lengths(layers) > 0L]
  groups <- c(
    stats::setNames(as.list(predictors), paste0("predictor\r", predictors)),
    if (length(layers)) stats::setNames(layers, paste0("layer\r", names(layers)))
  )
  held_score <- atlas_score_at_effort(score, effort_at)
  falls <- lapply(seq_along(fitted), function(i) {
    test <- training[!training$cell %in% fitted[[i]]$cells, , drop = FALSE]
    atlas_permutation_falls(fitted[[i]]$model, test, groups, held_score,
                            repeats = repeats, seed = seed + i)
  })
  importance <- if (length(falls) && length(groups)) {
    mean_fall <- rowMeans(do.call(cbind, falls), na.rm = TRUE)
    parts <- strsplit(names(groups), "\r", fixed = TRUE)
    data.frame(
      kind = vapply(parts, `[[`, character(1), 1L),
      name = vapply(parts, `[[`, character(1), 2L),
      fall = round(as.numeric(mean_fall), 4),
      stringsAsFactors = FALSE
    )
  } else {
    data.frame(kind = character(), name = character(), fall = numeric(),
               stringsAsFactors = FALSE)
  }
  importance$fall[is.nan(importance$fall)] <- NA_real_
  attr(scores, "importance") <- importance
  scores
}

#' Importance across a study's taxa: for each arm, kind and name, how many
#' taxa had the predictor in their model, the mean fall in held-out AUC with
#' its standard error, the share of taxa where shuffling it cost anything at
#' all, and the same by guild group (ectomycorrhizal or not).
atlas_importance_summary <- function(rows) {
  scored <- Filter(function(r) identical(r$status, "scored"), rows)
  long <- do.call(rbind, c(list(NULL), unlist(lapply(scored, function(r) {
    lapply(r$arms, function(a) {
      if (!length(a$importance)) return(NULL)
      data.frame(
        taxon = r$taxon, arm = a$arm,
        guild = if (isTRUE(r$guild %in% ATLAS_HOST_FIRST_GUILDS)) "ectomycorrhizal" else "other",
        kind = vapply(a$importance, function(x) as.character(x$kind), character(1)),
        name = vapply(a$importance, function(x) as.character(x$name), character(1)),
        fall = vapply(a$importance, function(x) as.numeric(x$fall %||% NA_real_), numeric(1)),
        stringsAsFactors = FALSE
      )
    })
  }), recursive = FALSE)))
  if (is.null(long) || !nrow(long)) {
    return(data.frame())
  }
  long <- long[is.finite(long$fall), , drop = FALSE]
  summarise <- function(x, guild) {
    keys <- unique(x[, c("arm", "kind", "name")])
    out <- do.call(rbind, lapply(seq_len(nrow(keys)), function(i) {
      f <- x$fall[x$arm == keys$arm[i] & x$kind == keys$kind[i] & x$name == keys$name[i]]
      data.frame(
        arm = keys$arm[i], guild = guild, kind = keys$kind[i], name = keys$name[i],
        taxa = length(f), fall = round(mean(f), 4),
        fall_se = if (length(f) > 1L) round(stats::sd(f) / sqrt(length(f)), 4) else NA_real_,
        helped = round(mean(f > 0.002), 2),
        stringsAsFactors = FALSE
      )
    }))
    out[order(out$arm, out$kind, -out$fall), , drop = FALSE]
  }
  out <- rbind(
    summarise(long, "all"),
    do.call(rbind, lapply(split(long, long$guild), function(x) summarise(x, x$guild[1])))
  )
  rownames(out) <- NULL
  out
}

# Layers measured and shown as one: the host genera, the further genera and
# the species are all host trees, shuffled together and listed under one name
# (Steve, 2026-10-06), so a model's trees are not split across headings.
ATLAS_LAYER_GROUPS <- c(hostsdecay = "hosts", hostspecies = "hosts")

#' The layer each predictor belongs to, from the grid's layer bands. A
#' predictor no layer lists belongs to "other". Layers in ATLAS_LAYER_GROUPS
#' answer as the layer they are grouped under.
atlas_layer_of <- function(predictors, bands = list(), groups = ATLAS_LAYER_GROUPS) {
  owner <- stats::setNames(rep("other", length(predictors)), predictors)
  for (id in names(bands)) {
    owner[intersect(predictors, bands[[id]])] <- if (id %in% names(groups)) groups[[id]] else id
  }
  owner
}

#' The groups a fitted model is shuffled by: every predictor it was given, one
#' by one, and every layer it drew from, all of that layer's predictors
#' together. Effort is left out; it is held fixed when a model is scored.
atlas_importance_groups <- function(predictors, layer_of) {
  predictors <- setdiff(predictors, ATLAS_EFFORT_COLUMN)
  layers <- split(predictors, layer_of[predictors])
  c(stats::setNames(as.list(predictors), paste0("predictor\r", predictors)),
    stats::setNames(layers, paste0("layer\r", names(layers))))
}

# A fall in held-out AUC smaller than this is not read as an effect.
ATLAS_IMPORTANCE_FLOOR <- 0.002

#' What a model owed to each layer and each predictor, as stored with it.
#'
#' falls is a matrix, one row per group (as named by atlas_importance_groups),
#' one column per scored fold. Each layer carries its predictors, both sorted
#' by the mean fall in held-out AUC; sd is between folds.
atlas_importance_table <- function(falls, layer_of) {
  if (is.null(falls) || !length(falls)) {
    return(NULL)
  }
  parts <- strsplit(rownames(falls), "\r", fixed = TRUE)
  kind <- vapply(parts, `[[`, character(1), 1L)
  name <- vapply(parts, `[[`, character(1), 2L)
  mean_fall <- apply(falls, 1, function(v) if (all(is.na(v))) NA_real_ else mean(v, na.rm = TRUE))
  sd_fall <- apply(falls, 1, function(v) if (sum(is.finite(v)) < 2L) NA_real_ else stats::sd(v, na.rm = TRUE))
  scored <- apply(falls, 1, function(v) sum(is.finite(v)))
  entry <- function(i, labels) {
    # Whether the fall is told apart from nothing: more than twice its
    # standard error between folds, and more than the smallest step a few
    # hundred sites can register.
    se <- if (is.finite(sd_fall[[i]])) sd_fall[[i]] / sqrt(scored[[i]]) else NA_real_
    clear <- is.finite(mean_fall[[i]]) && mean_fall[[i]] > ATLAS_IMPORTANCE_FLOOR &&
      (!is.finite(se) || mean_fall[[i]] > 2 * se)
    list(name = name[[i]], label = atlas_label(name[[i]], labels),
         fall = round(mean_fall[[i]], 4), sd = round(sd_fall[[i]], 4), clear = clear)
  }
  layers <- which(kind == "layer")
  out <- lapply(layers, function(i) {
    # unname: a named list would be written as a JSON object, not an array.
    members <- unname(which(kind == "predictor" & unname(layer_of[name]) == name[[i]]))
    members <- members[order(-mean_fall[members], na.last = TRUE)]
    c(entry(i, ATLAS_LAYER_LABELS),
      list(predictors = lapply(members, entry, labels = ATLAS_PREDICTOR_LABELS)))
  })
  out[order(-vapply(out, function(x) x$fall %||% NA_real_, numeric(1)), na.last = TRUE)]
}
