# Null models that keep a taxon's clustering, a test that stops early, and
# a correction for testing thousands of taxa.
#
# The null test asks whether a map beats species that know nothing. The
# production nulls ("scatter") draw detection sites one by one, busier sites
# more often. Real detections are not scattered: a lineage named for the
# Pacific Northwest sits in the Pacific Northwest. Within a 500 km circle,
# almost any smooth predictor tells a cluster from the rest of the circle,
# and scattered nulls cannot do that (Hijmans 2012, spatial sorting bias). So
# a clustered taxon can pass the test on clustering alone.
#
# A "shift" null keeps the shape of the real pattern. Every detection is
# rotated by one random angle about their centre, and the whole pattern is
# moved to a random survey site (busier sites more often). Each moved point
# then snaps to a survey site, never two to the same one. A draw is rejected
# when more than a fifth of its points land further than ATLAS_NULL_SNAP_KM
# from any free site, which is moving a cluster into ground nobody surveyed.
# A big pattern spread over several regions can rarely be moved whole without
# that (a 205-site species: every one of 200 tries rejected), and scattering
# it instead would quietly turn the test back into the one it replaces. So
# after ATLAS_NULL_SHIFT_TRIES rejections the null takes the try that left the
# fewest points far from a site, snaps those to the nearest free site wherever
# it is, and says so (best_effort, with the share of points that moved far).
# "shift-effort" snaps each point among the
# nearest free sites within snap distance in proportion to their records, so
# the nulls keep both the clustering and the pull of busy sites.
#
# With 19 nulls the smallest p is 0.05, so a single tie fails a map. The
# sequential test (Besag & Clifford 1991) draws up to 99, in batches, and
# stops once stop_after nulls have done at least as well as the map: p is
# then stop_after over the nulls drawn. Stopping after 5 gives the same pass
# or fail at 0.05 as drawing all 99, at a fraction of the cost for maps that
# fail.
#
# Near the pass line one draw of 99 decides little: a map that 5% of nulls
# beat passes 45% of the time. So production goes on (ATLAS_NULL_EXTEND,
# Steve 2026-11-19): a first stage of 99 that passed with at most one null
# as good, or stopped before its 50th null, stands; otherwise the test draws
# up to 199, stopping after 10, and passes at p = (1 + k) / 200 <= 0.05.
# The pass rule is unchanged, and the exact size (a map that knows nothing is
# exchangeable with its nulls) is 0.0497, against 0.05 for 99 alone. (It was
# 499, stopping after 25, until 2026-11-20: a near-line Maxent with hundreds
# of sites could then take longer than a worker's deadline.)
#
# Pooled over fold splits, the test passed more than its share of maps that
# know nothing when they have many sites: on E1's virtual species with no
# habitat signal, 12.6% of Maxent and 11.2% of random-forest maps at 200 or
# more sites (2026-11-21), against about 5% below. So from 200 sites
# production runs a stricter test in place of the extension
# (ATLAS_NULL_LARGE, atlas_null_plan; Steve 2026-11-22): 199 nulls with no
# clear pass on the first 99, stopping after 3, passing at p <= 0.015, that
# is at most 2 of 199 as good.
#
# One fold split decides a lot too: a record that changes one block re-deals
# every fold, and at 10 to 60 sites the map's score against its nulls moves
# with the split it got (paper E11, 2026-11-19). So production scores the map
# and every null on ATLAS_NULL_SPLITS fold splits and compares their means
# (atlas_null_fold_splits). The first split is the map's own; the others are
# dealt from further seeds, with the same block size.
#
# Across thousands of taxa, 5% of maps of species that know nothing would
# pass at p = 0.05. atlas_null_qvalues gives Benjamini-Hochberg q-values, the
# false discovery rate at which each map would pass.

ATLAS_NULL_DESIGNS <- c("scatter", "shift", "shift-effort")
# How far a moved point may land from a free survey site, in km, and the
# share of points that may land further before a draw is rejected.
ATLAS_NULL_SNAP_KM <- 25
ATLAS_NULL_FAR_SHARE <- 0.2
# Draws of a shift null before it falls back to a scattered one.
ATLAS_NULL_SHIFT_TRIES <- 200L
# Free sites a shift-effort point chooses among.
ATLAS_NULL_SNAP_CHOICES <- 5L

#' One null design, refusing names Atlas does not know.
atlas_null_design <- function(design) {
  design <- as.character(design %||% "scatter")[[1]]
  if (!design %in% ATLAS_NULL_DESIGNS) {
    stop("unknown null design '", design, "': use one of ",
         paste(ATLAS_NULL_DESIGNS, collapse = ", "), call. = FALSE)
  }
  design
}

#' Snap moved points to survey sites, one site each.
#'
#' Points are taken in random order; each takes the nearest free site, or,
#' with weight, one of the choices nearest free sites within snap_km (always
#' at least the nearest) in proportion to weight. Returns the row of each
#' point's site, or NULL when more than far_share of the points land further
#' than snap_km from a free site. With strict = FALSE every point is placed
#' however far it lands, and attr(, "far_share") says how many landed far.
atlas_snap_to_sites <- function(px, py, sx, sy, weight = NULL, snap_km = ATLAS_NULL_SNAP_KM,
                                far_share = ATLAS_NULL_FAR_SHARE,
                                choices = ATLAS_NULL_SNAP_CHOICES, strict = TRUE) {
  n <- length(px)
  if (n > length(sx)) return(NULL)
  allowed_far <- floor(far_share * n)
  used <- logical(length(sx))
  chosen <- integer(n)
  far <- 0L
  for (i in sample.int(n)) {
    d <- sqrt((sx - px[[i]])^2 + (sy - py[[i]])^2) / 1000
    d[used] <- Inf
    nearest <- which.min(d)
    j <- nearest
    if (!is.null(weight)) {
      candidates <- utils::head(order(d), choices)
      candidates <- candidates[d[candidates] <= max(snap_km, d[[nearest]])]
      if (length(candidates) > 1L) j <- candidates[[sample.int(length(candidates), 1L, prob = weight[candidates])]]
    }
    if (d[[j]] > snap_km) {
      far <- far + 1L
      if (isTRUE(strict) && far > allowed_far) return(NULL)
    }
    used[[j]] <- TRUE
    chosen[[i]] <- j
  }
  attr(chosen, "far_share") <- far / n
  chosen
}

#' One shifted null: the real detections rotated, moved and snapped to
#' sites. attr(, "tries") says how many draws it took; attr(, "best_effort")
#' is TRUE when every draw was rejected and the one that left the fewest
#' points far from a site was placed anyway, and attr(, "far_share") is the
#' share of points that landed further than snap_km from a free site.
atlas_null_shift <- function(training, seed, effort = FALSE, tries = ATLAS_NULL_SHIFT_TRIES,
                             snap_km = ATLAS_NULL_SNAP_KM, far_share = ATLAS_NULL_FAR_SHARE) {
  found <- which(training$presence == 1L)
  weight <- if (ATLAS_EFFORT_COLUMN %in% names(training)) {
    exp(training[[ATLAS_EFFORT_COLUMN]])
  } else {
    rep(1, nrow(training))
  }
  dx <- training$x[found] - mean(training$x[found])
  dy <- training$y[found] - mean(training$y[found])
  allowed_far <- floor(far_share * length(found))
  place <- function(px, py, strict) {
    atlas_snap_to_sites(px, py, training$x, training$y, weight = if (isTRUE(effort)) weight,
                        snap_km = snap_km, far_share = far_share, strict = strict)
  }
  finish <- function(snapped, try, best_effort) {
    presence <- integer(nrow(training))
    presence[snapped] <- 1L
    attr(presence, "tries") <- try
    attr(presence, "best_effort") <- best_effort
    attr(presence, "far_share") <- attr(snapped, "far_share") %||% 0
    presence
  }
  set.seed(seed)
  best <- NULL
  for (try in seq_len(tries)) {
    angle <- stats::runif(1, 0, 2 * pi)
    anchor <- sample.int(nrow(training), 1L, prob = weight)
    px <- training$x[[anchor]] + dx * cos(angle) - dy * sin(angle)
    py <- training$y[[anchor]] + dx * sin(angle) + dy * cos(angle)
    # A point far from every site is far from every free one too, so a draw
    # this count already rejects is not worth snapping point by point.
    far <- sum(atlas_nearest_km(px, py, training$x, training$y) > snap_km)
    if (is.null(best) || far < best$far) best <- list(far = far, px = px, py = py, state = atlas_rng_state())
    if (far > allowed_far) next
    snapped <- place(px, py, strict = TRUE)
    if (!is.null(snapped)) return(finish(snapped, try, FALSE))
  }
  # Snapped from the random state it was drawn in, so the same seed gives the
  # same null.
  atlas_rng_restore(best$state)
  finish(place(best$px, best$py, strict = FALSE), tries, TRUE)
}

#' A null's detections under any design.
atlas_null_draw <- function(training, n, seed, design = "scatter") {
  switch(
    atlas_null_design(design),
    scatter = atlas_null_presence(training, n, seed),
    shift = atlas_null_shift(training, seed, effort = FALSE),
    "shift-effort" = atlas_null_shift(training, seed, effort = TRUE)
  )
}

#' The fold splits a pooled null test scores on: the map's own (fold_ids),
#' then splits - 1 more dealt by atlas_spatial_folds with the same block size
#' from seeds seed + 100, seed + 200, ... The random number stream is put back
#' as it was, so nothing fitted after this sees a different one.
atlas_null_fold_splits <- function(x, y, fold_ids, k, block_km, seed, presence, splits = ATLAS_NULL_SPLITS) {
  if (splits <= 1L) return(list(fold_ids))
  stream <- atlas_rng_state()
  on.exit(atlas_rng_restore(stream), add = TRUE)
  c(list(fold_ids), lapply(seq_len(splits - 1L), function(i) {
    atlas_spatial_folds(x, y, k = k, block_km = block_km, seed = seed + 100L * i, presence = presence)
  }))
}

#' Whether a first test of reps nulls ended near the pass line, so the test
#' goes on to more (extend, production's ATLAS_NULL_EXTEND): it stopped at its
#' stop_after'th null on the near_from'th scored null or later (p at most
#' stop_after / near_from), or it did not stop and more than clear_pass nulls
#' did as well as the taxon.
atlas_null_near_line <- function(scored, above, stopped, extend) {
  if (isTRUE(stopped)) scored >= extend$near_from else above > extend$clear_pass
}

#' The test a taxon of n detection sites gets: reps nulls stopping after
#' stop_after, with extend near the line, at level alpha. With large
#' (production's ATLAS_NULL_LARGE), a taxon of large$sites or more whose test
#' is production's (reps is extend$from, the first stage the extension was
#' calibrated for) gets large$reps nulls instead, stopping after
#' large$stop_after, with no extension, at large$alpha; is_large says so.
#' Without large, or below its sites, the test is as asked, at
#' ATLAS_SKILL_ALPHA.
atlas_null_plan <- function(n, reps, stop_after, extend = NULL, large = NULL) {
  is_large <- !is.null(large) && !is.null(extend) &&
    identical(as.integer(reps), as.integer(extend$from)) && isTRUE(n >= large$sites)
  if (!is_large) {
    return(list(reps = as.integer(reps), stop_after = as.integer(stop_after), extend = extend,
                large = FALSE, alpha = ATLAS_SKILL_ALPHA))
  }
  list(reps = as.integer(large$reps), stop_after = as.integer(large$stop_after), extend = NULL,
       large = TRUE, alpha = as.numeric(large$alpha))
}

#' Draw nulls in batches until reps are scored or stop_after of them have
#' done at least as well as the taxon, then, when extend is given and the
#' first reps ended near the pass line, on to extend$to, stopping at
#' extend$stop_after.
#'
#' fetch(draws) scores the nulls of those draw numbers, in order: a list of
#' c(auc, boyce), auc NA for a null that could not be scored. A null that
#' fails is replaced, up to twice as many draws as nulls wanted. Results are
#' taken in draw order and counting stops exactly where a one-at-a-time test
#' would, so the batch size changes nothing but speed. drawn counts the
#' draws the test used, a failed one included; draws scored in the last batch
#' but never reached are not counted, and used holds the results of those it
#' used, in order.
#'
#' p is stop_after over the nulls scored when the test stopped, else
#' (1 + nulls at least as good) / (1 + nulls scored), for whichever stage
#' decided. extend applies only to a first stage of extend$from nulls, the
#' size it was calibrated for.
atlas_null_sequence <- function(observed_auc, fetch, reps = 99L, stop_after = 5L,
                                batch = 10L, extend = NULL) {
  # batch may be a function, asked before each batch (the null test's batch
  # grows with the processes it may use).
  batch_size <- function() as.integer(if (is.function(batch)) batch() else batch)
  aucs <- numeric()
  boyces <- numeric()
  above <- 0L
  draw <- 0L
  # Scored but not yet counted: the rest of a batch when a stage ends, which
  # the next stage counts first, so the nulls are the same whatever the batch.
  pending <- list()
  used <- list()
  draw_until <- function(want, enough, cap) {
    while (length(aucs) < want && above < enough) {
      if (!length(pending)) {
        if (draw >= cap) break
        take <- seq.int(draw + 1L, min(draw + batch_size(), cap))
        draw <<- take[[length(take)]]
        pending <<- fetch(take)
      }
      result <- pending[[1]]
      pending <<- pending[-1]
      used[[length(used) + 1L]] <<- result
      if (!is.finite(result[["auc"]])) next
      aucs <<- c(aucs, result[["auc"]])
      boyces <<- c(boyces, result[["boyce"]])
      if (result[["auc"]] >= observed_auc) above <<- above + 1L
    }
  }
  p_of <- function(stopped, enough) {
    if (!length(aucs)) NA_real_ else if (stopped) enough / length(aucs) else (1 + above) / (1 + length(aucs))
  }
  draw_until(reps, stop_after, 2L * reps)
  stopped <- above >= stop_after
  first <- list(reps = length(aucs), p = p_of(stopped, stop_after))
  p <- first$p
  extended <- !is.null(extend) && identical(as.integer(reps), as.integer(extend$from)) &&
    length(aucs) > 0L && atlas_null_near_line(length(aucs), above, stopped, extend)
  if (extended) {
    draw_until(extend$to, extend$stop_after, 2L * extend$to)
    stopped <- above >= extend$stop_after
    p <- p_of(stopped, extend$stop_after)
  }
  list(aucs = aucs, boyces = boyces, above = above, drawn = length(used), used = used, stopped = stopped, p = p,
       extended = extended, first = first)
}

#' The null test with any design, drawing nulls in batches until reps are
#' scored or stop_after of them have done at least as well as the taxon, and,
#' with extend, on to more nulls when that first stage ends near the pass
#' line (atlas_null_sequence).
#'
#' Same procedure as atlas_null_test (same sites, folds and untuned
#' settings; a failed null is replaced, up to 2 x reps draws), and the same
#' result, with the design, how many nulls were drawn, whether the test
#' stopped early, how many shifted nulls were placed best-effort, and the mean
#' share of their points that landed far from a site. With extend, also
#' whether the test went on past its first stage, and that stage's nulls and p.
#'
#' With large (production's ATLAS_NULL_LARGE) a taxon with many sites gets its
#' stricter test instead (atlas_null_plan), and the result says whether it did
#' (large) and the level its p is read at (alpha, which atlas_skill uses).
#'
#' folds is one fold split, or a list of them (production's pooled test,
#' atlas_null_fold_splits): the taxon and every null are then scored on each
#' split, and compared by the mean over the splits; observed_auc is that mean,
#' and the result says how many splits were used and the first split's AUC.
#' One split gives exactly the single-split test.
#'
#' A batch of nulls is scored across several processes when the machine has
#' cores to spare (atlas_null_cores: a pool's fits that have finished leave
#' theirs idle), each process scoring a run of the batch's nulls
#' (atlas_null_score). Each null's fits are seeded from its own draw, and the
#' random stream is left as the map's own scores left it, so the result is
#' the same however many processes score the nulls, and whatever the batch.
atlas_null_test_sequential <- function(training, folds, algo, reps = 99L, seed = 1L,
                                       design = "scatter", stop_after = 5L, batch = 10L,
                                       extend = NULL, cores = atlas_null_cores,
                                       map = atlas_null_fork_map, large = NULL) {
  design <- atlas_null_design(design)
  if (!reps) return(list(reps = 0L))
  params <- atlas_null_params(algo, training)
  n <- sum(training$presence == 1L)
  plan <- atlas_null_plan(n, reps, stop_after, extend, large)
  summarise <- function(scores) {
    if (is.null(scores)) return(c(auc = NA_real_, boyce = NA_real_))
    c(auc = mean(scores$auc, na.rm = TRUE), boyce = atlas_pooled_boyce(scores))
  }
  # Each null says whether it was placed best-effort, and how far its points
  # moved, with its scores: counted for the nulls the test used, so a batch's
  # unused nulls (more of them with more processes) change nothing.
  null_table <- function(draw) {
    null <- training
    null$presence <- atlas_null_draw(training, n, seed + 1000L + draw, design)
    attr(null, "best_effort") <- isTRUE(attr(null$presence, "best_effort"))
    attr(null, "far_share") <- attr(null$presence, "far_share") %||% NA_real_
    attributes(null$presence) <- NULL
    attr(null, "draw") <- draw
    null
  }
  # A null's fits draw from the random stream (boosted trees do): seeded from
  # its draw, its scores do not depend on which nulls were scored before it
  # in the same process.
  seeded <- function(table) {
    draw <- attr(table, "draw")
    if (!is.null(draw)) set.seed(seed + 2000L + as.integer(draw))
    table
  }
  run_split <- function(tables, split) {
    if (atlas_shares_features(algo)) {
      features <- atlas_feature_cache()
      fit <- atlas_fit_sharing(algo, params, seed, features)
      runs <- lapply(tables, function(table) {
        list(training = table, fit = fit, score = algo$score, effort_at = atlas_effort_level(table))
      })
      # Fitted fold by fold across the tables: seeded once, from the first.
      if (length(tables)) seeded(tables[[1]])
      lapply(atlas_cross_validate_by_fold(runs, split, features), summarise)
    } else {
      lapply(tables, function(table) summarise(tryCatch(
        atlas_cross_validate(seeded(table), split,
                             fit = function(train) algo$fit(train, params, seed, tuning = TRUE),
                             score = algo$score, effort_at = atlas_effort_level(table)),
        error = function(e) NULL
      )))
    }
  }
  # Several fold splits: every table is scored on each, and its score is the
  # mean over them. A null that cannot be scored on one of them is a null that
  # failed, and is replaced.
  run_tables <- function(tables) {
    per_split <- lapply(splits, function(split) run_split(tables, split))
    if (length(per_split) == 1L) return(per_split[[1]])
    lapply(seq_along(tables), function(i) {
      scores <- vapply(per_split, function(scored) scored[[i]], numeric(2))
      c(auc = mean(scores["auc", ]), boyce = mean(scores["boyce", ]))
    })
  }
  splits <- if (is.list(folds)) folds else list(folds)
  pooled <- length(splits) > 1L
  stream <- atlas_rng_state()
  started <- proc.time()[["elapsed"]]
  by_split <- lapply(splits, function(split) run_split(list(training), split)[[1]])
  # What one table costs on every split: a forked run of nulls that takes
  # many times that is taken to be stuck (atlas_null_fork_map).
  per_table <- proc.time()[["elapsed"]] - started
  if (!is.finite(by_split[[1]][["auc"]])) {
    atlas_rng_restore(stream)
    return(list(reps = 0L))
  }
  # Whatever the nulls draw, the stream goes on from where the map's own
  # scores left it, as it does when the nulls are scored in other processes.
  after_map <- atlas_rng_state()
  on.exit(atlas_rng_restore(after_map), add = TRUE)
  # A further split the taxon itself cannot be scored on is left out before
  # any null is drawn, for the taxon and every null alike.
  scored_on <- vapply(by_split, function(x) is.finite(x[["auc"]]), logical(1))
  splits <- splits[scored_on]
  observed <- c(auc = mean(vapply(by_split[scored_on], function(x) x[["auc"]], numeric(1))),
                boyce = mean(vapply(by_split[scored_on], function(x) x[["boyce"]], numeric(1))))
  using <- 1L
  # Once a forked run is lost or stuck, this test forks no more: its nulls
  # are scored here, slower but sure.
  forking <- TRUE
  batch_now <- function() {
    using <<- if (forking) as.integer(cores()) else 1L
    if (using > 1L) max(as.integer(batch), 2L * using) else as.integer(batch)
  }
  fetch <- function(take) {
    tables <- lapply(take, null_table)
    run_size <- ceiling(length(tables) / max(1L, using))
    scores <- atlas_null_score(tables, run_tables, using, map = map,
                               timeout = max(ATLAS_NULL_FORK_MIN_SECONDS, ATLAS_NULL_FORK_SLACK * run_size * per_table))
    if (isTRUE(attr(scores, "lost") > 0L)) forking <<- FALSE
    Map(function(score, table) {
      c(score, best_effort = as.numeric(attr(table, "best_effort")), far_share = as.numeric(attr(table, "far_share")))
    }, scores, tables)
  }
  run <- atlas_null_sequence(observed[["auc"]], fetch, reps = plan$reps, stop_after = plan$stop_after,
                             batch = batch_now, extend = plan$extend)
  aucs <- run$aucs
  boyces <- run$boyces[is.finite(run$boyces)]
  best_effort <- sum(vapply(run$used, function(r) r[["best_effort"]], numeric(1)))
  far_shares <- vapply(run$used, function(r) r[["far_share"]], numeric(1))
  far_shares <- far_shares[is.finite(far_shares)]
  c(list(
    reps = length(aucs),
    design = design,
    settings = atlas_params_label(params),
    observed_auc = round(observed[["auc"]], 3),
    observed_boyce = round(observed[["boyce"]], 3),
    auc_mean = round(mean(aucs), 3),
    auc_sd = round(stats::sd(aucs), 3),
    auc_p = round(run$p, 4),
    boyce_mean = if (length(boyces)) round(mean(boyces), 3) else NA_real_,
    stopped_early = run$stopped,
    drawn = run$drawn,
    best_effort = as.integer(best_effort),
    far_share = if (length(far_shares)) round(mean(far_shares), 3) else NA_real_
  ), if (!is.null(extend)) list(
    extended = run$extended,
    first_reps = run$first$reps,
    first_auc_p = round(run$first$p, 4)
  ), if (!is.null(large)) list(
    large = plan$large,
    alpha = plan$alpha
  ), if (pooled) list(
    splits = length(splits),
    first_split_auc = round(by_split[[1]][["auc"]], 3)
  ))
}

# ---- scoring one model's nulls in several processes -------------------------

# The most processes one model's null test uses at once. A near-line
# Maxent with hundreds of sites draws up to 199 nulls on five splits, hours
# in one process, while at the end of a shard the pool's other cores sit idle.
ATLAS_NULL_MAX_CORES <- 8L

# A forked run of nulls is given ATLAS_NULL_FORK_SLACK times what its
# tables would cost here, and never less than ATLAS_NULL_FORK_MIN_SECONDS,
# before it is taken to be stuck, killed, and scored here instead.
ATLAS_NULL_FORK_SLACK <- 20
ATLAS_NULL_FORK_MIN_SECONDS <- 120

#' How many processes the null test may use now: 1, unless this process is
#' one of a pool's (atlas_make_workers) on a machine that can fork, its BLAS
#' and OpenMP were started on one thread (ATLAS_WORKER_ENV, as a pool's
#' processes are), and the pool's scheduler says some of its processes are
#' idle (ATLAS_POOL_STATE, written by atlas_run_on_workers): then an equal
#' share of the idle ones, at most ATLAS_NULL_MAX_CORES (overridden by that
#' variable in the environment). A pool of n processes then never runs more
#' than n fits at once, so each process's memory budget
#' (ATLAS_EC2_GB_PER_FIT) holds.
#'
#' A process whose BLAS runs its own threads must not fork: a child that
#' calls into a thread pool copied mid-use can wait for ever (a test that
#' forked so hung for 8.5 hours on Linux, 2026-11-21).
atlas_null_cores <- function(state = Sys.getenv("ATLAS_POOL_STATE", unset = ""),
                             most = atlas_null_max_cores(), can_fork = .Platform$OS.type == "unix",
                             pinned = atlas_threads_pinned()) {
  if (!isTRUE(can_fork) || !isTRUE(pinned) || !nzchar(state) || most <= 1L || !file.exists(state)) return(1L)
  line <- tryCatch(readLines(state, n = 1L, warn = FALSE), error = function(e) character())
  if (!length(line)) return(1L)
  v <- suppressWarnings(as.integer(strsplit(trimws(line), "[[:space:]]+")[[1]]))
  if (length(v) != 2L || anyNA(v) || v[[1]] < 0L || v[[2]] < 1L) return(1L)
  as.integer(max(1L, min(most, 1L + v[[1]] %/% v[[2]])))
}

#' Whether this process was started with its BLAS and OpenMP on one thread,
#' as ATLAS_WORKER_ENV starts a pool's processes.
atlas_threads_pinned <- function(env = Sys.getenv) {
  all(vapply(names(ATLAS_WORKER_ENV), function(name) identical(env(name, unset = ""), "1"), logical(1)))
}

atlas_null_max_cores <- function() {
  wanted <- suppressWarnings(as.integer(Sys.getenv("ATLAS_NULL_MAX_CORES", unset = "")))
  if (is.na(wanted) || wanted < 1L) ATLAS_NULL_MAX_CORES else wanted
}

#' Score a batch of null tables with score(tables) (a list of c(auc, boyce)
#' in their order), in up to `cores` processes, each scoring a run of them
#' within `timeout` seconds. A process that is lost (killed, out of memory)
#' or stuck has its run scored here instead, so it costs time, never a null;
#' attr(, "lost") says how many runs were.
atlas_null_score <- function(tables, score, cores = 1L, map = atlas_null_fork_map, timeout = Inf) {
  cores <- min(as.integer(cores), length(tables))
  if (is.na(cores) || cores <= 1L) return(score(tables))
  runs <- split(seq_along(tables), sort(rep_len(seq_len(cores), length(tables))))
  names(runs) <- NULL
  parts <- tryCatch(map(runs, function(i) score(tables[i]), cores, timeout = timeout),
                    error = function(e) vector("list", length(runs)))
  out <- vector("list", length(tables))
  lost <- 0L
  for (r in seq_along(runs)) {
    part <- if (length(parts) >= r) parts[[r]]
    whole <- is.list(part) && length(part) == length(runs[[r]]) &&
      all(vapply(part, function(x) is.numeric(x) && length(x) == 2L, logical(1)))
    if (!whole) lost <- lost + 1L
    out[runs[[r]]] <- if (whole) part else score(tables[runs[[r]]])
  }
  attr(out, "lost") <- lost
  out
}

#' Run f over runs, one forked process each, each starting from this
#' process's random stream (mc.set.seed = FALSE), as the same work done here
#' would. A run not back within timeout seconds is killed and comes back as
#' NULL, as does one whose process died: a stuck child never holds up the
#' model, only costs it the timeout.
atlas_null_fork_map <- function(runs, f, cores, timeout = Inf) {
  jobs <- lapply(runs, function(run) parallel::mcparallel(f(run), mc.set.seed = FALSE, silent = TRUE))
  pids <- vapply(jobs, function(job) as.integer(job$pid), integer(1))
  out <- vector("list", length(runs))
  pending <- seq_along(jobs)
  deadline <- Sys.time() + timeout
  while (length(pending)) {
    left <- as.numeric(difftime(deadline, Sys.time(), units = "secs"))
    if (left <= 0) break
    got <- parallel::mccollect(jobs[pending], wait = FALSE, timeout = min(left, 5))
    for (key in names(got)) {
      i <- match(as.integer(key), pids)
      if (is.na(i) || !i %in% pending) next
      value <- got[[key]]
      if (!inherits(value, "try-error")) out[i] <- list(value)
      pending <- setdiff(pending, i)
    }
  }
  if (length(pending)) {
    tools::pskill(pids[pending], tools::SIGKILL)
    # Reaped, so no zombie is left; mccollect warns that they sent nothing.
    suppressWarnings(try(parallel::mccollect(jobs[pending], wait = TRUE), silent = TRUE))
  }
  out
}

#' Benjamini-Hochberg q-values: for each p, the false discovery rate at
#' which it would pass. NA stays NA and is not counted as a test (p.adjust
#' counts only the p-values it is given that are not NA).
atlas_null_qvalues <- function(p) {
  stats::p.adjust(as.numeric(p), method = "BH")
}
