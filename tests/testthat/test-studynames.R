# What sequence names change (paper E9): the record-name arm keeps every
# record and its effort, changes only which taxon a record counts for, and
# its maps are compared with the DNA-named ones.

dna_pull <- function() {
  data.frame(
    id = as.character(1:8), source = c(rep("inat", 5), rep("mo", 3)),
    observation_id = as.character(101:108),
    scientific_name = c("Amanita muscaria", "Amanita muscaria", "Amanita muscaria",
                        "Russula sp. 'IN01'", "Russula sp. 'IN01'",
                        "Boletus edulis", "Boletus edulis", "Cortinarius alboviolaceus"),
    record_name = c("Amanita muscaria", "Amanita muscaria (L.) Lam.", "Amanita persicina",
                    "Russula emetica", "Russula", "Boletus edulis", "Tylopilus felleus",
                    "Cortinarius alboviolaceus"),
    latitude = "40", longitude = "-80", observed_on = "2025-09-01",
    stringsAsFactors = FALSE
  )
}

test_that("the record-name arm keeps every record, relabelled with its own name, spellings merged", {
  dna <- dna_pull()
  record <- atlas_e9_record_named(dna)
  expect_equal(nrow(record), nrow(dna))
  expect_equal(record$observation_id, dna$observation_id)
  expect_equal(record$latitude, dna$latitude)
  # An author citation is a spelling of the same taxon.
  expect_equal(record$scientific_name[1:2], c("Amanita muscaria", "Amanita muscaria"))
  expect_equal(record$scientific_name[[3]], "Amanita persicina")
  # A record named only to genus stays as effort under a label no taxon has.
  expect_equal(record$scientific_name[[5]], ATLAS_E9_NO_TAXON)
  expect_false(atlas_species_level(ATLAS_E9_NO_TAXON))
  expect_error(atlas_e9_record_named(dna[, setdiff(names(dna), "record_name")]), "record_name")
})

test_that("label changes are told apart: spelling, another species, another genus, no taxon", {
  dna <- dna_pull()
  changes <- atlas_e9_label_changes(dna, atlas_e9_record_named(dna))
  expect_equal(changes$per_record,
               c("same", "same", "species", "species", "no_taxon", "same", "genus", "same"))
  by <- changes$by_source
  expect_equal(by$records[by$source == "inat" & by$change == "species"], 2L)
  expect_equal(by$records[by$source == "mo" & by$change == "genus"], 1L)
  expect_equal(sum(by$records), nrow(dna))
})

test_that("taxa split, merged, gained and lost are counted", {
  dna <- dna_pull()
  taxa <- atlas_e9_taxon_changes(dna, atlas_e9_record_named(dna))
  expect_equal(taxa$split, c("Amanita muscaria", "Boletus edulis"))
  expect_equal(taxa$gained, c("Amanita persicina", "Russula emetica", "Tylopilus felleus"))
  expect_equal(taxa$lost, "Russula sp. 'IN01'")
  expect_length(taxa$merged, 0L)
  expect_equal(taxa$counts$dna_taxa, 4L)
})

test_that("only taxa under both names whose record sets differ are refitted", {
  dna <- dna_pull()
  changed <- atlas_e9_changed_taxa(dna, atlas_e9_record_named(dna))
  expect_setequal(changed$taxon, c("Amanita muscaria", "Boletus edulis", "Cortinarius alboviolaceus"))
  expect_equal(changed$changed[changed$taxon == "Cortinarius alboviolaceus"], FALSE)
  amanita <- changed[changed$taxon == "Amanita muscaria", ]
  expect_equal(c(amanita$records_dna, amanita$records_record, amanita$lost, amanita$gained), c(3L, 2L, 1L, 0L))
  expect_false(ATLAS_E9_NO_TAXON %in% changed$taxon)
})

test_that("identical maps compare as Spearman 1 and Schoener's D 1, and opposite ones far lower", {
  skip_if_not_installed("terra")
  grid <- terra::rast(nrows = 10, ncols = 10, xmin = 0, xmax = 1e5, ymin = 0, ymax = 1e5, crs = ATLAS_CRS)
  a <- grid
  terra::values(a) <- seq(0.01, 1, length.out = 100)
  same <- atlas_e9_compare_maps(a, a)
  expect_equal(same$cells, 100L)
  expect_equal(same$spearman, 1)
  expect_equal(same$schoener_d, 1)
  b <- grid
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
