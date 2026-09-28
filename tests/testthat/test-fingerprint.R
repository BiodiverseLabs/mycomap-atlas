test_that("a fingerprint does not depend on row order", {
  df <- fake_occurrences()
  shuffled <- df[rev(seq_len(nrow(df))), , drop = FALSE]
  expect_equal(atlas_fingerprint(df), atlas_fingerprint(shuffled))
})

test_that("moving a record changes the fingerprint", {
  df <- fake_occurrences()
  moved <- df
  moved$latitude[1] <- "46.0000"
  expect_false(identical(atlas_fingerprint(df), atlas_fingerprint(moved)))
})

test_that("renaming a record changes the fingerprint", {
  df <- fake_occurrences()
  renamed <- df
  renamed$scientific_name[1] <- "Amanita persicina"
  expect_false(identical(atlas_fingerprint(df), atlas_fingerprint(renamed)))
})

test_that("dropping a record changes the fingerprint", {
  df <- fake_occurrences()
  expect_false(identical(atlas_fingerprint(df), atlas_fingerprint(df[-1, , drop = FALSE])))
})

test_that("an empty set fingerprints without error", {
  expect_type(atlas_fingerprint(fake_occurrences()[0, , drop = FALSE]), "character")
})

test_that("records in one cell count as one locality", {
  taxa <- atlas_taxon_fingerprints(fake_occurrences())
  expect_equal(nrow(taxa), 1L)
  expect_equal(taxa$records, 3L)
  expect_equal(taxa$localities, 2L)
})

test_that("each taxon gets its own fingerprint", {
  df <- fake_occurrences()
  df$scientific_name[3] <- "Russula brevipes"
  taxa <- atlas_taxon_fingerprints(df)
  expect_equal(nrow(taxa), 2L)
  expect_equal(length(unique(taxa$fingerprint)), 2L)
})

test_that("taxa are listed by how many localities they have", {
  df <- fake_occurrences()
  df$scientific_name[3] <- "Russula brevipes"
  taxa <- atlas_taxon_fingerprints(df)
  expect_equal(taxa$scientific_name[1], "Amanita muscaria")
})

test_that("an empty pull yields no taxa", {
  expect_equal(nrow(atlas_taxon_fingerprints(fake_occurrences()[0, , drop = FALSE])), 0L)
})
