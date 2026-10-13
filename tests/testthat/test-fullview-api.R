# The map route's two views (R/api.R atlas_map_view_extension): the default
# map within 500 km of the records, and a strong map's full-extent view
# (R/fullextent.R), which the taxon page's toggle asks for with view=full.
# The full view is published only when the box sets ATLAS_FULL_VIEW=on
# (atlas_full_view_on); until then the API neither lists nor serves it.

test_that("a view names the file it draws, and anything else is refused", {
  expect_equal(atlas_map_view_extension(NULL), ".png")
  expect_equal(atlas_map_view_extension(""), ".png")
  expect_equal(atlas_map_view_extension("accessible"), ".png")
  expect_equal(atlas_map_view_extension("full"), ".full.png")
  expect_null(atlas_map_view_extension("everywhere"))
})

test_that("the full view is published only when the site says so", {
  with_env(c(ATLAS_FULL_VIEW = ""), expect_false(atlas_full_view_on()))
  with_env(c(ATLAS_FULL_VIEW = "off"), expect_false(atlas_full_view_on()))
  with_env(c(ATLAS_FULL_VIEW = "on"), expect_true(atlas_full_view_on()))
  with_env(c(ATLAS_FULL_VIEW = "TRUE"), expect_true(atlas_full_view_on()))
})

# A strong model with a full view, and a weak one without, as stand-in files:
# the route sends whatever file the view names.
full_view_fixture <- function() {
  for (taxon in c("Strong one", "Weak one")) {
    path <- atlas_model_path(taxon, "draft", ".png", "maxnet")
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    writeLines("the default map", path)
  }
  writeLines("FULL-VIEW-PICTURE", atlas_model_path("Strong one", "draft", ".full.png", "maxnet"))
  atlas_write_json(list(taxon = "Strong one", grade = "strong",
                        full_map = list(map = "strong-one.full.png",
                                        bounds = list(south = 14, west = -170, north = 72, east = -52))),
                   atlas_model_path("Strong one", "draft", ".json", "maxnet"))
}

test_that("with the full view on, the map route serves it and a model names it", {
  with_data_dir({
    full_view_fixture()
    env <- c(ATLAS_DATA_DIR = atlas_data_dir(), ATLAS_FULL_VIEW = "on")
    with_env(env, {
      api <- test_api(env)
      default <- call_api(api, "/api/taxa/Strong%20one/map.png")
      expect_equal(default$status, 200L)
      expect_match(default$body, "the default map", fixed = TRUE)
      expect_match(call_api(api, "/api/taxa/Strong%20one/map.png", query = "view=accessible")$body,
                   "the default map", fixed = TRUE)
      full <- call_api(api, "/api/taxa/Strong%20one/map.png", query = "view=full&v=2026")
      expect_equal(full$status, 200L)
      expect_match(full$body, "FULL-VIEW-PICTURE", fixed = TRUE)
      model <- jsonlite::fromJSON(call_api(api, "/api/taxa/Strong%20one/model")$body)
      expect_equal(model$full_map$bounds$north, 72)
      # A weak map has no full view: it makes no claim beyond its reach.
      weak <- call_api(api, "/api/taxa/Weak%20one/map.png", query = "view=full")
      expect_equal(weak$status, 404L)
      expect_match(weak$body, "only strong maps are drawn beyond their reach", fixed = TRUE)
      expect_equal(call_api(api, "/api/taxa/Strong%20one/map.png", query = "view=sideways")$status, 400L)
    })
  })
})

test_that("with the full view off, as by default, nothing offers or serves it", {
  with_data_dir({
    full_view_fixture()
    env <- c(ATLAS_DATA_DIR = atlas_data_dir(), ATLAS_FULL_VIEW = "")
    with_env(env, {
      api <- test_api(env)
      full <- call_api(api, "/api/taxa/Strong%20one/map.png", query = "view=full")
      expect_equal(full$status, 404L)
      expect_match(full$body, "not published on this site yet", fixed = TRUE)
      expect_false(grepl("FULL-VIEW-PICTURE", full$body, fixed = TRUE))
      # Without full_map the taxon page shows no toggle (web/src/lib/mapView.ts hasFullView).
      model <- jsonlite::fromJSON(call_api(api, "/api/taxa/Strong%20one/model")$body)
      expect_null(model$full_map)
      expect_equal(model$grade, "strong")
      # The default map is untouched.
      expect_match(call_api(api, "/api/taxa/Strong%20one/map.png")$body, "the default map", fixed = TRUE)
    })
  })
})
