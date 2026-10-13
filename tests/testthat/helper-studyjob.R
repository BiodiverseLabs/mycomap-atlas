# Shared by the study job tests (test-studyjob.R) and the EC2 tests.

# A stand-in study command: writes one result per shard under --out, as the
# experiments lane's commands do, or fails when told to.
fake_study_main <- function(store, fail_shard = NA_integer_, seen = new.env()) {
  seen$argv <- list()
  function(argv) {
    seen$argv[[length(seen$argv) + 1L]] <- argv
    flags <- atlas_parse_flags(argv[-1])
    shard <- as.integer(sub("/.*$", "", flags$shard))
    if (identical(shard, as.integer(fail_shard))) stop("the study's bad day")
    file <- tempfile(fileext = ".json")
    atlas_write_json(list(shard = shard, argv = argv), file)
    store$put(paste0(flags$out, "result-", shard, ".json"), file)
    invisible(0L)
  }
}
