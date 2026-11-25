# The frozen release's cells made now, from its own privacy list
# (atlas_cells_now_frozen_run, R/cellsnow.R).

frozen_cells_setup <- function(check) {
  without_guards(with_data_dir({
    computed_data()
    store <- new_store()
    release <- atlas_publish_release(store, quiet = TRUE)
    pull <- atlas_read_occurrences()
    # The release's own list (empty here), kept apart from this machine's latest.
    own <- tempfile(fileext = ".tsv.gz")
    atlas_write_tsv_gz(data.frame(source = character(), observation_id = character(), privacy = character()), own)
    check(store, release, pull, own)
  }))
}

test_that("cells-now for the frozen release refuses any other release", {
  frozen_cells_setup(function(store, release, pull, own) {
    expect_error(atlas_cells_now_frozen_run(tempfile(), release$id, own, store, frozen = "20990101T000000Z-other",
                                            run = function(...) stop("no query may be sent")),
                 "only for the frozen release")
    expect_error(suppressMessages(atlas_main(c("cells-now", paste0("--out=", tempfile()), paste0("--release=", release$id),
                                               paste0("--privacy-list=", own), paste0("--store=", store$uri)))),
                 "only for the frozen release")
  })
})

test_that("the frozen release's list must alone give its own cells before anyone is asked how the sources stand", {
  frozen_cells_setup(function(store, release, pull, own) {
    # A list that hides one record more than the release's own does not give its cells.
    wrong <- tempfile(fileext = ".tsv.gz")
    atlas_write_tsv_gz(data.frame(source = pull$source[1], observation_id = pull$observation_id[1], privacy = "place"),
                       wrong)
    dir <- tempfile("cells-now-")
    expect_error(atlas_cells_now_frozen_run(dir, release$id, wrong, store, frozen = release$id,
                                            run = function(...) stop("no query may be sent")),
                 "alone does not give release")
    expect_false(dir.exists(dir))
    expect_error(atlas_cells_now_frozen_run(dir, release$id, tempfile(), store, frozen = release$id), "--privacy-list")
  })
})

test_that("cells made now for the frozen release record its list's hash and leave out what the sources hide now", {
  frozen_cells_setup(function(store, release, pull, own) {
    # This machine's own cells file is not the release's: the release's is fetched from the store.
    atlas_write_tsv_gz(data.frame(taxon = "x", lat = 0, lng = 0, records = 1L), atlas_public_cells_path())
    dir <- tempfile("cells-now-")
    status <- planted_status(pull, inat_hidden = pull$observation_id[[3]])
    summary <- atlas_cells_now_frozen_run(dir, release$id, own, store, frozen = release$id, status = status)
    expect_identical(summary$privacy_list$sha256, atlas_sha256(own))
    expect_equal(summary$privacy_list$records, 0L)
    expect_equal(summary$left_out_beyond_the_list, 1L)
    expect_silent(atlas_read_cells_now(dir, release))
  })
})
