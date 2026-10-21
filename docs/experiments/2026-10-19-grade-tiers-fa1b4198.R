# Read-only: how a release's maps grade, and why most are not "strong" — for
# deciding looser map tiers (Steve, 2026-10-13). No refits, no store writes.
#
# On atlas-box, in the Atlas image, with the store env (arguments by env var):
#   GRADE_TIERS_RUN=1 ATLAS_RELEASE=20261013T155140Z-026d3a26 \
#     GRADE_TIERS_OUT=/home/ubuntu/seamcheck/grade-tiers Rscript grade_tiers.R
#
# Reads the release JSON, its occurrences/taxa-latest.json, and every model's
# metrics JSON (one small object each). Prints the tables and writes two
# CSVs: <out>-models.csv (one row per model) and <out>-taxa.csv (one row per
# taxon). Taxon names and numbers only, no places.
#
# Grade rules (R/map.R atlas_map_grade, R/fit.R atlas_skill):
#   strong  passed: shifted-null AUC p <= 0.05 AND pooled held-out Boyce > 0
#   weak    not passed, but held-out AUC > 0.5 and Boyce > 0 (or passed
#           scattered nulls only, a fit from before the switch)
#   failed  otherwise; untested: no null test
# The null test is sequential (stops once 5 nulls beat the map): p is then
# 5 / nulls scored (Besag-Clifford), else (1 + beaten) / (1 + nulls).
#
# Looser tiers (plan-map-tiers, E24; nothing in production changes):
#   strong      as today
#   moderate    not strong; shift p <= 0.20 with 25+ nulls scored, Boyce > 0,
#               held-out AUC > 0.5
#   indicative  not strong or moderate; AUC > 0.5 and Boyce > 0
#   failed      the rest; untested: no null test
#   moderate-z  (variant) not strong; z = (AUC - null mean) / null SD >= 1
#               and Boyce > 0
# A taxon's tier is its best model's.

ns <- asNamespace("mycomapatlas")
`%||%` <- function(a, b) if (is.null(a)) b else a

GT_BANDS <- c("3-4" = 3, "5-9" = 5, "10-19" = 10, "20-49" = 20, "50-99" = 50, "100+" = 100)
GT_GRADES <- c("strong", "weak", "failed", "untested")

gt_band <- function(n) {
  n <- as.numeric(n)
  out <- rep(NA_character_, length(n))
  for (i in seq_along(GT_BANDS)) out[!is.na(n) & n >= GT_BANDS[[i]]] <- names(GT_BANDS)[[i]]
  factor(out, levels = names(GT_BANDS))
}

gt_read_json <- function(store, entry) {
  if (is.null(entry)) return(NULL)
  file <- tempfile(fileext = ".json")
  on.exit(unlink(file), add = TRUE)
  tryCatch({
    store$get(ns$atlas_object_key(entry$sha256), file)
    jsonlite::fromJSON(file, simplifyVector = FALSE)
  }, error = function(e) NULL)
}

gt_num <- function(x) if (is.null(x) || !length(x)) NA_real_ else suppressWarnings(as.numeric(unlist(x))[1])

#' One row per model from its metrics.
gt_model_row <- function(entry, metrics) {
  null <- metrics$null %||% list()
  observed <- gt_num(null$observed_auc)
  mean_null <- gt_num(null$auc_mean)
  sd_null <- gt_num(null$auc_sd)
  data.frame(
    algorithm = entry$algorithm, taxon = entry$taxon,
    sites = gt_num(entry$presences %||% metrics$presences),
    grade = as.character(entry$grade %||% metrics$grade %||% NA),
    skill = as.character(metrics$skill %||% NA),
    map_withheld = isTRUE(metrics$map_withheld),
    design = as.character(null$design %||% NA),
    auc = gt_num(metrics$auc_mean), boyce = gt_num(metrics$boyce),
    null_reps = gt_num(null$reps), null_drawn = gt_num(null$drawn),
    null_stopped_early = isTRUE(null$stopped_early), null_p = gt_num(null$auc_p),
    null_observed_auc = observed, null_auc_mean = mean_null, null_auc_sd = sd_null,
    z = if (is.finite(observed) && is.finite(mean_null) && is.finite(sd_null) && sd_null > 0)
      (observed - mean_null) / sd_null else NA_real_,
    stringsAsFactors = FALSE
  )
}

#' Which strong criterion a model failed: the shifted-null p (<= 0.05) and
#' the pooled held-out Boyce (> 0), as atlas_skill tests them.
gt_fails <- function(grade, p, boyce) {
  p_fail <- !is.na(p) & p > 0.05
  b_fail <- !(is.finite(boyce) & boyce > 0)
  ifelse(grade %in% "strong", "",
  ifelse(is.na(p), "no null test",
  ifelse(p_fail & b_fail, "both",
  ifelse(p_fail, "shift-null p > 0.05",
  ifelse(b_fail, "Boyce <= 0", "passed, but scattered nulls only")))))
}

GT_TIERS <- c("strong", "moderate", "indicative", "failed", "untested")

#' The plan's tiers, from stored fields only. The p must come from shifted
#' nulls: a fit graded against scattered nulls has no shift p to loosen.
gt_tier <- function(grade, design, p, auc, boyce, nulls = rep(Inf, length(p))) {
  ok <- is.finite(auc) & auc > 0.5 & is.finite(boyce) & boyce > 0
  shift <- design %in% "shift"
  # 25 or more nulls scored (equivalent to p <= 0.20 for an early stop; a
  # test that ran out of draws with fewer is not loosened).
  enough <- !is.na(nulls) & nulls >= 25
  out <- ifelse(grade %in% "strong", "strong",
         ifelse(grade %in% "untested" | is.na(p), "untested",
         ifelse(shift & p <= 0.20 & enough & ok, "moderate",
         ifelse(ok, "indicative", "failed"))))
  factor(out, levels = GT_TIERS)
}

#' The continuous variant: not strong, z >= 1 on shifted nulls, Boyce > 0.
gt_moderate_z <- function(grade, design, z, boyce) {
  !(grade %in% "strong") & design %in% "shift" & is.finite(z) & z >= 1 & is.finite(boyce) & boyce > 0
}

gt_iqr <- function(x) {
  x <- x[is.finite(x)]
  if (!length(x)) return("-")
  q <- stats::quantile(x, c(0.25, 0.5, 0.75), names = FALSE)
  sprintf("%.3f [%.3f, %.3f] n=%d", q[2], q[1], q[3], length(x))
}

gt_print <- function(title, x) {
  cat("\n== ", title, " ==\n", sep = "")
  print(x)
}

grade_tiers <- function(store, release_id, grid = "draft", out = "grade-tiers", quiet = FALSE) {
  release <- ns$atlas_store_text(store, paste0("releases/", grid, "/", release_id, ".json"))
  files <- stats::setNames(release$files, vapply(release$files, function(f) f$path, ""))
  entries <- Filter(function(e) !isTRUE(e$refused), release$index)
  refused <- Filter(function(e) isTRUE(e$refused), release$index)
  if (!quiet) message("release ", release_id, ": ", length(entries), " models, ", length(refused), " refusals")
  rows <- vector("list", length(entries))
  for (i in seq_along(entries)) {
    e <- entries[[i]]
    m <- gt_read_json(store, files[[ns$atlas_model_relpaths(e$taxon, grid, e$algorithm, ".json")]]) %||% list()
    rows[[i]] <- gt_model_row(e, m)
    if (!quiet && i %% 1000 == 0) message("  ", i, " metrics read")
  }
  d <- do.call(rbind, rows)
  d$band <- gt_band(d$sites)
  d$grade <- factor(d$grade, levels = GT_GRADES)
  d$fails <- gt_fails(d$grade, d$null_p, d$boyce)
  d$tier <- gt_tier(as.character(d$grade), d$design, d$null_p, d$auc, d$boyce, d$null_reps)
  d$moderate_z <- gt_moderate_z(as.character(d$grade), d$design, d$z, d$boyce)

  # 1. Grade x learner x band, and the best grade per taxon.
  cat("\n#### 1. Models by grade x learner x site band\n")
  for (alg in sort(unique(d$algorithm))) {
    gt_print(paste("learner", alg), with(d[d$algorithm == alg, ], table(band, grade, useNA = "no")))
  }
  gt_print("all learners", with(d, table(band, grade)))
  rank <- stats::setNames(seq_along(GT_GRADES), GT_GRADES)
  best <- do.call(rbind, lapply(split(d, d$taxon), function(x) {
    k <- which.min(rank[as.character(x$grade)])
    tier_rank <- stats::setNames(seq_along(GT_TIERS), GT_TIERS)
    data.frame(taxon = x$taxon[1], sites = max(x$sites, na.rm = TRUE), best_grade = as.character(x$grade[k]),
               best_tier = as.character(x$tier[which.min(tier_rank[as.character(x$tier)])]),
               any_moderate_z = any(x$moderate_z), any_strong = any(x$grade %in% "strong"),
               best_learner = x$algorithm[k], models = nrow(x),
               best_z = suppressWarnings(max(x$z, na.rm = TRUE)), stringsAsFactors = FALSE)
  }))
  best$best_z[!is.finite(best$best_z)] <- NA
  best$band <- gt_band(best$sites)
  best$best_grade <- factor(best$best_grade, levels = GT_GRADES)
  gt_print("taxa by best grade (any learner) x band", with(best, table(band, best_grade)))

  # 2. Which criterion a non-strong model failed.
  cat("\n#### 2. Non-strong models: which criterion failed\n")
  ns_rows <- d[d$grade != "strong", ]
  gt_print("by learner", with(ns_rows, table(algorithm, fails)))
  gt_print("by band", with(ns_rows, table(band, fails)))

  # 3. Shift-null p of non-strong models; AUC and Boyce by grade x band.
  cat("\n#### 3. Shift-null p (non-strong; sequential, stops at 5 exceedances) and held-out scores\n")
  pcut <- cut(ns_rows$null_p, c(-Inf, 0.05, 0.10, 0.20, 0.30, Inf),
              labels = c("<=0.05 (Boyce failed)", "0.05-0.10", "0.10-0.20", "0.20-0.30", ">0.30"))
  gt_print("p bands by learner", table(ns_rows$algorithm, addNA(pcut)))
  gt_print("p bands by site band", table(ns_rows$band, addNA(pcut)))
  cum <- sapply(c(0.10, 0.20, 0.30), function(t) sum(ns_rows$null_p <= t, na.rm = TRUE))
  cat(sprintf("non-strong with p <= 0.10: %d, <= 0.20: %d, <= 0.30: %d (of %d)\n", cum[1], cum[2], cum[3], nrow(ns_rows)))
  cat("\nheld-out AUC, median [IQR] by grade x band\n")
  for (g in GT_GRADES) for (b in levels(d$band)) {
    x <- d[d$grade == g & d$band == b, ]
    if (nrow(x)) cat(sprintf("  %-8s %-6s AUC %s | Boyce %s\n", g, b, gt_iqr(x$auc), gt_iqr(x$boyce)))
  }

  # 4. Taxa with no model vs a model.
  cat("\n#### 4. Taxa with a model vs none\n")
  taxa <- gt_read_json(store, files[["occurrences/taxa-latest.json"]])
  coverage <- NULL
  if (!is.null(taxa)) {
    t <- data.frame(taxon = vapply(taxa, function(x) as.character(x$scientific_name), ""),
                    sites = vapply(taxa, function(x) gt_num(x$sites %||% x$localities), 0),
                    counted = if (!is.null(taxa[[1]]$sites)) "sites" else "localities", stringsAsFactors = FALSE)
    refused_taxa <- unique(vapply(refused, function(e) as.character(e$taxon), ""))
    t$status <- ifelse(t$taxon %in% best$taxon, "has a model",
                ifelse(t$sites < 3, "fewer than 3 sites",
                ifelse(t$taxon %in% refused_taxa, "refused (no model)", "3+ sites, no model or refusal")))
    t$band <- gt_band(t$sites)
    cat("site count from taxa-latest.json field:", t$counted[1], "\n")
    gt_print("taxa by status", table(t$status))
    gt_print("taxa by status x band (fewer than 3 sites has no band)", table(addNA(t$band), t$status))
    coverage <- t
  } else {
    cat("no occurrences/taxa-latest.json in the release: taxa without a model are not counted\n")
  }

  # 5. Effect size per taxon (best over its models), by band.
  cat("\n#### 5. Effect size z = (AUC - mean null AUC) / SD(null AUC), taxon's best model\n")
  for (b in levels(best$band)) {
    z <- best$best_z[best$band == b & !is.na(best$band)]
    z <- z[is.finite(z)]
    if (length(z)) {
      q <- stats::quantile(z, c(0.1, 0.25, 0.5, 0.75, 0.9), names = FALSE)
      cat(sprintf("  %-6s n=%4d  p10 %5.2f  p25 %5.2f  median %5.2f  p75 %5.2f  p90 %5.2f | z>=1: %d  z>=1.645: %d  z>=2: %d\n",
                  b, length(z), q[1], q[2], q[3], q[4], q[5], sum(z >= 1), sum(z >= 1.645), sum(z >= 2)))
    }
  }

  # 7. The plan's looser tiers (E24).
  cat("
#### 7. Looser tiers (plan-map-tiers): moderate = shift p <= 0.20 (25+ nulls before the 5th match), Boyce > 0, AUC > 0.5
")
  for (alg in sort(unique(d$algorithm))) {
    gt_print(paste("models by tier x band, learner", alg), with(d[d$algorithm == alg, ], table(band, tier)))
  }
  gt_print("models by tier x band, all learners", with(d, table(band, tier)))
  # Moderate needs a shift-null p: models graded on scattered nulls only (or
  # none) can reach indicative at most.
  gt_print("models by null design x learner (moderate needs 'shift')",
           table(d$algorithm, ifelse(is.na(d$design), "none recorded", d$design)))
  best$best_tier <- factor(best$best_tier, levels = GT_TIERS)
  gt_print("taxa by best tier x band", with(best, table(band, best_tier)))
  n_taxa <- nrow(best)
  cum <- c(strong = sum(best$best_tier == "strong"),
           `strong or moderate` = sum(best$best_tier %in% c("strong", "moderate")),
           `strong, moderate or indicative` = sum(best$best_tier %in% c("strong", "moderate", "indicative")))
  cat(sprintf("taxa with a model: %d; with a map at or above: %s
", n_taxa,
              paste(sprintf("%s %d (%.1f%%)", names(cum), cum, 100 * cum / n_taxa), collapse = "; ")))
  if (!is.null(coverage)) {
    all_taxa <- nrow(coverage)
    cat(sprintf("of all %d taxa in the pull: strong %.1f%%, strong or moderate %.1f%%, any of the three %.1f%%
",
                all_taxa, 100 * cum[1] / all_taxa, 100 * cum[2] / all_taxa, 100 * cum[3] / all_taxa))
  }
  cat(sprintf("moderate-z variant: models %d; taxa with strong or moderate-z: %d (moderate by p: %d; both: %d)
",
              sum(d$moderate_z), sum(best$any_strong | best$any_moderate_z),
              sum(best$best_tier == "moderate"), sum(best$best_tier == "moderate" & best$any_moderate_z)))
  gt_print("moderate-z vs p tier, non-strong models", with(d[d$grade != "strong", ], table(tier, moderate_z)))

  # 6. Weak maps.
  cat("\n#### 6. Weak maps (rank held-out ground better than chance; not shown to beat shifted nulls)\n")
  cat(sprintf("models graded weak: %d; taxa whose best grade is weak: %d; taxa whose best is failed: %d; strong: %d\n",
              sum(d$grade == "weak", na.rm = TRUE), sum(best$best_grade == "weak", na.rm = TRUE),
              sum(best$best_grade == "failed", na.rm = TRUE), sum(best$best_grade == "strong", na.rm = TRUE)))
  gt_print("taxa whose best grade is weak, by band", table(best$band[best$best_grade == "weak"]))
  gt_print("maps withheld (3-4 sites until they pass), by grade", with(d[d$map_withheld, ], table(grade)))

  utils::write.csv(d, paste0(out, "-models.csv"), row.names = FALSE)
  utils::write.csv(merge(best, if (!is.null(coverage)) coverage[, c("taxon", "status")] else
    data.frame(taxon = character(), status = character()), all.x = TRUE), paste0(out, "-taxa.csv"), row.names = FALSE)
  cat("\nwritten: ", out, "-models.csv, ", out, "-taxa.csv\n", sep = "")
  invisible(list(models = d, taxa = best, coverage = coverage))
}

if (identical(Sys.getenv("GRADE_TIERS_RUN"), "1")) {
  release_id <- Sys.getenv("ATLAS_RELEASE")
  if (!nzchar(release_id)) stop("set ATLAS_RELEASE")
  grade_tiers(ns$atlas_store(), release_id, out = Sys.getenv("GRADE_TIERS_OUT", "grade-tiers"))
}
