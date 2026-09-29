# One taxon, one name: spellings that differ only in punctuation are merged.

same_taxon <- function(...) length(unique(atlas_name_key(c(...)))) == 1L

test_that("spellings that differ only in punctuation are one taxon", {
  expect_true(same_taxon("Mycena sp. 'IN10'", "Mycena \"sp-IN10\""))
  expect_true(same_taxon("Clitocybe sp. 'fuscidisca PNW10'", "Clitocybe sp. 'fuscidisca-PNW10'"))
  expect_true(same_taxon("Mycena sp. 'IN22'", "Mycena \"sp-IN22\"", "Mycena “sp-IN22”"))
  expect_true(same_taxon("Marasmiellus sp. 'candidus-CA01'", "Marasmiellus sp. ‘candidus-CA01’"))
  expect_true(same_taxon("Lactarius subvernalis var. cokeri", "Lactarius subvernalis var. cokeri"))
  expect_true(same_taxon("Tricholoma lutescentifolium", "Tricholoma lutescentifolium "))
  expect_true(same_taxon("Peziza sp. 'varia-IN01'", "Peziza sp. 'varia-IN01"))
  expect_true(same_taxon("Hemimycena sp. 'lactea-PNW04'", "Hemimycena sp. ''lactea-PNW04''"))
  expect_true(same_taxon("Arrhenia sp. 'CA09'", "Arrhenia sp. 'CA09’"))
})

test_that("letters and digits are never merged away", {
  expect_false(same_taxon("Russula sp. 'IN1'", "Russula sp. 'IN01'"))
  expect_false(same_taxon("Mycena sp. 'IN10'", "Mycena sp. 'IN100'"))
  expect_false(same_taxon("Mycena sp. 'IN10'", "Russula sp. 'IN10'"))
  expect_false(same_taxon("Amanita muscaria", "Amanita muscarius"))
  # Accented letters are part of the name, not punctuation.
  expect_false(same_taxon("Diploöspora longispora", "Diploospora longispora"))
})

test_that("a merged taxon takes the spelling most of its records use", {
  names <- c(rep("Mycena sp. 'IN10'", 5), rep("Mycena \"sp-IN10\"", 2), "Amanita muscaria")
  canonical <- atlas_canonical_names(names)
  expect_equal(unname(canonical["Mycena \"sp-IN10\""]), "Mycena sp. 'IN10'")
  expect_equal(unname(canonical["Amanita muscaria"]), "Amanita muscaria")
  # A tie goes to the alphabetically first spelling, so the choice is stable.
  tie <- atlas_canonical_names(c("X sp. 'a b'", "X sp. 'a-b'"))
  expect_equal(unique(unname(tie)), "X sp. 'a b'")
})

test_that("records keep their original spelling, and merging twice changes nothing", {
  occurrences <- data.frame(
    scientific_name = c("Mycena sp. 'IN10'", "Mycena sp. 'IN10'", "Mycena \"sp-IN10\""),
    latitude = "45", longitude = "-100", stringsAsFactors = FALSE
  )
  once <- atlas_canonicalise_occurrences(occurrences)
  expect_equal(unique(once$scientific_name), "Mycena sp. 'IN10'")
  expect_equal(once$original_name, occurrences$scientific_name)
  expect_equal(atlas_canonicalise_occurrences(once), once)
})

test_that("every merge is reported, with how many records each spelling brought", {
  occurrences <- atlas_canonicalise_occurrences(data.frame(
    scientific_name = c(rep("Mycena sp. 'IN10'", 3), rep("Mycena \"sp-IN10\"", 2), "Amanita muscaria"),
    stringsAsFactors = FALSE
  ))
  merges <- atlas_name_merges(occurrences)
  expect_equal(nrow(merges), 1L)
  expect_equal(merges$taxon, "Mycena sp. 'IN10'")
  expect_equal(merges$spelling, "Mycena \"sp-IN10\"")
  expect_equal(merges$records, 2L)
})

test_that("a pull made before the rule is merged when it is read", {
  with_data_dir({
    old <- data.frame(id = c("1", "2", "3"),
                      scientific_name = c("Mycena sp. 'IN10'", "Mycena sp. 'IN10'", "Mycena \"sp-IN10\""),
                      latitude = "45", longitude = "-100", observed_on = "2025-01-01",
                      stringsAsFactors = FALSE)
    atlas_write_tsv_gz(old, atlas_path("occurrences", "occurrences-x.tsv.gz"))
    atlas_write_json(list(file = "occurrences-x.tsv.gz"), atlas_path("occurrences", "latest.json"))
    read <- atlas_read_occurrences()
    expect_equal(unique(read$scientific_name), "Mycena sp. 'IN10'")
    merges <- atlas_refresh_names(quiet = TRUE)
    expect_equal(nrow(merges), 1L)
    expect_true(file.exists(atlas_name_merges_path()))
    taxa <- jsonlite::fromJSON(atlas_path("occurrences", "taxa-latest.json"))
    expect_equal(taxa$scientific_name, "Mycena sp. 'IN10'")
    expect_equal(taxa$records, 3L)
  })
})

test_that("a fit refuses to overwrite the model of a different taxon", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  with_data_dir({
    world <- synthetic_landscape()
    # Another name that makes the same file name already has a model there.
    dir.create(atlas_model_dir("draft"), recursive = TRUE)
    atlas_write_json(list(taxon = "Eastern-fungus"), atlas_model_path("Eastern fungus", "draft", ".json"))
    expect_error(
      atlas_fit_taxon("Eastern fungus", points = world$points, stack = world$stack,
                      fingerprint = "f00dfeed", layers = "synthetic", n_background = 500,
                      buffer_km = 300, predict = FALSE, quiet = TRUE),
      "share a file name"
    )
    expect_equal(atlas_read_metrics("Eastern fungus")$taxon, "Eastern-fungus")
  })
})
