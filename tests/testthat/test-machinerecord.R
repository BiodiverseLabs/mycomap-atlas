# A shard's record names the machine its models were fitted on, down to the
# BLAS build, its threads and the processor's vector extensions: fits are
# bit-identical within a processor family and can differ across families
# (E12, 2026-10-21).

test_that("the BLAS build and version are read from the LAPACK library's path", {
  expect_equal(atlas_blas_build("/usr/lib/x86_64-linux-gnu/openblas-pthread/libopenblasp-r0.3.26.so"),
               list(blas_build = "openblas-pthread", blas_version = "0.3.26"))
  expect_equal(atlas_blas_build("/usr/lib/R/lib/libRlapack.so"), list())
  expect_equal(atlas_blas_build(""), list())
})

test_that("the vector extensions that pick OpenBLAS's kernels are read from the processor's flags", {
  zen4 <- c("model name\t: AMD EPYC 9R14", "flags\t\t: fpu sse4_2 avx avx2 fma avx512f avx512bw avx512vl avx512_bf16")
  expect_equal(atlas_vector_extensions(zen4), "sse4_2,avx,avx2,fma,avx512f,avx512bw,avx512vl,avx512_bf16")
  expect_equal(atlas_vector_extensions(c("flags : fpu sse4_2 avx avx2 fma")), "sse4_2,avx,avx2,fma")
  expect_null(atlas_vector_extensions(character()))
})

test_that("the record says how many BLAS threads the fits ran with, and the cores", {
  expect_equal(with_env(c(OPENBLAS_NUM_THREADS = NA), atlas_machine_info()$blas_threads), "default")
  expect_equal(with_env(c(OPENBLAS_NUM_THREADS = "4"), atlas_machine_info()$blas_threads), "4")
  expect_equal(atlas_machine_info(blas_threads = "1")$blas_threads, "1")
  expect_true(is.integer(atlas_machine_info()$cores))
})

test_that("a shard fitted in worker processes records their one BLAS thread; one fitted in its own process, its own", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  boss <- machine()
  on_machine(boss, orchestrator_data(synthetic_occurrences(TAXA)))
  job <- on_machine(boss, atlas_plan_job(store, algorithms = "maxnet", shards = 1L, quiet = TRUE))
  record <- with_env(c(OPENBLAS_NUM_THREADS = NA),
                     on_machine(machine(), atlas_run_shard(store, job$id, 1L, quiet = TRUE, fit = fake_fit)))
  expect_equal(record$machine$blas_threads, "default")
  expect_true(all(vapply(Filter(function(r) !is.null(r$machine), record$results),
                         function(r) identical(r$machine$blas_threads, "default"), logical(1))))
  local_mocked_bindings(atlas_fit_batch = function(...) list(settings_key = "k"))
  pooled <- with_env(c(OPENBLAS_NUM_THREADS = NA),
                     on_machine(machine(), atlas_run_shard(store, job$id, 1L, workers = 4L, quiet = TRUE, fit = fake_fit)))
  expect_equal(pooled$machine$blas_threads, ATLAS_WORKER_ENV[["OPENBLAS_NUM_THREADS"]])
})
