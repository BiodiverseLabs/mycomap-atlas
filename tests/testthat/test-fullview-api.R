# The map route's two views (R/api.R atlas_map_view_extension): the default
# map within 500 km of the records, and a strong map's full-extent view
# (R/fullextent.R), which the taxon page's toggle asks for with view=full.

test_that("a view names the file it draws, and anything else is refused", {
  expect_equal(atlas_map_view_extension(NULL), ".png")
  expect_equal(atlas_map_view_extension(""), ".png")
  expect_equal(atlas_map_view_extension("accessible"), ".png")
  expect_equal(atlas_map_view_extension("full"), ".full.png")
  expect_null(atlas_map_view_extension("everywhere"))
})

test_that("the map route serves the default map, a strong map's full view, and says when there is none", {
  with_data_dir({
    # Stand-in images: the route sends whatever file the view names.
    for (taxon in c("Strong one", "Weak one")) {
      path <- atlas_model_path(taxon, "draft", ".png", "maxnet")
      dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
      writeLines("the default map", path)
    }
    writeLines("the full view", atlas_model_path("Strong one", "draft", ".full.png", "maxnet"))
    with_env(c(ATLAS_DATA_DIR = atlas_data_dir()), {
      api <- test_api(c(ATLAS_DATA_DIR = atlas_data_dir()))
      default <- call_api(api, "/api/taxa/Strong%20one/map.png")
      expect_equal(default$status, 200L)
      expect_match(default$body, "the default map", fixed = TRUE)
      expect_match(call_api(api, "/api/taxa/Strong%20one/map.png", query = "view=accessible")$body,
                   "the default map", fixed = TRUE)
      full <- call_api(api, "/api/taxa/Strong%20one/map.png", query = "view=full&v=2026")
      expect_equal(full$status, 200L)
      expect_match(full$body, "the full view", fixed = TRUE)
      # A weak map has no full view: it makes no claim beyond its reach.
      weak <- call_api(api, "/api/taxa/Weak%20one/map.png", query = "view=full")
      expect_equal(weak$status, 404L)
      expect_match(weak$body, "only strong maps are drawn beyond their reach", fixed = TRUE)
      expect_equal(call_api(api, "/api/taxa/Strong%20one/map.png", query = "view=sideways")$status, 400L)
    })
  })
})
