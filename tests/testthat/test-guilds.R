# Guilds from FungalTraits, looked up by genus. The table itself is never in
# the repository, so these tests write small stand-ins.

write_guild_table <- function(rows, path = atlas_guild_table_path()) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  table <- data.frame(
    jrk_template = seq_len(nrow(rows)), Phylum = "Basidiomycota",
    GENUS = rows$genus, `COMMENT on genus` = "", primary_lifestyle = rows$lifestyle,
    Secondary_lifestyle = "", check.names = FALSE, stringsAsFactors = FALSE
  )
  utils::write.csv(table, path, row.names = FALSE, na = "")
  invisible(path)
}

SMALL_TABLE <- data.frame(
  genus = c("Amanita", "Mycena", "Trichaptum", "Russula", "Blankia", "Twiceia", "Twiceia", "Onceia", "Onceia"),
  lifestyle = c("ectomycorrhizal", "litter_saprotroph", "wood_saprotroph", "Ectomycorrhizal ",
                "", "plant_pathogen", "ectomycorrhizal", "soil_saprotroph", "soil_saprotroph"),
  stringsAsFactors = FALSE
)

test_that("a taxon's genus is the first word of its name, provisional or not", {
  expect_equal(atlas_taxon_genus("Mycena sp. 'IN10'"), "Mycena")
  expect_equal(atlas_taxon_genus("Amanita muscaria var. guessowii"), "Amanita")
  expect_equal(atlas_taxon_genus("  Russula   brevipes "), "Russula")
  expect_equal(atlas_taxon_genus("Cortinarius"), "Cortinarius")
  # Not a Latin genus: no genus rather than a wrong one.
  expect_true(is.na(atlas_taxon_genus("'IN10' unknown")))
  expect_true(is.na(atlas_taxon_genus("cf. Russula")))
  expect_true(is.na(atlas_taxon_genus(NA)))
  expect_equal(atlas_taxon_genus(c("Suillus luteus", "Pluteus cervinus")), c("Suillus", "Pluteus"))
})

test_that("the table is read as genus to lifestyle, tidied, blanks and homonyms left out", {
  with_data_dir({
    write_guild_table(SMALL_TABLE)
    guilds <- atlas_read_guild_table()
    expect_equal(guilds[["Amanita"]], "ectomycorrhizal")
    # Case and stray spaces do not make a new guild.
    expect_equal(guilds[["Russula"]], "ectomycorrhizal")
    # No lifestyle recorded: not listed, so unknown.
    expect_false("Blankia" %in% names(guilds))
    # One name for two fungi with different lifestyles is not guessed at...
    expect_false("Twiceia" %in% names(guilds))
    # ...but a genus listed twice alike is kept.
    expect_equal(guilds[["Onceia"]], "soil_saprotroph")
  })
})

test_that("a taxon's guild comes from its genus, and is unknown when not listed", {
  with_data_dir({
    write_guild_table(SMALL_TABLE)
    guilds <- atlas_read_guild_table()
    expect_equal(atlas_taxon_guild("Amanita muscaria", guilds), "ectomycorrhizal")
    expect_equal(atlas_taxon_guild("Mycena sp. 'IN10'", guilds), "litter_saprotroph")
    expect_equal(atlas_taxon_guild("Notagenus fictus", guilds), "unknown")
    expect_equal(atlas_taxon_guild("Twiceia confusa", guilds), "unknown")
    expect_equal(atlas_taxon_guild("'IN10' unknown", guilds), "unknown")
  })
})

test_that("without the table every guild is unknown, and nothing fails", {
  with_data_dir({
    expect_false(file.exists(atlas_guild_table_path()))
    expect_length(atlas_guild_table(), 0L)
    expect_equal(atlas_taxon_guild(c("Amanita muscaria", "Mycena galericulata")),
                 c("unknown", "unknown"))
    expect_equal(atlas_guild_table_key(), "none")
  })
})

test_that("something that is not the genus table is refused", {
  with_data_dir({
    dir.create(dirname(atlas_guild_table_path()), recursive = TRUE)
    writeLines(c("a,b", "1,2"), atlas_guild_table_path())
    expect_error(atlas_read_guild_table(), "not a FungalTraits genus table")
  })
})

test_that("the table lives in the data directory, never in the repository", {
  with_data_dir({
    expect_true(startsWith(normalizePath(atlas_guild_table_path(), mustWork = FALSE),
                           normalizePath(atlas_data_dir(), mustWork = FALSE)))
  })
})

test_that("the table's key follows its contents, not its file", {
  a <- c(Amanita = "ectomycorrhizal", Mycena = "litter_saprotroph")
  expect_equal(atlas_guild_table_key(a), atlas_guild_table_key(rev(a)))
  changed <- c(Amanita = "ectomycorrhizal", Mycena = "wood_saprotroph")
  expect_false(atlas_guild_table_key(a) == atlas_guild_table_key(changed))
  expect_equal(atlas_guild_table_key(character()), "none")
})

test_that("the table is read again once it changes on disk", {
  with_data_dir({
    write_guild_table(SMALL_TABLE[1, ])
    expect_equal(names(atlas_guild_table()), "Amanita")
    write_guild_table(SMALL_TABLE[1:2, ])
    expect_setequal(names(atlas_guild_table()), c("Amanita", "Mycena"))
  })
})

test_that("fetching the table writes it where it is looked for, and refuses anything else", {
  with_data_dir({
    csv <- tempfile(fileext = ".csv")
    write_guild_table(SMALL_TABLE, csv)
    served <- function(url, dest) {
      expect_equal(url, ATLAS_FUNGALTRAITS_URL)
      file.copy(csv, dest, overwrite = TRUE)
      200L
    }
    atlas_fetch_guild_table(http = served, quiet = TRUE)
    expect_equal(atlas_taxon_guild("Amanita muscaria"), "ectomycorrhizal")

    unlink(atlas_guild_table_path())
    expect_error(atlas_fetch_guild_table(http = function(url, dest) 404L, quiet = TRUE), "HTTP 404")
    expect_false(file.exists(atlas_guild_table_path()))
  })
})
