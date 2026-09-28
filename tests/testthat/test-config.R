test_that("an explicit ATLAS_DATA_DIR wins", {
  with_env(c(ATLAS_DATA_DIR = "D:/elsewhere", ATLAS_ROOT = "D:/repo"), {
    expect_equal(atlas_data_dir(), "D:/elsewhere")
  })
})

test_that("data sits under ATLAS_ROOT, because plumber runs from its own directory", {
  with_env(c(ATLAS_DATA_DIR = NA, ATLAS_ROOT = "D:/repo"), {
    expect_equal(atlas_data_dir(), "D:/repo/data")
    expect_equal(atlas_path("occurrences", "latest.json"), "D:/repo/data/occurrences/latest.json")
  })
})

test_that("with neither set, the working directory is used", {
  with_env(c(ATLAS_DATA_DIR = NA, ATLAS_ROOT = NA), {
    expect_equal(atlas_data_dir(), "data")
  })
})
