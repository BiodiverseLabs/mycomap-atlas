# The location prior: every strong map's ranks by 20 km cell, for MycoMap
# Vision to weigh a photo by where it was taken. Built from the same
# per-model ranks as the "what could grow here" index.

cell_of <- function(point) {
  xy <- atlas_albers(point[["lat"]], point[["lng"]])
  atlas_here_cell(xy[1, "x"], xy[1, "y"])
}

prior_fixture <- function() {
  write_model("Eastern agreed", "maxnet", here_raster("east"))
  write_model("Eastern agreed", "rf", here_raster("east"))
  write_model("Eastern forest only", "maxnet", here_raster("west"))
  write_model("Eastern forest only", "rf", here_raster("east"))
  write_model("Western", "rf", here_raster("west"), presences = 12)
  write_model("Half known", "maxnet", here_raster("east"), dissimilarity = east_outside(), threshold = 0.5)
  write_model("Eastern by chance", "maxnet", here_raster("east"), skill = "failed")
  strong <- atlas_strong_map_cells("draft", quiet = TRUE)
  list(strong = strong,
       index = atlas_build_here_index("draft", quiet = TRUE, strong = strong),
       prior = atlas_build_prior("draft", quiet = TRUE, strong = strong))
}

# The index's entries as rows: cell, model, rank.
index_rows <- function(index) {
  data.frame(cell = rep(seq_len(length(index$start) - 1L), diff(index$start)),
             model = index$model, rank = as.integer(index$rank))
}

EAST_POINT <- c(lat = 40, lng = -95.5)
WEST_POINT <- c(lat = 40, lng = -96.5)

test_that("the here index is exactly each strong map's prior ranks of 50 and up", {
  testthat::skip_if_not_installed("terra")
  with_data_dir({
    f <- prior_fixture()
    rows <- index_rows(f$index)
    for (i in seq_len(nrow(f$strong$models))) {
      full <- f$strong$cells[[i]]
      expected <- full[!is.na(full$rank) & full$rank >= 50, , drop = FALSE]
      got <- rows[rows$model == i, , drop = FALSE]
      got <- got[order(got$cell), , drop = FALSE]
      expect_equal(got$cell, expected$cell, info = f$strong$models$taxon[[i]])
      expect_equal(got$rank, expected$rank, info = f$strong$models$taxon[[i]])
    }
    # A taxon with one strong map: its prior, kept at 50 and up, is its index.
    ranks <- f$prior$ranks
    id <- f$prior$taxa$taxon_id[f$prior$taxa$name == "Western"]
    mine <- ranks[ranks$taxon_id == id & !is.na(ranks$rank) & ranks$rank >= 50, , drop = FALSE]
    model <- which(f$strong$models$taxon == "Western")
    theirs <- rows[rows$model == model, , drop = FALSE]
    theirs <- theirs[order(theirs$cell), , drop = FALSE]
    expect_equal(mine$cell_id, theirs$cell)
    expect_equal(mine$rank, theirs$rank)
  })
})

test_that("a taxon's prior rank is the mean of its strong maps' ranks over every cell they reach", {
  testthat::skip_if_not_installed("terra")
  with_data_dir({
    f <- prior_fixture()
    for (k in seq_len(nrow(f$prior$taxa))) {
      name <- f$prior$taxa$name[[k]]
      parts <- f$strong$cells[f$strong$models$taxon == name]
      all <- do.call(rbind, parts)
      cells <- sort(unique(all$cell))
      expected <- vapply(cells, function(cell) {
        r <- all$rank[all$cell == cell & !is.na(all$rank)]
        if (length(r)) as.integer(round(mean(r))) else NA_integer_
      }, integer(1))
      mine <- f$prior$ranks[f$prior$ranks$taxon_id == k, , drop = FALSE]
      expect_equal(mine$cell_id, cells, info = name)
      expect_equal(mine$rank, expected, info = name)
    }
    # Two maps that disagree end up in the middle; the low half is kept, not dropped.
    split <- f$prior$ranks[f$prior$ranks$taxon_id == f$prior$taxa$taxon_id[f$prior$taxa$name == "Eastern forest only"], ]
    expect_true(all(abs(split$rank - 50) <= 2))
    agreed <- f$prior$ranks[f$prior$ranks$taxon_id == f$prior$taxa$taxon_id[f$prior$taxa$name == "Eastern agreed"], ]
    expect_true(any(agreed$rank < 10))
    expect_lt(agreed$rank[agreed$cell_id == cell_of(WEST_POINT)], agreed$rank[agreed$cell_id == cell_of(EAST_POINT)])
    # Beyond a taxon's reach there is no row at all.
    expect_false(cell_of(c(lat = 49, lng = -123)) %in% f$prior$ranks$cell_id)
  })
})

test_that("ground outside a map's area of applicability is left unranked, and is never here", {
  testthat::skip_if_not_installed("terra")
  with_data_dir({
    f <- prior_fixture()
    id <- f$prior$taxa$taxon_id[f$prior$taxa$name == "Half known"]
    mine <- f$prior$ranks[f$prior$ranks$taxon_id == id, , drop = FALSE]
    # Within reach but unknown ground: a row with no rank.
    expect_true(is.na(mine$rank[mine$cell_id == cell_of(EAST_POINT)]))
    # The ranks are taken among the known ground alone, so its best reaches the top.
    expect_gte(max(mine$rank, na.rm = TRUE), 95)
    expect_lt(mine$rank[mine$cell_id == cell_of(WEST_POINT)], 95)
    # The index keeps none of the unknown ground, though the raw map rises there.
    rows <- index_rows(f$index)
    model <- which(f$strong$models$taxon == "Half known")
    expect_false(cell_of(EAST_POINT) %in% rows$cell[rows$model == model])
    here <- atlas_here(f$index, EAST_POINT[["lat"]], EAST_POINT[["lng"]])
    expect_false("Half known" %in% vapply(here$taxa, `[[`, "", "scientific_name"))
  })
})

test_that("only strong maps are in the prior, and the taxa table says what each taxon has", {
  testthat::skip_if_not_installed("terra")
  with_data_dir({
    f <- prior_fixture()
    taxa <- f$prior$taxa
    expect_false("Eastern by chance" %in% taxa$name)
    expect_equal(taxa$name, sort(taxa$name))
    expect_equal(taxa$taxon_id, seq_len(nrow(taxa)))
    expect_true(all(taxa$grade == "strong"))
    agreed <- taxa[taxa$name == "Eastern agreed", ]
    expect_equal(agreed$models, 2L)
    expect_equal(agreed$algorithms, "maxnet,rf")
    expect_equal(taxa$sites[taxa$name == "Western"], 12L)
    for (k in taxa$taxon_id) {
      mine <- f$prior$ranks[f$prior$ranks$taxon_id == k, ]
      expect_equal(taxa$reach_cells[[k]], nrow(mine))
      expect_equal(taxa$applicable_cells[[k]], sum(!is.na(mine$rank)))
    }
    expect_lt(taxa$applicable_cells[taxa$name == "Half known"], taxa$reach_cells[taxa$name == "Half known"])
  })
})

test_that("the prior's files agree with each other: the TSV, the Parquet and the grid", {
  testthat::skip_if_not_installed("terra")
  with_data_dir({
    f <- prior_fixture()
    back <- atlas_read_prior("draft")
    expect_equal(back$ranks, f$prior$ranks)
    expect_equal(back$taxa$name, f$prior$taxa$name)
    expect_equal(back$taxa$reach_cells, f$prior$taxa$reach_cells)
    grid <- jsonlite::fromJSON(atlas_prior_path("grid.json"))
    expect_equal(grid$rows, nrow(f$prior$ranks))
    expect_equal(grid$taxa, nrow(f$prior$taxa))
    expect_equal(grid$cell_m, 20000)
    expect_equal(grid$ncol * grid$nrow, length(f$index$start) - 1L)
    expect_null(grid$built_at)
    if (requireNamespace("nanoparquet", quietly = TRUE)) {
      parquet <- as.data.frame(nanoparquet::read_parquet(atlas_prior_path("ranks.parquet")))
      expect_equal(parquet$taxon_id, f$prior$ranks$taxon_id)
      expect_equal(parquet$cell_id, f$prior$ranks$cell_id)
      expect_equal(parquet$rank, f$prior$ranks$rank)
      schema <- nanoparquet::read_parquet_schema(atlas_prior_path("ranks.parquet"))
      rank <- schema$logical_type[[which(schema$name == "rank")]]
      expect_equal(rank$bit_width, 8L)
      expect_false(rank$is_signed)
    }
  })
})

test_that("the same maps build the same prior, byte for byte", {
  testthat::skip_if_not_installed("terra")
  with_data_dir({
    prior_fixture()
    files <- c("ranks.tsv.gz", "taxa.tsv", "grid.json")
    first <- vapply(files, function(x) atlas_sha256(atlas_prior_path(x)), "")
    atlas_build_prior("draft", quiet = TRUE)
    expect_equal(vapply(files, function(x) atlas_sha256(atlas_prior_path(x)), ""), first)
  })
})

test_that("the Python cell lookup in grid.json finds the same cells as Atlas", {
  python <- Filter(nzchar, Sys.which(c("python3", "python")))
  ok <- vapply(python, function(p) {
    identical(suppressWarnings(tryCatch(system2(p, c("-c", shQuote("import numpy")), stdout = FALSE, stderr = FALSE),
                                        error = function(e) 1L)), 0L)
  }, logical(1))
  testthat::skip_if(!any(ok), "no Python with numpy here")
  points <- data.frame(lat = c(40, 40, 49.3, 25.8, 61.2, 19.4, 44.9, -40),
                       lng = c(-95.5, -96.5, -123.1, -80.2, -149.9, -99.1, -68.8, 100))
  script <- tempfile(fileext = ".py")
  writeLines(c(atlas_prior_python(),
               sprintf("print(' '.join(str(c) for c in atlas_cell([%s], [%s])))",
                       paste(points$lat, collapse = ", "), paste(points$lng, collapse = ", "))), script)
  out <- system2(python[ok][[1]], script, stdout = TRUE)
  theirs <- as.numeric(strsplit(out, " ")[[1]])
  xy <- atlas_albers(points$lat, points$lng)
  mine <- atlas_here_cell(xy[, "x"], xy[, "y"])
  mine[is.na(mine)] <- 0
  expect_equal(theirs, mine)
})

test_that("a release and its Zenodo bundle carry the prior", {
  testthat::skip_if_not_installed("terra")
  with_data_dir({
    prior_fixture()
    store <- new_store()
    release <- atlas_publish_release(store, quiet = TRUE)
    paths <- vapply(release$files, `[[`, "", "path")
    expect_true(all(paste0("prior/draft/", c("ranks.tsv.gz", "taxa.tsv", "grid.json")) %in% paths))
    bundle <- atlas_archive_models_bundle(store, "draft")
    expect_true(all(c("prior-ranks.tsv.gz", "prior-taxa.tsv", "prior-grid.json") %in% names(bundle$sources)))
  })
})

test_that("the API lists the prior with checksums and serves each file, and nothing else", {
  testthat::skip_if_not_installed("terra")
  testthat::skip_if_not_installed("plumber")
  with_data_dir({
    prior_fixture()
    with_env(c(ATLAS_DATA_DIR = atlas_data_dir()), {
      api <- test_api(c(ATLAS_DATA_DIR = atlas_data_dir()))
      listing <- call_api(api, "/api/prior")
      expect_equal(listing$status, 200L)
      body <- jsonlite::fromJSON(listing$body, simplifyVector = FALSE)
      expect_equal(body$taxa, 4L)
      names <- vapply(body$files, `[[`, "", "name")
      expect_true(all(c("ranks.tsv.gz", "taxa.tsv", "grid.json") %in% names))
      expect_equal(body$definition$cell_m, 20000)
      # Each file comes back byte for byte as listed (raw bodies: Parquet and
      # gzip are binary).
      for (f in body$files) {
        req <- new.env()
        req$REQUEST_METHOD <- "GET"; req$PATH_INFO <- f$url; req$QUERY_STRING <- ""
        req$REMOTE_ADDR <- "203.0.113.5"; req$SERVER_NAME <- "127.0.0.1"; req$SERVER_PORT <- "5100"
        req$HTTP_HOST <- "atlas.example.org"
        req$rook.input <- list(read = function(...) raw(), rewind = function() invisible(), read_lines = function() character())
        out <- suppressMessages(api$call(req))
        expect_equal(out$status, 200L, info = f$name)
        bytes <- if (is.raw(out$body)) out$body else charToRaw(out$body)
        expect_equal(digest::digest(bytes, algo = "sha256", serialize = FALSE), f$sha256, info = f$name)
        expect_equal(unname(unlist(out$headers[tolower(names(out$headers)) == "content-type"])),
                     unname(ATLAS_PRIOR_TYPES[[f$name]]), info = f$name)
      }
      # Only the prior's own files: no other path under data/ can be asked for.
      expect_equal(call_api(api, "/api/prior/here.rds")$status, 404L)
      expect_equal(call_api(api, "/api/prior/..%2F..%2Foccurrences%2Flatest.json")$status, 404L)
    })
  })
})

test_that("a server with no prior says so with a 404, not an empty answer", {
  testthat::skip_if_not_installed("plumber")
  with_data_dir({
    with_env(c(ATLAS_DATA_DIR = atlas_data_dir()), {
      api <- test_api(c(ATLAS_DATA_DIR = atlas_data_dir()))
      expect_equal(call_api(api, "/api/prior")$status, 404L)
      expect_equal(call_api(api, "/api/prior/ranks.parquet")$status, 404L)
    })
  })
})

test_that("each cell says how many strong maps judge it and how far apart their ranks are", {
  testthat::skip_if_not_installed("terra")
  with_data_dir({
    f <- prior_fixture()
    taxa <- f$prior$taxa
    of <- function(name) f$prior$ranks[f$prior$ranks$taxon_id == taxa$taxon_id[taxa$name == name], , drop = FALSE]
    # Two maps that agree everywhere: two judges, no spread.
    agreed <- of("Eastern agreed")
    expect_true(all(agreed$models == 2L))
    expect_true(all(agreed$rank_sd == 0L))
    # Two that disagree: the spread is the gap between them, over root 2.
    split <- of("Eastern forest only")
    parts <- f$strong$cells[f$strong$models$taxon == "Eastern forest only"]
    a <- parts[[1]]$rank[match(split$cell_id, parts[[1]]$cell)]
    b <- parts[[2]]$rank[match(split$cell_id, parts[[2]]$cell)]
    expect_equal(split$rank_sd, as.integer(round(abs(a - b) / sqrt(2))))
    expect_gt(max(split$rank_sd), 50L)
    # One map: one judge, no spread to give.
    western <- of("Western")
    expect_true(all(western$models == 1L))
    expect_true(all(is.na(western$rank_sd)))
    # Ground no map can judge: no judges.
    half <- of("Half known")
    expect_equal(half$models[is.na(half$rank)], rep(0L, sum(is.na(half$rank))))
  })
})

test_that("a taxon's map strength is its maps', weighted as the combined map weights them", {
  testthat::skip_if_not_installed("terra")
  with_data_dir({
    write_model("Two maps", "maxnet", here_raster("east"), auc = 0.6, map_strength = 0.4)
    write_model("Two maps", "rf", here_raster("east"), auc = 0.9, map_strength = 0.8)
    write_model("One map", "rf", here_raster("west"), auc = 0.8, map_strength = 0.55)
    prior <- atlas_build_prior("draft", quiet = TRUE)
    strength <- stats::setNames(prior$taxa$map_strength, prior$taxa$name)
    # Weights AUC - 0.5: 0.1 and 0.4.
    expect_equal(strength[["Two maps"]], round((0.1 * 0.4 + 0.4 * 0.8) / 0.5, 3))
    expect_equal(strength[["One map"]], 0.55)
    expect_equal(sort(prior$models$weight), c(0.1, 0.3, 0.4))
  })
})

test_that("each map's area-of-applicability index by cell sits beside its threshold", {
  testthat::skip_if_not_installed("terra")
  with_data_dir({
    f <- prior_fixture()
    models <- f$prior$models
    half <- models[models$taxon_id == f$prior$taxa$taxon_id[f$prior$taxa$name == "Half known"], ]
    expect_equal(nrow(half), 1L)
    expect_equal(half$threshold, 0.5)
    aoa <- f$prior$aoa[f$prior$aoa$model_id == half$model_id, ]
    # The east is wholly outside (index 1, above 0.5), the west wholly inside (0).
    expect_equal(aoa$dissimilarity[aoa$cell_id == cell_of(EAST_POINT)], 100L)
    expect_equal(aoa$dissimilarity[aoa$cell_id == cell_of(WEST_POINT)], 0L)
    # Every model with a map has its threshold and its weight.
    expect_equal(nrow(models), nrow(f$strong$models))
    files <- c("models.tsv", "aoa.tsv.gz", if (requireNamespace("nanoparquet", quietly = TRUE)) "aoa.parquet")
    for (file in files) expect_true(file.exists(atlas_prior_path(file)), info = file)
    if (requireNamespace("nanoparquet", quietly = TRUE)) {
      parquet <- as.data.frame(nanoparquet::read_parquet(atlas_prior_path("aoa.parquet")))
      expect_equal(parquet$dissimilarity, f$prior$aoa$dissimilarity)
    }
  })
})

test_that("weak maps' ranks are made for Vision but stay out of the prior and the release", {
  testthat::skip_if_not_installed("terra")
  with_data_dir({
    write_model("Eastern agreed", "maxnet", here_raster("east"))
    write_model("Faint", "rf", here_raster("west"))
    metrics <- jsonlite::fromJSON(atlas_model_path("Faint", "draft", ".json", "rf"), simplifyVector = FALSE)
    metrics$grade <- "weak"
    atlas_write_json(metrics, atlas_model_path("Faint", "draft", ".json", "rf"))
    atlas_build_finish_indexes("draft", quiet = TRUE)
    weak <- utils::read.delim(gzfile(atlas_weak_ranks_path("draft")), stringsAsFactors = FALSE)
    expect_equal(unique(weak$taxon), "Faint")
    expect_true(all(weak$grade == "weak"))
    expect_false("Faint" %in% atlas_read_prior("draft")$taxa$name)
    expect_false(any(grepl("weak|unpublished", atlas_release_files("draft"))))
  })
})
