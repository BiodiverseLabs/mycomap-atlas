# E12 reading: agreement across arms, weighted back to the release by cell,
# with Cohen's kappa on grades, and (once the block step reports) each
# cross-family difference split by whether the block changed.
#
#   ATLAS_SRC=<Atlas checkout> Rscript 2026-10-21-e12-reading.R <dir>
#
# <dir> holds: 20261013T191324Z-fa1b4198.json (the release manifest),
# a1/*.json, a2_rerun/*.json, b/*.json (each arm's results files, from
# study/<job>/), and optionally blocks-r7i/*.json and blocks-r7a/*.json.
args <- commandArgs(trailingOnly = TRUE)
dir <- if (length(args)) args[[1]] else "."
# The Atlas package source (any commit with R/studye12.R), from ATLAS_SRC.
pkgload::load_all(Sys.getenv("ATLAS_SRC", "."), quiet = TRUE)

read_arm <- function(sub) {
  files <- list.files(file.path(dir, sub), pattern = "[.]json$", full.names = TRUE)
  if (!length(files)) return(NULL)
  rows <- do.call(c, lapply(files, function(f) jsonlite::fromJSON(f, simplifyVector = FALSE)$models))
  data.frame(
    algorithm = vapply(rows, function(m) as.character(m$algorithm), ""),
    taxon = vapply(rows, function(m) as.character(m$taxon), ""),
    cell = vapply(rows, function(m) as.character(m$cell %||% NA), ""),
    band = vapply(rows, function(m) as.character(m$band %||% NA), ""),
    grade = vapply(rows, function(m) as.character(m$fit$grade %||% NA), ""),
    release_grade = vapply(rows, function(m) as.character(m$release$grade %||% NA), ""),
    identical = vapply(rows, function(m) isTRUE(m$against_release$identical), logical(1)),
    differs = vapply(rows, function(m) paste(unlist(m$against_release$differs), collapse = ","), ""),
    stringsAsFactors = FALSE)
}

manifest <- jsonlite::fromJSON(file.path(dir, "20261013T191324Z-fa1b4198.json"), simplifyVector = FALSE)
draw <- atlas_e12_draw(manifest$index)
population <- table(draw$cell)

arms <- Filter(Negate(is.null), list(a1 = read_arm("a1"), a2 = read_arm("a2_rerun"), b = read_arm("b")))
key <- function(d) paste(d$algorithm, d$taxon, sep = "|")
for (n in names(arms)) arms[[n]]$key <- key(arms[[n]])
sample <- arms[[1]]
drawn <- table(sample$cell)
weight_of <- function(cells) as.numeric(population[cells]) / as.numeric(drawn[cells])

kappa <- function(x, y, w = rep(1, length(x))) {
  levels <- sort(unique(c(x, y)))
  t <- tapply(w, list(factor(x, levels), factor(y, levels)), sum)
  t[is.na(t)] <- 0
  p <- t / sum(t)
  po <- sum(diag(p))
  pe <- sum(rowSums(p) * colSums(p))
  if (pe == 1) return(NA_real_)
  (po - pe) / (1 - pe)
}

cat("Models drawn:", nrow(sample), " cells:", length(drawn), " release models in those cells:",
    sum(population[names(drawn)]), "\n\n")
for (n in names(arms)) {
  d <- arms[[n]]
  w <- weight_of(d$cell)
  cat(sprintf("%-3s identical to release %d/%d (weighted %.4f); same grade %d/%d (weighted %.4f); kappa vs release %.4f (weighted %.4f)\n",
              n, sum(d$identical), nrow(d), sum(w * d$identical) / sum(w),
              sum(d$grade == d$release_grade), nrow(d), sum(w * (d$grade == d$release_grade)) / sum(w),
              kappa(d$release_grade, d$grade), kappa(d$release_grade, d$grade, w)))
}
pair <- function(a, b) {
  x <- arms[[a]]; y <- arms[[b]][match(arms[[a]]$key, arms[[b]]$key), ]
  w <- weight_of(x$cell)
  same <- x$grade == y$grade
  cat(sprintf("%s vs %s: same grade %d/%d (weighted %.4f), kappa %.4f (weighted %.4f)\n", a, b, sum(same), nrow(x),
              sum(w * same) / sum(w), kappa(x$grade, y$grade), kappa(x$grade, y$grade, w)))
}
if (all(c("a1", "a2") %in% names(arms))) pair("a1", "a2")
if (all(c("a1", "b") %in% names(arms))) pair("a1", "b")

if ("b" %in% names(arms)) {
  b <- arms$b
  cat("\nb's differences by learner and band:\n")
  print(with(b, table(learner = algorithm, differs = !identical)))
  print(with(b[!b$identical, ], table(band, algorithm)))
  cat("\nb's grade changes (release -> b):\n")
  print(with(b[b$grade != b$release_grade, ], table(paste(release_grade, "->", grade))))
}

blocks <- Filter(Negate(is.null), lapply(c(r7i = "blocks-r7i", r7a = "blocks-r7a"), function(sub) {
  files <- list.files(file.path(dir, sub), pattern = "[.]json$", full.names = TRUE)
  if (!length(files)) return(NULL)
  rows <- do.call(c, lapply(files, function(f) jsonlite::fromJSON(f, simplifyVector = FALSE)$models))
  data.frame(key = paste(vapply(rows, function(m) m$algorithm, ""), vapply(rows, function(m) m$taxon, ""), sep = "|"),
             block = vapply(rows, function(m) as.numeric(m$block_km %||% NA), 0),
             release_block = vapply(rows, function(m) as.numeric(m$release_block_km %||% NA), 0),
             status = vapply(rows, function(m) as.character(m$status), ""), stringsAsFactors = FALSE)
}))
if (length(blocks) == 2L && "b" %in% names(arms)) {
  m <- merge(blocks$r7i, blocks$r7a, by = "key", suffixes = c("_r7i", "_r7a"))
  m$changed <- m$block_r7i != m$block_r7a
  cat("\nFull-design models measured on both families:", nrow(m), "; block changed:", sum(m$changed, na.rm = TRUE), "\n")
  cat("r7i block equal to the release's recorded block:", sum(m$block_r7i == m$release_block_r7i, na.rm = TRUE), "of", nrow(m), "\n")
  b <- arms$b[arms$b$algorithm %in% c("maxnet", "rf", "xgboost"), ]
  b$changed <- m$changed[match(b$key, m$key)]
  cat("\nb against the release, full-design models, by block change:\n")
  print(with(b, table(block_changed = changed, identical = identical)))
  print(with(b, table(block_changed = changed, same_grade = grade == release_grade)))
}

# Cell-stratified bootstrap of b's weighted rates (models resampled within
# their cell, each cell weighted back to its share of the release).
if ("b" %in% names(arms)) {
  b <- arms$b
  set.seed(1)
  cells <- split(seq_len(nrow(b)), b$cell)
  w_cell <- as.numeric(population[names(cells)])
  rate <- function(flag) {
    vapply(seq_len(10000), function(r) {
      per <- vapply(cells, function(i) mean(flag[i[sample.int(length(i), length(i), replace = TRUE)]]), 0)
      sum(w_cell * per) / sum(w_cell)
    }, 0)
  }
  for (what in c("differs", "grade_changes")) {
    flag <- if (what == "differs") !b$identical else b$grade != b$release_grade
    est <- sum(w_cell * vapply(cells, function(i) mean(flag[i]), 0)) / sum(w_cell)
    q <- stats::quantile(rate(flag), c(0.025, 0.975))
    cat(sprintf("b %s: weighted rate %.4f [%.4f, %.4f] (cell-stratified bootstrap, 10,000)\n", what, est, q[[1]], q[[2]]))
  }
  # By learner family, weighted.
  for (lr in c("full design", "esm")) {
    s <- if (lr == "esm") b$algorithm == "esm" else b$algorithm != "esm"
    d <- b[s, ]
    cw <- as.numeric(population[unique(d$cell)])
    per <- vapply(split(!d$identical, d$cell)[unique(d$cell)], mean, 0)
    cat(sprintf("  %s: weighted differs %.4f over %d release models\n", lr, sum(cw * per) / sum(cw), sum(cw)))
  }
}
