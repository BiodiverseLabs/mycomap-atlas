test_that("flags with values are parsed", {
  flags <- atlas_parse_flags(c("--since=2026-09-01", "--chunk-size=500"))
  expect_equal(flags$since, "2026-09-01")
  expect_equal(flags$chunk_size, "500")
})

test_that("a flag without a value is TRUE", {
  expect_true(atlas_parse_flags("--dry-run")$dry_run)
})

test_that("a bare argument is refused, so a typo never runs a full pull", {
  expect_error(atlas_parse_flags("since=2026-09-01"), "unexpected argument")
})

test_that("no flags gives an empty list", {
  expect_equal(length(atlas_parse_flags(character())), 0L)
})

test_that("a flag is read by its exact name, never by a prefix of a longer one", {
  # Every pair of flag names where one begins the other.
  pairs <- list(c("kernels", "kernels-from"), c("algorithm", "algorithms"), c("only", "only-missing"),
                c("pool", "pool-from"), c("record", "record-names"), c("defaults", "defaults-from"))
  for (pair in pairs) {
    short <- gsub("-", "_", pair[[1]])
    long <- gsub("-", "_", pair[[2]])
    flags <- atlas_parse_flags(paste0("--", pair[[2]], "=x"))
    expect_null(flags[[short]], info = pair[[1]])
    # The `$` the commands use, by name, as atlas_main reads it.
    expect_null(eval(call("$", flags, as.name(short))), info = pair[[1]])
    expect_equal(eval(call("$", flags, as.name(long))), "x", info = pair[[2]])
    both <- atlas_parse_flags(c(paste0("--", pair[[1]], "=a"), paste0("--", pair[[2]], "=b")))
    expect_equal(eval(call("$", both, as.name(short))), "a", info = pair[[1]])
  }
})

# study-score as a study job's shard runs it (atlas_run_study_shard): the
# job's command and args, then --shard and --out.
score_argv <- function(...) {
  c("study-score", "--hindcast=priv-h1", ..., "--shard=1/1", "--out=study/study-x/")
}

test_that("study-score takes --kernels-from alone through the command line, as a study job runs it", {
  got <- NULL
  local_mocked_bindings(atlas_score_study = function(...) { got <<- list(...); invisible(list()) },
                        atlas_flag_store = function(flags) NULL)
  atlas_main(score_argv("--kernels-from=study-a,study-b"))
  expect_null(got$kernels)
  expect_equal(got$kernels_from, c("study-a", "study-b"))
  atlas_main(score_argv("--kernels=a.json,b.json"))
  expect_equal(got$kernels, c("a.json", "b.json"))
  expect_null(got$kernels_from)
})

test_that("study-score takes --defaults-from through the command line, as a study job runs it", {
  got <- NULL
  local_mocked_bindings(atlas_score_study = function(...) { got <<- list(...); invisible(list()) },
                        atlas_flag_store = function(flags) NULL)
  atlas_main(score_argv("--defaults-from=study-e6a"))
  expect_null(got$defaults)
  expect_equal(got$defaults_from, "study-e6a")
})
