# What sequence names change (paper E9): the record-name release (built by
# the private-release job with --record-names) set against the frozen one.

dna_pull <- function() {
  data.frame(
    id = as.character(1:8), source = c(rep("inat", 5), rep("mo", 3)),
    observation_id = as.character(101:108),
    scientific_name = c("Amanita muscaria", "Amanita muscaria", "Amanita muscaria",
                        "Russula sp. 'IN01'", "Russula sp. 'IN01'",
                        "Boletus edulis", "Boletus edulis", "Cortinarius alboviolaceus"),
    stringsAsFactors = FALSE
  )
}

# As the record-name job gives it: each record under its own name, spellings
# merged; the record named only "Russula" is not in it, and the rows come in
# another order.
record_pull <- function() {
  data.frame(
    id = as.character(c(8, 7, 6, 4, 3, 2, 1)), source = c("mo", "mo", "mo", rep("inat", 4)),
    observation_id = as.character(c(108, 107, 106, 104, 103, 102, 101)),
    scientific_name = c("Cortinarius alboviolaceus", "Tylopilus felleus", "Boletus edulis",
                        "Russula emetica", "Amanita persicina", "Amanita muscaria", "Amanita muscaria"),
    stringsAsFactors = FALSE
  )
}

test_that("label changes are told apart by record, whatever order the pulls are in", {
  changes <- atlas_e9_label_changes(dna_pull(), record_pull())
  expect_equal(changes$per_record,
               c("same", "same", "species", "species", "no_taxon", "same", "genus", "same"))
  by <- changes$by_source
  expect_equal(by$records[by$source == "mo" & by$change == "genus"], 1L)
  expect_equal(by$records[by$source == "inat" & by$change == "no_taxon"], 1L)
  expect_equal(sum(by$records), nrow(dna_pull()))
})

test_that("a record kept as effort under a label that is no taxon counts as no taxon", {
  record <- record_pull()
  record <- rbind(record, data.frame(id = "5", source = "inat", observation_id = "105",
                                     scientific_name = "Russula", stringsAsFactors = FALSE))
  expect_equal(atlas_e9_label_changes(dna_pull(), record)$per_record[[5]], "no_taxon")
  expect_false("Russula" %in% atlas_e9_taxon_changes(dna_pull(), record)$gained)
})

test_that("taxa split, merged, gained and lost are counted", {
  taxa <- atlas_e9_taxon_changes(dna_pull(), record_pull())
  expect_equal(taxa$split, c("Amanita muscaria", "Boletus edulis"))
  expect_equal(taxa$gained, c("Amanita persicina", "Russula emetica", "Tylopilus felleus"))
  expect_equal(taxa$lost, "Russula sp. 'IN01'")
  expect_length(taxa$merged, 0L)
  expect_equal(taxa$counts$dna_taxa, 4L)
})

test_that("only taxa under both names whose record sets differ count as changed", {
  changed <- atlas_e9_changed_taxa(dna_pull(), record_pull())
  expect_setequal(changed$taxon, c("Amanita muscaria", "Boletus edulis", "Cortinarius alboviolaceus"))
  expect_false(changed$changed[changed$taxon == "Cortinarius alboviolaceus"])
  amanita <- changed[changed$taxon == "Amanita muscaria", ]
  expect_equal(c(amanita$records_dna, amanita$records_record, amanita$lost, amanita$gained), c(3L, 2L, 1L, 0L))
})

map_grid <- function() terra::rast(nrows = 10, ncols = 10, xmin = 0, xmax = 1e5, ymin = 0, ymax = 1e5, crs = ATLAS_CRS)

test_that("identical maps compare as Spearman 1 and Schoener's D 1, opposite ones far lower", {
  skip_if_not_installed("terra")
  a <- map_grid()
  terra::values(a) <- seq(0.01, 1, length.out = 100)
  same <- atlas_e9_compare_maps(a, a)
  expect_equal(c(same$cells, same$spearman, same$schoener_d), c(100, 1, 1))
  b <- map_grid()
  terra::values(b) <- rev(seq(0.01, 1, length.out = 100))
  opposite <- atlas_e9_compare_maps(a, b)
  expect_equal(opposite$spearman, -1)
  expect_lt(opposite$schoener_d, 0.6)
  # Only cells both maps cover are compared; a map on a smaller window is
  # extended, not resampled.
  half <- terra::crop(a, terra::ext(0, 5e4, 0, 1e5))
  expect_equal(atlas_e9_compare_maps(a, half)$cells, 50L)
  shifted <- terra::rast(nrows = 10, ncols = 10, xmin = 3000, xmax = 103000, ymin = 0, ymax = 1e5, crs = ATLAS_CRS)
  terra::values(shifted) <- 1
  expect_error(atlas_e9_compare_maps(a, shifted), "one grid")
})

test_that("every record-name model is set against the frozen one: grades, and maps where both are drawn", {
  skip_if_not_installed("terra")
  dir <- tempfile("e9-")
  dir.create(dir)
  write_map <- function(name, values) {
    r <- map_grid()
    terra::values(r) <- values
    path <- file.path(dir, paste0(name, ".tif"))
    terra::writeRaster(r, path, overwrite = TRUE)
    path
  }
  files <- list(
    frozen = list(`Amanita muscaria/maxnet` = write_map("f-am", seq(0.01, 1, length.out = 100)),
                  `Amanita muscaria/rf` = write_map("f-am-rf", seq(0.01, 1, length.out = 100))),
    record = list(`Amanita muscaria/maxnet` = write_map("r-am", seq(0.01, 1, length.out = 100)),
                  `Amanita muscaria/rf` = write_map("r-am-rf", rev(seq(0.01, 1, length.out = 100))),
                  `Amanita persicina/maxnet` = write_map("r-ap", 0.5))
  )
  view <- function(side, entries) list(side = side, grid = "draft", entries = entries)
  frozen <- view("frozen", list(list(taxon = "Amanita muscaria", algorithm = "maxnet", grade = "strong", presences = 60),
                                list(taxon = "Amanita muscaria", algorithm = "rf", grade = "strong", presences = 60)))
  record <- view("record", list(list(taxon = "Amanita muscaria", algorithm = "maxnet", grade = "strong", presences = 52),
                                list(taxon = "Amanita muscaria", algorithm = "rf", grade = "weak", presences = 52),
                                list(taxon = "Amanita persicina", algorithm = "maxnet", grade = "failed", presences = 8)))
  raster_of <- function(v, path, ext) {
    taxon <- if (grepl("persicina", path)) "Amanita persicina" else "Amanita muscaria"
    algorithm <- if (grepl("/rf/", path)) "rf" else "maxnet"
    files[[v$side]][[paste0(taxon, "/", algorithm)]]
  }
  compared <- atlas_e9_compare_releases(frozen, record, raster_of = raster_of)
  expect_equal(nrow(compared), 3L)
  am <- compared[compared$taxon == "Amanita muscaria" & compared$algorithm == "maxnet", ]
  expect_equal(c(am$spearman, am$schoener_d), c(1, 1))
  expect_equal(c(am$presences_dna, am$presences_record), c(60L, 52L))
  rf <- compared[compared$algorithm == "rf", ]
  expect_equal(rf$spearman, -1)
  expect_equal(c(rf$grade_dna, rf$grade_record), c("strong", "weak"))
  # A taxon only under record names has no frozen map to compare with.
  new <- compared[compared$taxon == "Amanita persicina", ]
  expect_true(is.na(new$grade_dna) && is.na(new$spearman))
  grades <- atlas_e9_grade_changes(compared)
  expect_equal(grades$Freq[grades$dna == "strong" & grades$record == "weak"], 1L)
  expect_equal(grades$Freq[grades$dna == "strong" & grades$record == "strong"], 1L)
})
