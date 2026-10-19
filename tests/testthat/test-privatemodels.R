# The private release's models table (atlas_private_models_table): every
# model's grade and scores, read from the metrics a real fit writes. Its
# boyce_pooled was empty for every model of hindcast 9e3ab153 (2026-10-19):
# it read a field fits never write.

test_that("the models table's pooled Boyce is the one a real fit records, not an empty column", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  with_data_dir({
    world <- synthetic_landscape()
    atlas_fit_taxon("Eastern fungus", points = world$points, stack = world$stack,
                    fingerprint = "f00dfeed", layers = "synthetic", n_background = 500,
                    buffer_km = 300, predict = FALSE, quiet = TRUE, nulls = 0, tune = FALSE)
    stored <- atlas_read_metrics("Eastern fungus")
    table <- atlas_private_models_table("draft")
    row <- table[table$taxon == "Eastern fungus" & table$algorithm == "maxnet", , drop = FALSE]
    expect_equal(nrow(row), 1L)
    # The pooled index the grade is judged by, as the fit wrote it.
    expect_true(is.finite(row$boyce_pooled))
    expect_equal(row$boyce_pooled, as.numeric(stored$boyce))
    expect_equal(row$auc_mean, as.numeric(stored$auc_mean))
    # Not the mean over folds, which the fit keeps beside it.
    expect_true(is.numeric(stored$boyce_mean))
  })
})
