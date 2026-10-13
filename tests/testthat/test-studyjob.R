# Study jobs: a study command sharded onto the EC2 machinery, publishing its
# own results under study/<id>/, never a release.

test_that("a study job is planned for a study command only, and sets --shard and --out itself", {
  store <- fresh_store()
  commands <- c("study-rescan", "plan-job")
  expect_error(atlas_plan_study_job(store, "plan-job", commands = commands, quiet = TRUE), "study command")
  expect_error(atlas_plan_study_job(store, "study-nothing", commands = commands, quiet = TRUE), "no command")
  expect_error(atlas_plan_study_job(store, "study-rescan", args = "--out=releases/", commands = commands, quiet = TRUE),
               "sets --shard and --out itself")
  job <- atlas_plan_study_job(store, "study-rescan", args = c("--sample=200"), shards = 3L, commands = commands,
                              quiet = TRUE)
  expect_equal(job$kind, "study")
  expect_equal(job$shards, 3L)
  expect_match(job$out, paste0("^study/", job$id, "/$"))
  expect_identical(atlas_read_job(store, job$id)$command, "study-rescan")
})

test_that("a worker runs its shard of the study command with the job's arguments, and records the outcome", {
  store <- fresh_store()
  job <- atlas_plan_study_job(store, "study-rescan", args = c("--sample=200"), shards = 2L,
                              commands = "study-rescan", quiet = TRUE)
  seen <- new.env()
  record <- on_machine(machine(), atlas_run_study_shard(worker_store(store), job$id, 2L, quiet = TRUE,
                                                        main = fake_study_main(store, seen = seen)))
  expect_identical(seen$argv[[1]], c("study-rescan", "--sample=200", "--shard=2/2", paste0("--out=", job$out)))
  expect_equal(record$status, "succeeded")
  expect_true(store$exists(paste0(job$out, "result-2.json")))
  failed <- on_machine(machine(), atlas_run_study_shard(store, job$id, 1L, quiet = TRUE,
                                                        main = fake_study_main(store, fail_shard = 1L)))
  expect_equal(failed$status, "failed")
  expect_match(failed$error, "bad day")
  expect_error(atlas_study_outcome(store, job), "shard 1 [(]the study's bad day[)] failed")
})

test_that("a study job gets a release's job inputs when it names one", {
  skip_if_not_installed("terra")
  setup <- prior_only_setup()
  main_job <- atlas_read_job(setup$store, setup$main$job)
  job <- on_machine(setup$boss, atlas_plan_study_job(setup$store, "study-rescan", from_release = setup$main$id,
                                                     commands = "study-rescan", quiet = TRUE))
  expect_identical(job$inputs, main_job$inputs)
  dir <- machine()
  on_machine(dir, atlas_run_study_shard(setup$store, job$id, 1L, quiet = TRUE,
                                        main = fake_study_main(setup$store)))
  expect_true(file.exists(file.path(dir, atlas_job_pull_entry(main_job)$path)))
})

test_that("a study job is never finished as a job", {
  store <- fresh_store()
  job <- atlas_plan_study_job(store, "study-rescan", shards = 1L, commands = "study-rescan", quiet = TRUE)
  expect_error(atlas_finish_job(store, job$id, quiet = TRUE), "study job")
})

test_that("the study commands of this version are found in atlas_main's dispatch", {
  commands <- atlas_cli_commands()
  expect_true(all(c("plan-job", "run-shard", "run-study", "plan-study") %in% commands))
})

test_that("a study command that returns a failing exit code is a failed shard", {
  store <- fresh_store()
  job <- atlas_plan_study_job(store, "study-rescan", shards = 1L, commands = "study-rescan", quiet = TRUE)
  record <- on_machine(machine(), atlas_run_study_shard(store, job$id, 1L, quiet = TRUE,
                                                        main = function(argv) invisible(1L)))
  expect_equal(record$status, "failed")
  expect_equal(record$error, "exit code 1")
})
