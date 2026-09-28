test_that("a percent-encoded name from the URL path is decoded", {
  expect_equal(atlas_decode_name("Amanita%20muscaria"), "Amanita muscaria")
  expect_equal(atlas_decode_name("Russula%20%27IN01%27"), "Russula 'IN01'")
})

test_that("an already-decoded name survives decoding", {
  expect_equal(atlas_decode_name("Amanita muscaria"), "Amanita muscaria")
  expect_equal(atlas_decode_name(NULL), "")
})

test_that("a taxon that is not in the pull returns nothing", {
  taxa <- atlas_taxon_fingerprints(fake_occurrences())
  expect_null(atlas_taxon_row(taxa, "Boletus edulis"))
  expect_equal(atlas_taxon_row(taxa, "Amanita muscaria")$records, 3L)
})

test_that("cells are aggregated to the public grid", {
  cells <- atlas_public_cells(fake_occurrences(), "Amanita muscaria")
  expect_equal(nrow(cells), 1L)
  expect_equal(cells$records, 3L)
})

test_that("a published cell never repeats a record's own coordinates", {
  records <- fake_occurrences()
  cells <- atlas_public_cells(records, "Amanita muscaria")
  expect_false(any(cells$lat %in% as.numeric(records$latitude)))
  expect_false(any(cells$lng %in% as.numeric(records$longitude)))
})

test_that("a finer grid separates what the public grid merges", {
  records <- fake_occurrences()
  coarse <- atlas_public_cells(records, "Amanita muscaria", degrees = 0.1)
  fine <- atlas_public_cells(records, "Amanita muscaria", degrees = 0.01)
  expect_lt(nrow(coarse), nrow(fine))
})

test_that("an unknown taxon has no cells", {
  expect_equal(nrow(atlas_public_cells(fake_occurrences(), "Boletus edulis")), 0L)
})
