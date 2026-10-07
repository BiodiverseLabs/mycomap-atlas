# The sitemap tells search engines which pages exist: the app's own, and a
# taxon page for every map worth finding. Written on the web server from the
# models it holds (R/sitemap.R), never from the API.

sitemap_models <- function(...) {
  rows <- list(...)
  do.call(rbind, lapply(rows, function(r) {
    atlas_model_summary(list(
      taxon = r$taxon, algorithm = r$algorithm %||% "maxnet", skill = r$skill,
      map = if (isTRUE(r$map %||% TRUE)) "map.png", built_at = r$built_at %||% "2026-10-01T07:00:00Z"
    ))
  }))
}

sitemap_locs <- function(xml) {
  regmatches(xml, gregexpr("(?<=<loc>)[^<]*(?=</loc>)", xml, perl = TRUE))[[1]]
}

test_that("a taxon is listed only when a model that passed its null test drew it a map", {
  models <- sitemap_models(
    list(taxon = "Amanita muscaria", skill = "passed"),
    list(taxon = "Boletus edulis", skill = "failed"),
    list(taxon = "Craterellus tubaeformis", skill = "passed", map = FALSE),
    list(taxon = "Daedalea quercina", skill = "untested"),
    list(taxon = "Exidia recisa", skill = "failed", algorithm = "maxnet"),
    list(taxon = "Exidia recisa", skill = "passed", algorithm = "xgboost")
  )
  expect_equal(atlas_sitemap_taxa(models)$taxon, c("Amanita muscaria", "Exidia recisa"))
})

test_that("a taxon with several passing models is listed once, dated by the newest", {
  models <- sitemap_models(
    list(taxon = "Exidia recisa", skill = "passed", algorithm = "maxnet", built_at = "2026-09-01T07:00:00Z"),
    list(taxon = "Exidia recisa", skill = "passed", algorithm = "rf", built_at = "2026-10-03T07:00:00Z"),
    list(taxon = "Exidia recisa", skill = "failed", algorithm = "xgboost", built_at = "2026-10-05T07:00:00Z"),
    list(taxon = "Amanita muscaria", skill = "passed", built_at = "")
  )
  taxa <- atlas_sitemap_taxa(models)
  expect_equal(taxa$taxon, c("Amanita muscaria", "Exidia recisa"))
  # A failed model's later build does not count; an undated one gets no date.
  expect_equal(taxa$lastmod, c(NA, "2026-10-03"))
  xml <- atlas_sitemap_xml(taxa, "https://atlas.mycomap.org")
  expect_match(xml, "<loc>https://atlas.mycomap.org/taxa/Exidia%20recisa</loc><lastmod>2026-10-03</lastmod>", fixed = TRUE)
  expect_match(xml, "<loc>https://atlas.mycomap.org/taxa/Amanita%20muscaria</loc></url>", fixed = TRUE)
})

test_that("a taxon's address is the one the app's own links use", {
  # encodeURIComponent, as web/src/components/Search.tsx builds /taxa/ links.
  expect_equal(atlas_url_component("Cortinarius sp. 'IN01'"), "Cortinarius%20sp.%20'IN01'")
  expect_equal(atlas_url_component("Amanita sp. A&B/2"), "Amanita%20sp.%20A%26B%2F2")
  expect_equal(atlas_url_component("Russula \u00d7 hybrida"), "Russula%20%C3%97%20hybrida")
  expect_equal(atlas_url_component("Mycena (s.l.) *x~!"), "Mycena%20(s.l.)%20*x~!")
})

test_that("the sitemap is well-formed XML that escapes what XML must", {
  taxa <- data.frame(taxon = "Cortinarius sp. 'IN01'", lastmod = NA_character_)
  xml <- atlas_sitemap_xml(taxa, "https://atlas.mycomap.org/")
  expect_match(xml, "^<\\?xml version=\"1.0\" encoding=\"UTF-8\"\\?>\n<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">")
  expect_match(xml, "/taxa/Cortinarius%20sp.%20&apos;IN01&apos;</loc>", fixed = TRUE)
  expect_false(grepl("'", sub("^<\\?xml[^>]*>", "", xml)))
  # One closing tag for every opening one.
  for (tag in c("urlset", "url", "loc")) {
    opened <- lengths(regmatches(xml, gregexpr(paste0("<", tag, "[ >]"), xml)))
    closed <- lengths(regmatches(xml, gregexpr(paste0("</", tag, ">"), xml)))
    expect_equal(opened, closed, label = tag)
  }
})

test_that("every address is on the public site, and every page of the app is listed", {
  taxa <- atlas_sitemap_taxa(sitemap_models(list(taxon = "Amanita muscaria", skill = "passed")))
  locs <- sitemap_locs(atlas_sitemap_xml(taxa, "https://atlas.mycomap.org"))
  expect_true(all(startsWith(locs, "https://atlas.mycomap.org/")))
  expect_equal(locs[seq_along(ATLAS_SITEMAP_PAGES)], paste0("https://atlas.mycomap.org", ATLAS_SITEMAP_PAGES))
  expect_equal(length(locs), length(ATLAS_SITEMAP_PAGES) + 1L)
})

test_that("the sitemap's pages are the app's own pages, no more and no fewer", {
  app <- testthat::test_path("..", "..", "web", "src", "App.tsx")
  skip_if_not(file.exists(app), "the web app's sources are not here (release image)")
  lines <- readLines(app, warn = FALSE)
  # Pages with a component of their own; not /taxa/:name, nor a redirect.
  routes <- regmatches(lines, regexpr("<Route path=\"/[^\"]*\" component=", lines))
  routes <- sub("<Route path=\"([^\"]*)\".*", "\\1", routes)
  routes <- routes[!grepl(":", routes)]
  expect_setequal(ATLAS_SITEMAP_PAGES, routes)
})

test_that("a sitemap is refused without the public site's origin", {
  taxa <- atlas_sitemap_taxa(NULL)
  for (origin in list("", "atlas.mycomap.org", "https://atlas.mycomap.org/taxa", NA_character_, NULL)) {
    expect_error(atlas_sitemap_xml(taxa, origin), "origin", label = format(origin))
  }
})

test_that("with no passing maps, the sitemap still lists the pages", {
  locs <- sitemap_locs(atlas_sitemap_xml(atlas_sitemap_taxa(NULL), "https://atlas.mycomap.org"))
  expect_equal(locs, paste0("https://atlas.mycomap.org", ATLAS_SITEMAP_PAGES))
})

test_that("the written sitemap is the file nginx serves, and an oversized one is refused", {
  path <- file.path(tempfile("sitemap"), "sitemap.xml")
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)
  models <- sitemap_models(
    list(taxon = "Amanita muscaria", skill = "passed"),
    list(taxon = "Russula \u00d7 hybrida", skill = "passed")
  )
  expect_message(atlas_write_sitemap(path, "https://atlas.mycomap.org", models = models), "2 taxa")
  written <- readChar(path, file.size(path), useBytes = TRUE)
  expect_identical(written, atlas_sitemap_xml(atlas_sitemap_taxa(models), "https://atlas.mycomap.org"))
  expect_false(file.exists(paste0(path, ".tmp")))
  expect_error(
    atlas_write_sitemap(path, "https://atlas.mycomap.org", models = models, max = length(ATLAS_SITEMAP_PAGES) + 1L),
    "split the sitemap"
  )
})

test_that("the command line writes the sitemap into the data directory", {
  with_data_dir({
    expect_message(atlas_main(c("sitemap", "--origin=https://atlas.mycomap.org")), "0 taxa")
    expect_true(file.exists(file.path(atlas_data_dir(), "sitemap.xml")))
  })
})
