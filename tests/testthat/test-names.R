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

test_that("an author citation is not part of the name", {
  expect_true(same_taxon("Pluteus chrysophaeus", "Pluteus chrysophaeus (Schaeff. ex Lasch) Quél."))
  expect_true(same_taxon("Suillus caerulescens", "Suillus caerulescens A. H. Sm. & Thiers"))
  expect_true(same_taxon("Clavaria zollingeri", "Clavaria zollingeri Lév."))
  expect_true(same_taxon("Entocybe nitida", "Entocybe nitida (Quél.) T. J. Baroni et al."))
  expect_true(same_taxon("Amanita muscaria var. formosa", "Amanita muscaria var. formosa (Pers. ex Fr.) Bertill."))
  expect_true(same_taxon("Cuphophyllus subviolaceus", "Cuphophyllus subviolaceus (Peck) Bon"))
})

test_that("dropping authors never merges different taxa", {
  # A variety is not its species.
  expect_false(same_taxon("Amanita muscaria", "Amanita muscaria var. formosa (Pers. ex Fr.) Bertill."))
  expect_false(same_taxon("Amanita muscaria var. formosa", "Amanita muscaria var. guessowii"))
  expect_false(same_taxon("Clavaria flavipes Pers.", "Clavaria zollingeri Lév."))
  # A hybrid keeps both epithets.
  expect_false(same_taxon("Fomitopsis marianii × nivosella", "Fomitopsis marianii"))
})

test_that("a provisional code keeps its brackets", {
  expect_false(same_taxon("Descomyces sp. 'Marbled (PDD 112668)'", "Descomyces sp. 'Marbled'"))
  expect_equal(atlas_strip_authors("Descomyces sp. 'Marbled (PDD 112668)'"),
               "Descomyces sp. 'Marbled (PDD 112668)'")
})

test_that("spellings of one rank word are one taxon", {
  expect_true(same_taxon("Amanita muscaria ssp. flavivolvata", "Amanita muscaria subsp. flavivolvata"))
  expect_true(same_taxon("Amanita muscaria ssp flavivolvata", "Amanita muscaria subsp flavivolvata",
                         "Amanita muscaria subsp. flavivolvata"))
  expect_true(same_taxon("Lactarius subvernalis var cokeri", "Lactarius subvernalis var. cokeri"))
  expect_true(same_taxon("Inocybe geophylla f. lilacina", "Inocybe geophylla forma lilacina",
                         "Inocybe geophylla fo. lilacina"))
  # With an author after it, too.
  expect_true(same_taxon("Amanita muscaria ssp. flavivolvata Singer", "Amanita muscaria subsp. flavivolvata"))
})

test_that("joining rank spellings never joins different taxa", {
  expect_false(same_taxon("Amanita muscaria ssp. flavivolvata", "Amanita muscaria subsp. guessowii"))
  # A variety is not a subspecies, nor a form a variety, even of one epithet.
  expect_false(same_taxon("Amanita muscaria var. flavivolvata", "Amanita muscaria subsp. flavivolvata"))
  expect_false(same_taxon("Inocybe geophylla f. lilacina", "Inocybe geophylla var. lilacina"))
  # A subspecies is not its species, nor a species whose epithet looks like a rank.
  expect_false(same_taxon("Amanita muscaria ssp. flavivolvata", "Amanita muscaria"))
  expect_false(same_taxon("Amanita var", "Amanita var."))
  # A capital F. is an author's initial, not a form.
  expect_true(same_taxon("Boletus edulis", "Boletus edulis F. Bull."))
  # A form's epithet is kept, not taken for an author.
  expect_equal(atlas_strip_authors("Inocybe geophylla fo. lilacina (Peck) Gillet"), "Inocybe geophylla fo. lilacina")
  # Nothing inside a provisional code is rewritten.
  expect_false(same_taxon("Russula sp. 'IN01 ssp alba'", "Russula sp. 'IN01 subsp alba'"))
})

test_that("a merged subspecies keeps the spelling most records use", {
  names <- c(rep("Amanita muscaria ssp. flavivolvata", 3), "Amanita muscaria subsp. flavivolvata")
  canonical <- atlas_canonical_names(names)
  expect_equal(unname(canonical["Amanita muscaria subsp. flavivolvata"]), "Amanita muscaria ssp. flavivolvata")
})

test_that("a lineage code without quotes is not mistaken for an author", {
  expect_false(same_taxon("Cuphophyllus pratensis PNW06", "Cuphophyllus pratensis"))
  expect_false(same_taxon("Cystolepiota 'seminuda PNW04'", "Cystolepiota seminuda"))
  expect_equal(atlas_strip_authors("Entoloma subg. Pouzarella"), "Entoloma subg. Pouzarella")
})

# ---- renames across pulls (release review s9) ---------------------------------------

pulled <- function(...) {
  pairs <- list(...)
  data.frame(id = as.character(unlist(lapply(pairs, `[[`, 2))),
             scientific_name = rep(vapply(pairs, `[[`, "", 1), vapply(pairs, function(p) length(p[[2]]), 1L)),
             stringsAsFactors = FALSE)
}

test_that("a name gone from a pull whose records mostly moved to one name was renamed to it", {
  before <- pulled(list("Mycena sp. 'IN10'", 1:4), list("Amanita muscaria", 5:6), list("Russula sp. 'X1'", 7:10),
                   list("Lactarius sp. 'Y'", 11:14))
  after <- pulled(list("Mycena indianensis", 1:3), list("Amanita muscaria", 5:6),
                  # Russula X1 split two and two: no majority, no rename.
                  list("Russula a", 7:8), list("Russula b", 9:10),
                  # Lactarius Y lost three of four records and one moved: not a rename.
                  list("Lactarius z", 11))
  found <- atlas_detect_renames(before, after)
  expect_equal(found$from, "Mycena sp. 'IN10'")
  expect_equal(found$to, "Mycena indianensis")
  expect_equal(found$records, 4L)
  expect_equal(found$moved, 3L)
  expect_equal(nrow(atlas_detect_renames(before, before)), 0L)
  expect_equal(nrow(atlas_detect_renames(NULL, after)), 0L)
})

test_that("renames accumulate, a name renamed again keeps its latest, and a name that comes back is dropped", {
  first <- data.frame(from = c("A", "B"), to = c("B", "Q"), records = 3L, moved = 3L, seen = "2026-10-01")
  found <- data.frame(from = "B", to = "C", records = 2L, moved = 2L)
  kept <- atlas_update_renames(first, found, current_names = c("C", "Q"), seen = "2026-10-07")
  expect_equal(kept$from, c("A", "B"))
  expect_equal(kept$to, c("B", "C"))
  expect_equal(kept$seen, c("2026-10-01", "2026-10-07"))
  back <- atlas_update_renames(kept, NULL, current_names = c("A", "C"))
  expect_equal(back$from, "B")
  expect_equal(nrow(atlas_update_renames(NULL, NULL, "A")), 0L)
})

test_that("an old name or another spelling leads to the current name, and nothing else is guessed", {
  names <- c("Mycena indianensis", "Mycena sp. 'IN11'", "Amanita muscaria")
  renames <- data.frame(from = c("Mycena sp. 'IN10'", "Mycena sp. 'OLD'"),
                        to = c("Mycena indianensis", "Mycena sp. 'IN10'"))
  expect_equal(atlas_resolve_name("Amanita muscaria", names, renames)$how, "current")
  spelt <- atlas_resolve_name('Mycena "sp-IN11"', names, renames)
  expect_equal(spelt[c("name", "how")], list(name = "Mycena sp. 'IN11'", how = "spelling"))
  renamed <- atlas_resolve_name("Mycena sp. 'IN10'", names, renames)
  expect_equal(renamed$name, "Mycena indianensis")
  expect_equal(renamed$how, "renamed")
  # A chain is followed, and an old name in another spelling still finds it.
  chained <- atlas_resolve_name('Mycena "sp-OLD"', names, renames)
  expect_equal(chained$name, "Mycena indianensis")
  expect_equal(unlist(chained$via), c('Mycena "sp-OLD"', "Mycena sp. 'IN10'"))
  # Letters and digits are never bent: IN1 is not IN11.
  expect_null(atlas_resolve_name("Mycena sp. 'IN1'", names, renames))
  expect_null(atlas_resolve_name("", names, renames))
  # A loop ends.
  looped <- data.frame(from = c("X", "Y"), to = c("Y", "X"))
  expect_null(atlas_resolve_name("X", names, looped))
})

test_that("a full pull records what was renamed since the last one, and a broken previous pull fails nothing", {
  with_data_dir({
    before <- pulled(list("Mycena sp. 'IN10'", 1:4), list("Amanita muscaria", 5:6))
    after <- pulled(list("Mycena indianensis", 1:4), list("Amanita muscaria", 5:6))
    atlas_record_renames(after, previous = before, quiet = TRUE)
    kept <- atlas_read_renames()
    expect_equal(kept$from, "Mycena sp. 'IN10'")
    expect_equal(kept$to, "Mycena indianensis")
    # The next pull finds nothing new and keeps what was known.
    atlas_record_renames(after, previous = after, quiet = TRUE)
    expect_equal(atlas_read_renames()$to, "Mycena indianensis")
    # With no previous pull to read, the pull goes on.
    expect_silent(atlas_record_renames(after, quiet = TRUE))
  })
})

test_that("through the API: an old name answers with the current one, and an unknown name is a 404", {
  with_data_dir({
    dir.create(atlas_path("occurrences"), recursive = TRUE, showWarnings = FALSE)
    taxa <- data.frame(scientific_name = c("Mycena indianensis", "Amanita muscaria"),
                       records = 3L, localities = 3L, fingerprint = "f")
    jsonlite::write_json(taxa, atlas_path("occurrences", "taxa-latest.json"))
    jsonlite::write_json(data.frame(from = "Mycena sp. 'IN10'", to = "Mycena indianensis", records = 4L,
                                    moved = 4L, seen = "2026-10-07"), atlas_renames_path())
    with_env(c(ATLAS_DATA_DIR = atlas_data_dir()), {
      api <- test_api(c(ATLAS_DATA_DIR = atlas_data_dir()))
      out <- call_api(api, "/api/names/Mycena%20sp.%20'IN10'")
      expect_equal(out$status, 200L)
      body <- jsonlite::fromJSON(out$body)
      expect_equal(body$name, "Mycena indianensis")
      expect_equal(body$how, "renamed")
      expect_equal(body$requested, "Mycena sp. 'IN10'")
      expect_equal(jsonlite::fromJSON(call_api(api, "/api/names/Amanita%20muscaria")$body)$how, "current")
      expect_equal(call_api(api, "/api/names/Nothing%20here")$status, 404L)
    })
  })
})

test_that("a release carries the renames, so the box can follow old names too", {
  with_data_dir({
    dir.create(atlas_path("occurrences"), recursive = TRUE, showWarnings = FALSE)
    writeLines("[]", atlas_renames_path())
    expect_true("occurrences/renames.json" %in% atlas_release_files("draft"))
  })
})
