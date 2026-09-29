# Search finds a taxon however it is typed: in lower case, without a code's
# quotes, with a letter wrong, epithet first, or half-written; and puts taxa
# with maps first among equally good matches.

search_taxa <- function() {
  data.frame(
    scientific_name = c(
      "Trametes versicolor", "Trametes hirsuta", "Mycena sp. 'IN10'", "Mycena \"sp-IN10\"",
      "Mycena sp. 'IN1'", "Mycena sp. 'IN01'", "Mycena galericulata", "Amanita muscaria",
      "Amanita muscaria var. guessowii", "Mycetinis scorodonius", "Armillaria nabsnona"
    ),
    records = c(900, 40, 200, 30, 25, 12, 150, 300, 80, 20, 60),
    localities = c(294, 12, 150, 16, 20, 9, 60, 120, 40, 11, 47),
    fingerprint = "x",
    stringsAsFactors = FALSE
  )
}

names_found <- function(result) result$species$scientific_name

test_that("a provisional code is found however its quotes and sp. are written", {
  index <- atlas_search_index(search_taxa())
  for (typed in c("Mycena sp. 'IN10'", "mycena in10", "Mycena \"sp-IN10\"", "MYCENA sp IN10")) {
    found <- names_found(atlas_search(index, typed))
    expect_true(all(c("Mycena sp. 'IN10'", "Mycena \"sp-IN10\"") %in% utils::head(found, 2)), label = typed)
  }
})

test_that("codes that differ only by a digit stay different names", {
  index <- atlas_search_index(search_taxa())
  result <- atlas_search(index, "mycena IN1")
  expect_equal(names_found(result)[[1]], "Mycena sp. 'IN1'")
  expect_equal(result$species$match[[1]], "exact")
  # 'IN10' starts with 'IN1', so it is a prefix match, below the exact one;
  # 'IN01' is at best a near miss, never an exact match.
  expect_false("exact" %in% result$species$match[names_found(result) == "Mycena sp. 'IN01'"])
})

test_that("a misspelt name is still found, and says it was a near miss", {
  index <- atlas_search_index(search_taxa())
  result <- atlas_search(index, "Tramates versicolour")
  expect_equal(names_found(result)[[1]], "Trametes versicolor")
  expect_equal(result$species$match[[1]], "similar")
})

test_that("words can come in any order and be half-typed", {
  index <- atlas_search_index(search_taxa())
  expect_equal(names_found(atlas_search(index, "versicolor trametes"))[[1]], "Trametes versicolor")
  expect_equal(names_found(atlas_search(index, "tram vers"))[[1]], "Trametes versicolor")
  expect_equal(names_found(atlas_search(index, "muscar"))[1:2],
               c("Amanita muscaria", "Amanita muscaria var. guessowii"))
})

test_that("an exact name beats one that merely starts the same way", {
  index <- atlas_search_index(search_taxa())
  result <- atlas_search(index, "amanita muscaria")
  expect_equal(names_found(result)[[1]], "Amanita muscaria")
  expect_equal(result$species$match[[2]], "prefix")
})

test_that("among equally good matches, a taxon with a map comes first", {
  index <- atlas_search_index(search_taxa())
  unmapped <- atlas_search(index, "trametes")
  expect_equal(names_found(unmapped)[[1]], "Trametes versicolor")  # more localities
  mapped <- atlas_search(index, "trametes", mapped = list(`Trametes hirsuta` = c("maxnet", "rf")))
  expect_equal(names_found(mapped)[[1]], "Trametes hirsuta")
  expect_equal(mapped$species$models[[1]], c("maxnet", "rf"))
  expect_equal(mapped$species$models[[2]], character())
})

test_that("a one-word query also offers genera, with how many taxa and maps each has", {
  index <- atlas_search_index(search_taxa())
  genera <- atlas_search(index, "myc", mapped = list(`Mycena galericulata` = "rf"))$genera
  expect_equal(vapply(genera, `[[`, character(1), "genus"), c("Mycena", "Mycetinis"))
  expect_equal(genera[[1]]$taxa, 5)
  expect_equal(genera[[1]]$mapped, 1)
  expect_equal(vapply(atlas_search(index, "Amanitta")$genera, `[[`, character(1), "genus"), "Amanita")
  expect_length(atlas_search(index, "amanita muscaria")$genera, 0)
})

test_that("an empty or punctuation-only query finds nothing rather than everything", {
  index <- atlas_search_index(search_taxa())
  expect_equal(nrow(atlas_search(index, "")$species), 0)
  expect_equal(nrow(atlas_search(index, " '.-\" ")$species), 0)
})

test_that("the limit is respected", {
  index <- atlas_search_index(search_taxa())
  expect_equal(nrow(atlas_search(index, "m", limit = 3)$species), 3)
})

test_that("a search over seventeen thousand names answers quickly", {
  set.seed(1)
  n <- 17000
  syllables <- c("ma", "ri", "co", "te", "lu", "sa", "pho", "ga", "ne", "ti", "ro", "ci")
  word <- function() paste(sample(syllables, 4, replace = TRUE), collapse = "")
  genus <- vapply(1:1500, function(i) paste0(toupper(substr(w <- word(), 1, 1)), substring(w, 2)), character(1))
  taxa <- data.frame(
    scientific_name = paste(sample(genus, n, replace = TRUE), vapply(1:n, function(i) word(), character(1))),
    records = sample(1:500, n, replace = TRUE), localities = sample(1:200, n, replace = TRUE),
    fingerprint = "x", stringsAsFactors = FALSE
  )
  index <- atlas_search_index(taxa)
  elapsed <- system.time(atlas_search(index, "Macoteri lusaphone"))[["elapsed"]]
  expect_lt(elapsed, 1.5)
})

test_that("the search key drops punctuation and rank words but never letters or digits", {
  expect_equal(atlas_search_key("Mycena sp. 'IN10'"), "mycena in10")
  expect_equal(atlas_search_key("Amanita muscaria var. guessowii"), "amanita muscaria guessowii")
  expect_equal(atlas_search_key("Clitocybe sp. 'fuscidisca-PNW10'"), "clitocybe fuscidisca pnw10")
  expect_false(identical(atlas_search_key("Mycena sp. 'IN1'"), atlas_search_key("Mycena sp. 'IN01'")))
})

test_that("the species itself comes before its varieties when both match", {
  index <- atlas_search_index(search_taxa())
  mapped <- list(`Amanita muscaria var. guessowii` = "rf")
  expect_equal(names_found(atlas_search(index, "amanita musc", mapped))[[1]], "Amanita muscaria")
})

test_that("a typed genus beats the same word as an epithet", {
  taxa <- rbind(search_taxa(), data.frame(scientific_name = c("Hygrocybe cantharellus", "Cantharellus cinnabarinus"),
                                          records = c(500, 10), localities = c(200, 8), fingerprint = "x"))
  index <- atlas_search_index(taxa)
  found <- names_found(atlas_search(index, "cantharelus", list(`Hygrocybe cantharellus` = "rf")))
  expect_equal(found[[1]], "Cantharellus cinnabarinus")
})

test_that("the map list for search keeps only models that drew a map", {
  models <- data.frame(taxon = c("A a", "A a", "B b", "C c"), algorithm = c("maxnet", "rf", "rf", "xgboost"),
                       map = c(TRUE, TRUE, FALSE, TRUE), stringsAsFactors = FALSE)
  mapped <- atlas_search_mapped(models)
  expect_setequal(names(mapped), c("A a", "C c"))
  expect_equal(mapped[["A a"]], c("maxnet", "rf"))
  expect_equal(atlas_search_mapped(models[0, ]), list())
})
