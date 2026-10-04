# Jobs on EC2, against a fake EC2.
#
# The fake keeps instances in memory. Between the orchestrator's polls each
# worker does what its script says: runs its shard for real (on a fresh
# machine, against the folder store) and shuts down, is reclaimed without
# reporting, hangs, or vanishes from EC2's listings. So whole jobs — spot
# reclaims, deadlines and all — run in seconds without AWS.

test_config <- function(store = "file:///nowhere", ..., commit = strrep("a", 40),
                        types = "c7a.8xlarge,m7a.8xlarge") {
  values <- c(
    ATLAS_STORE = store, ATLAS_EC2_REGION = "us-east-2",
    ATLAS_EC2_SUBNETS = "subnet-a,subnet-b", ATLAS_EC2_SECURITY_GROUP = "sg-1",
    ATLAS_EC2_INSTANCE_PROFILE = "atlas-worker",
    if (!is.null(types)) c(ATLAS_EC2_INSTANCE_TYPES = types),
    unlist(list(...))
  )
  atlas_ec2_config(env = function(name, unset = "") {
    if (name %in% names(values)) values[[name]] else unset
  }, commit = commit)
}

tag_values <- function(tags) {
  stats::setNames(vapply(tags, function(t) t$Value, ""), vapply(tags, function(t) t$Key, ""))
}

# A fake EC2. `script(shard, attempt)` says what each worker does: "work",
# "partial" (saves one more model, then is reclaimed), "reclaim", "hang" or
# "vanish". `refuse(request, call)` may return an error
# message for a run_instances call.
fake_ec2 <- function(store, script = function(shard, attempt) "work",
                     refuse = function(request, call) NULL) {
  state <- new.env()
  state$instances <- list()
  state$requests <- list()
  state$calls <- 0L
  state$terminated <- character()
  state$describe_fails <- 0L
  advance <- function() {
    for (id in names(state$instances)) {
      worker <- state$instances[[id]]
      if (!worker$state %in% c("pending", "running")) next
      if (worker$behaviour == "work") {
        on_machine(machine(), atlas_run_shard(store, worker$job, worker$shard, quiet = TRUE, fit = fake_fit))
        worker$state <- "terminated"
      } else if (worker$behaviour == "partial") {
        # Fits one more model, saves it, and is taken back.
        run_until_lost(store, list(id = worker$job), worker$shard, lost_after(1L), save_seconds = 0)
        worker$state <- "terminated"
      } else if (worker$behaviour == "reclaim") {
        worker$state <- "terminated"
      } else if (worker$behaviour == "vanish") {
        if (worker$state == "running") worker$listed <- FALSE
        worker$state <- "running"
      } else {
        worker$state <- "running"
      }
      state$instances[[id]] <- worker
    }
  }
  client <- list(
    run_instances = function(...) {
      request <- list(...)
      state$calls <- state$calls + 1L
      problem <- refuse(request, state$calls)
      if (!is.null(problem)) stop(problem, call. = FALSE)
      state$requests[[length(state$requests) + 1L]] <- request
      tags <- tag_values(request$TagSpecifications[[1]]$Tags)
      id <- sprintf("i-%017d", length(state$instances) + 1L)
      shard <- as.integer(tags[["atlas-shard"]])
      attempt <- as.integer(tags[["atlas-attempt"]])
      state$instances[[id]] <- list(
        id = id, job = tags[["atlas-job"]], shard = shard, state = "pending", listed = TRUE,
        behaviour = script(shard, attempt), tags = request$TagSpecifications[[1]]$Tags
      )
      list(Instances = list(list(InstanceId = id)))
    },
    describe_instances = function(Filters, NextToken = NULL) {
      if (state$describe_fails > 0L) {
        state$describe_fails <- state$describe_fails - 1L
        stop("RequestExpired: the fake is having a bad day", call. = FALSE)
      }
      advance()
      job <- Filters[[1]]$Values[[1]]
      mine <- Filter(function(i) identical(i$job, job) && i$listed, state$instances)
      list(Reservations = list(list(Instances = unname(lapply(mine, function(i) {
        list(InstanceId = i$id, State = list(Name = i$state), Tags = i$tags)
      })))))
    },
    terminate_instances = function(InstanceIds) {
      for (id in unlist(InstanceIds)) {
        state$instances[[id]]$state <- "terminated"
        state$terminated <- c(state$terminated, id)
      }
      list()
    }
  )
  list(client = client, state = state)
}

# A clock that moves only when the orchestrator waits.
fake_clock <- function(start = as.POSIXct("2026-01-01 00:00:00", tz = "UTC")) {
  now <- start
  list(clock = function() now, wait = function(seconds) now <<- now + seconds)
}

# A planned job on a fresh store: three taxa clear 20 cells, in two shards.
planned <- function(shards = 2L) {
  store <- fresh_store()
  boss <- machine()
  on_machine(boss, orchestrator_data(synthetic_occurrences(TAXA)))
  job <- on_machine(boss, atlas_plan_job(store, algorithms = "maxnet", shards = shards, quiet = TRUE))
  list(store = store, boss = boss, job = job)
}

run_on <- function(setup, ec2, time = fake_clock(), config = test_config(setup$store$uri),
                   image_exists = function(image) TRUE) {
  on_machine(setup$boss, atlas_run_job_on_ec2(
    setup$store, setup$job, ec2 = ec2$client, config = config, poll_seconds = 60,
    wait = time$wait, clock = time$clock, quiet = TRUE, image_exists = image_exists
  ))
}

still_running <- function(ec2) {
  Filter(function(i) i$state %in% c("pending", "running"), ec2$state$instances)
}

user_data <- function(request) rawToChar(jsonlite::base64_dec(request$UserData))

# ---- whole jobs --------------------------------------------------------------

test_that("a job runs on spot workers and finishes into a release, leaving no worker running", {
  skip_if_not_installed("terra")
  setup <- planned()
  ec2 <- fake_ec2(setup$store)
  release <- run_on(setup, ec2)

  expect_equal(atlas_current_release(setup$store)$id, release$id)
  expect_length(release$index, 3L)
  expect_length(ec2$state$requests, 2L)
  expect_length(still_running(ec2), 0L)
})

test_that("a reclaimed spot worker is launched again, and its shard still finishes", {
  skip_if_not_installed("terra")
  setup <- planned()
  ec2 <- fake_ec2(setup$store, script = function(shard, attempt) {
    if (shard == 1L && attempt == 1L) "reclaim" else "work"
  })
  release <- run_on(setup, ec2)

  expect_equal(atlas_current_release(setup$store)$id, release$id)
  shards <- vapply(ec2$state$requests, function(r) tag_values(r$TagSpecifications[[1]]$Tags)[["atlas-shard"]], "")
  attempts <- vapply(ec2$state$requests, function(r) tag_values(r$TagSpecifications[[1]]$Tags)[["atlas-attempt"]], "")
  expect_equal(sort(shards), c("1", "1", "2"))
  expect_true("2" %in% attempts[shards == "1"])
})

test_that("a shard reclaimed every time fails the job after its attempts, and no worker is left running", {
  skip_if_not_installed("terra")
  setup <- planned()
  ec2 <- fake_ec2(setup$store, script = function(shard, attempt) if (shard == 2L) "reclaim" else "hang")
  expect_error(run_on(setup, ec2), "shard 2 .* failed 3 times")
  expect_length(still_running(ec2), 0L)
  expect_null(atlas_current_release(setup$store))
})

test_that("a job past its deadline stops, and every worker is terminated", {
  skip_if_not_installed("terra")
  setup <- planned()
  ec2 <- fake_ec2(setup$store, script = function(shard, attempt) "hang")
  expect_error(run_on(setup, ec2, config = test_config(setup$store$uri, ATLAS_EC2_MAX_HOURS = "1")),
               "past its 1 h deadline")
  expect_length(still_running(ec2), 0L)
  expect_length(ec2$state$terminated, 2L)
  expect_null(atlas_current_release(setup$store))
})

test_that("an orchestrator failure mid-job terminates every worker it launched", {
  skip_if_not_installed("terra")
  setup <- planned()
  ec2 <- fake_ec2(setup$store, script = function(shard, attempt) "hang")
  ec2$state$describe_fails <- 1L
  expect_error(run_on(setup, ec2), "bad day")
  expect_length(ec2$state$requests, 2L)
  expect_length(still_running(ec2), 0L)
})

test_that("a worker EC2 no longer lists counts as gone, and is replaced", {
  skip_if_not_installed("terra")
  setup <- planned()
  ec2 <- fake_ec2(setup$store, script = function(shard, attempt) {
    if (shard == 1L && attempt == 1L) "vanish" else "work"
  })
  release <- run_on(setup, ec2)
  expect_equal(atlas_current_release(setup$store)$id, release$id)
  expect_length(ec2$state$requests, 3L)
})

test_that("a missing image stops the job before any worker is launched", {
  skip_if_not_installed("terra")
  setup <- planned()
  ec2 <- fake_ec2(setup$store)
  expect_error(run_on(setup, ec2, image_exists = function(image) FALSE), "not in its registry")
  expect_equal(ec2$state$calls, 0L)
})

test_that("a job with nothing to fit finishes without EC2", {
  skip_if_not_installed("terra")
  setup <- planned()
  run_on(setup, fake_ec2(setup$store))
  # Taxon C drops under the line: retiring it needs no worker.
  on_machine(setup$boss, orchestrator_data(synthetic_occurrences(c("Taxon A" = 25, "Taxon B" = 30, "Taxon C" = 3))))
  setup$job <- on_machine(setup$boss, atlas_plan_job(setup$store, algorithms = "maxnet", quiet = TRUE))
  expect_equal(setup$job$shards, 0L)
  untouchable <- list(client = list(
    run_instances = function(...) stop("no EC2 call expected"),
    describe_instances = function(...) stop("no EC2 call expected"),
    terminate_instances = function(...) stop("no EC2 call expected")
  ))
  release <- run_on(setup, untouchable)
  expect_length(release$index, 2L)
})

# ---- spot capacity -----------------------------------------------------------

test_that("with no spot capacity in one zone, a launch tries the next zone and type", {
  skip_if_not_installed("terra")
  setup <- planned(shards = 1L)
  ec2 <- fake_ec2(setup$store, refuse = function(request, call) {
    if (call <= 2L) "InsufficientInstanceCapacity (HTTP 500). There is no Spot capacity" else NULL
  })
  run_on(setup, ec2)
  launched <- ec2$state$requests[[1]]
  # c7a in both subnets refused; the third try is the next type.
  expect_equal(launched$InstanceType, "m7a.8xlarge")
  expect_equal(launched$SubnetId, "subnet-a")
})

test_that("when every zone and type refuses, the launch is tried again at the next poll", {
  skip_if_not_installed("terra")
  setup <- planned(shards = 1L)
  ec2 <- fake_ec2(setup$store, refuse = function(request, call) {
    if (call <= 4L) "InsufficientInstanceCapacity (HTTP 500)" else NULL
  })
  time <- fake_clock()
  run_on(setup, ec2, time = time)
  expect_equal(ec2$state$calls, 5L)
  expect_true(time$clock() > as.POSIXct("2026-01-01 00:00:00", tz = "UTC"))
})

test_that("a quota refusal waits for the next poll instead of trying every type", {
  skip_if_not_installed("terra")
  setup <- planned(shards = 1L)
  time <- fake_clock()
  start <- time$clock()
  tries_before_waiting <- 0L
  # The quota holds until the orchestrator has waited once.
  ec2 <- fake_ec2(setup$store, refuse = function(request, call) {
    if (time$clock() == start) {
      tries_before_waiting <<- tries_before_waiting + 1L
      "MaxSpotInstanceCountExceeded (HTTP 400)"
    }
  })
  run_on(setup, ec2, time = time)
  # One refused call, not one per type and zone; then the next poll's launch
  # in the first place again.
  expect_equal(tries_before_waiting, 1L)
  expect_equal(ec2$state$requests[[1]]$InstanceType, "c7a.8xlarge")
  expect_equal(ec2$state$requests[[1]]$SubnetId, "subnet-a")
})

test_that("a launch error that is not about capacity stops the job and terminates the workers already up", {
  skip_if_not_installed("terra")
  setup <- planned()
  ec2 <- fake_ec2(setup$store, script = function(shard, attempt) "hang", refuse = function(request, call) {
    if (call == 2L) "UnauthorizedOperation (HTTP 403). You are not authorized" else NULL
  })
  expect_error(run_on(setup, ec2), "UnauthorizedOperation")
  expect_length(ec2$state$requests, 1L)
  expect_length(still_running(ec2), 0L)
})

test_that("an AWS error code is recognised in paws's message", {
  error <- simpleError("InsufficientInstanceCapacity (HTTP 500). We currently do not have sufficient c7a.8xlarge capacity")
  expect_equal(atlas_ec2_error_code(error), "InsufficientInstanceCapacity")
  expect_true(is.na(atlas_ec2_error_code(simpleError("UnauthorizedOperation (HTTP 403)"))))
  # A code inside a longer word is not that code.
  expect_true(is.na(atlas_ec2_error_code(simpleError("NotUnsupportedAtAll"))))
})

# ---- what a worker is told ---------------------------------------------------

test_that("a worker's shutdown timer is the time left before the job's deadline", {
  skip_if_not_installed("terra")
  setup <- planned(shards = 1L)
  time <- fake_clock()
  # The first launch waits two hours for capacity.
  ec2 <- fake_ec2(setup$store, refuse = function(request, call) {
    if (time$clock() < as.POSIXct("2026-01-01 02:00:00", tz = "UTC")) "InsufficientInstanceCapacity" else NULL
  })
  run_on(setup, ec2, time = time)
  timer <- regmatches(user_data(ec2$state$requests[[1]]), regexpr("shutdown -h [+][0-9]+", user_data(ec2$state$requests[[1]])))
  expect_equal(timer, "shutdown -h +240")
})

test_that("a worker is spot, IMDSv2-only, tagged, and terminates when it shuts down", {
  config <- test_config("s3://bucket")
  request <- atlas_worker_request(config, "job1", 2L, "draft", 1L, "subnet-a", "c7a.8xlarge")
  expect_equal(request$InstanceMarketOptions$MarketType, "spot")
  expect_equal(request$InstanceMarketOptions$SpotOptions$InstanceInterruptionBehavior, "terminate")
  expect_equal(request$InstanceInitiatedShutdownBehavior, "terminate")
  expect_equal(request$MetadataOptions$HttpTokens, "required")
  for (spec in request$TagSpecifications) {
    tags <- tag_values(spec$Tags)
    expect_equal(tags[["atlas"]], "worker")
    expect_equal(tags[["atlas-job"]], "job1")
    expect_equal(tags[["atlas-shard"]], "2")
  }
  expect_setequal(vapply(request$TagSpecifications, function(s) s$ResourceType, ""), c("instance", "volume"))
})

test_that("a worker's boot script carries no credentials, uploads its log, and always shuts down", {
  config <- test_config("s3://bucket")
  script <- atlas_worker_user_data("job1", 3L, "draft", config)
  expect_false(grepl("AWS_ACCESS_KEY|AWS_SECRET|AWS_SESSION_TOKEN", script))
  expect_true(grepl("s3://bucket/jobs/draft/job1/logs/3.log", script, fixed = TRUE))
  expect_true(grepl("--job=job1 --shard=3", script, fixed = TRUE))
  lines <- strsplit(script, "\n")[[1]]
  expect_equal(lines[[length(lines)]], "shutdown -h now")
  # set -e would skip the shutdown after a failed shard.
  expect_false(any(grepl("^set -[a-z]*e", lines)))
})

# ---- configuration -------------------------------------------------------------

test_that("EC2 settings refuse to launch half-configured, naming everything missing", {
  expect_error(atlas_ec2_config(env = function(name, unset = "") unset, commit = strrep("a", 40)),
               "ATLAS_STORE, ATLAS_EC2_REGION, ATLAS_EC2_SUBNETS, ATLAS_EC2_SECURITY_GROUP, ATLAS_EC2_INSTANCE_PROFILE")
})

test_that("workers run the image built from the orchestrator's own commit", {
  config <- test_config(commit = strrep("b", 40))
  expect_equal(config$image, paste0("ghcr.io/biodiverselabs/mycomap-atlas:", strrep("b", 40)))
  expect_error(test_config(commit = NA_character_), "no commit")
  expect_equal(test_config(ATLAS_IMAGE = "example/img:1", commit = NA_character_)$image, "example/img:1")
})

test_that("workers boot the newest Amazon Linux unless told otherwise", {
  expect_match(test_config()$ami, "^resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023")
  expect_equal(test_config(ATLAS_EC2_AMI = "ami-123")$ami, "ami-123")
  expect_equal(test_config()$subnets, c("subnet-a", "subnet-b"))
  expect_error(test_config(ATLAS_EC2_MAX_HOURS = "soon"), "positive number")
})

test_that("a small job gets one worker, a big one no more than allowed", {
  expect_equal(atlas_shard_count(0), 0L)
  expect_equal(atlas_shard_count(5, max_workers = 4, tasks_per_shard = 40), 1L)
  expect_equal(atlas_shard_count(81, max_workers = 4, tasks_per_shard = 40), 3L)
  expect_equal(atlas_shard_count(5000, max_workers = 4, tasks_per_shard = 40), 4L)
})

# ---- the nightly run -----------------------------------------------------------

test_that("a nightly run with nothing changed launches nothing", {
  skip_if_not_installed("terra")
  setup <- planned()
  run_on(setup, fake_ec2(setup$store))
  ec2 <- fake_ec2(setup$store)
  pulled <- FALSE
  result <- on_machine(setup$boss, atlas_nightly(
    algorithms = "maxnet", config = test_config(setup$store$uri), store = setup$store,
    ec2 = ec2$client, quiet = TRUE, pull_occurrences = function(quiet) pulled <<- TRUE,
    image_exists = function(image) TRUE
  ))
  expect_true(pulled)
  expect_null(result)
  expect_equal(ec2$state$calls, 0L)
})

test_that("a nightly run fits new records on EC2 and publishes the release", {
  skip_if_not_installed("terra")
  setup <- planned()
  first <- run_on(setup, fake_ec2(setup$store))
  on_machine(setup$boss, orchestrator_data(synthetic_occurrences(c(TAXA, "Taxon D" = 21))))
  ec2 <- fake_ec2(setup$store)
  time <- fake_clock()
  release <- on_machine(setup$boss, atlas_nightly(
    algorithms = "maxnet", config = test_config(setup$store$uri), store = setup$store,
    ec2 = ec2$client, quiet = TRUE, pull = FALSE, image_exists = function(image) TRUE,
    wait = time$wait, clock = time$clock
  ))
  expect_false(identical(release$id, first$id))
  expect_equal(atlas_current_release(setup$store)$id, release$id)
  expect_length(ec2$state$requests, 1L)
  expect_true("Taxon D" %in% vapply(release$index, function(e) e$taxon, ""))
})

# ---- the small box's disk --------------------------------------------------------

test_that("a machine without layers plans from the store's set, fetching only its manifest", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  builder <- machine()
  on_machine(builder, orchestrator_data(synthetic_occurrences(TAXA)))
  on_machine(builder, atlas_publish_layers(store, quiet = TRUE))

  box <- machine()
  on_machine(box, orchestrator_data(synthetic_occurrences(TAXA)))
  unlink(file.path(box, "layers"), recursive = TRUE)
  job <- on_machine(box, atlas_plan_job(store, algorithms = "maxnet", shards = 1L, quiet = TRUE))

  expect_false(file.exists(file.path(box, "layers", "draft", "fake.tif")))
  expect_true(file.exists(file.path(box, "layers", "draft", "manifest.json")))
  expect_true("layers/draft/fake.tif" %in% vapply(job$inputs, function(e) e$path, ""))
  # The worker still gets the raster, from the store.
  on_machine(machine(), atlas_run_shard(store, job$id, 1L, quiet = TRUE, fit = fake_fit))
  expect_equal(atlas_job_status(store, job$id)$missing, integer())
})

test_that("planning again on a machine without layers still sends the workers every raster", {
  # The first real run: the box's second plan found the manifest its first had
  # fetched, took it for a layer set of its own, and sent workers no rasters.
  skip_if_not_installed("terra")
  store <- fresh_store()
  builder <- machine()
  on_machine(builder, orchestrator_data(synthetic_occurrences(TAXA)))
  on_machine(builder, atlas_publish_layers(store, quiet = TRUE))
  box <- machine()
  on_machine(box, orchestrator_data(synthetic_occurrences(TAXA)))
  unlink(file.path(box, "layers"), recursive = TRUE)

  first <- on_machine(box, atlas_plan_job(store, algorithms = "maxnet", shards = 1L, quiet = TRUE))
  again <- on_machine(box, atlas_plan_job(store, algorithms = "maxnet", shards = 1L, quiet = TRUE))
  for (job in list(first, again)) {
    expect_true("layers/draft/fake.tif" %in% vapply(job$inputs, function(e) e$path, ""))
  }
  on_machine(machine(), atlas_run_shard(store, again$id, 1L, quiet = TRUE, fit = fake_fit))
  expect_equal(atlas_job_status(store, again$id)$missing, integer())
})

test_that("a job whose layers lack a raster the manifest names is never planned", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  boss <- machine()
  on_machine(boss, {
    orchestrator_data(synthetic_occurrences(TAXA))
    atlas_write_json(list(list(id = "fake", md5 = "m1", file = "fake.tif"),
                          list(id = "gone", md5 = "m2", file = "gone.tif")),
                     file.path(atlas_layer_dir("draft"), "manifest.json"))
    expect_error(atlas_plan_job(store, algorithms = "maxnet", quiet = TRUE),
                 "lacks layers/draft/gone.tif; nothing planned")
  })
  expect_length(store$list("jobs/"), 0L)
})

test_that("a first job in which every model failed finishes without error", {
  # The first real run: every fit failed and there was no release before it,
  # and the box stopped with an error while finishing.
  skip_if_not_installed("terra")
  store <- fresh_store()
  boss <- machine()
  on_machine(boss, orchestrator_data(synthetic_occurrences(c("Broken A" = 25, "Broken B" = 30))))
  job <- on_machine(boss, atlas_plan_job(store, algorithms = "maxnet", shards = 1L, quiet = TRUE))
  on_machine(machine(), atlas_run_shard(store, job$id, 1L, quiet = TRUE, fit = fake_fit))
  release <- on_machine(boss, atlas_finish_job(store, job$id, quiet = TRUE))
  expect_true(atlas_job_status(store, job$id)$finished)
  # The failures are planned again next time.
  again <- on_machine(boss, atlas_plan_job(store, algorithms = "maxnet", quiet = TRUE))
  expect_setequal(vapply(again$tasks, function(t) t$taxon, ""), c("Broken A", "Broken B"))
})

test_that("a web server's pull leaves the rasters in the store and keeps none of its own", {
  skip_if_not_installed("terra")
  setup <- planned()
  release <- run_on(setup, fake_ec2(setup$store))
  paths <- release_paths(release)
  rasters <- sum(grepl("[.]tif$", paths))
  expect_gt(rasters, 0L)

  # A web server's first pull never downloads a raster.
  on_machine(machine(), {
    pulled <- atlas_pull_release(setup$store, rasters = FALSE, quiet = TRUE)
    expect_equal(pulled$fetched, length(paths) - rasters)
    expect_false(file.exists(atlas_model_path("Taxon A", "draft", ".tif")))
    expect_true(file.exists(atlas_model_path("Taxon A", "draft", ".json")))
  })
  # A machine that had them keeps none once it pulls without them.
  on_machine(machine(), {
    atlas_pull_release(setup$store, quiet = TRUE)
    expect_true(file.exists(atlas_model_path("Taxon A", "draft", ".tif")))
    atlas_pull_release(setup$store, rasters = FALSE, quiet = TRUE)
    expect_false(file.exists(atlas_model_path("Taxon A", "draft", ".tif")))
  })
})

# ---- the AWS policies ------------------------------------------------------------

aws_dir <- function() testthat::test_path("..", "..", "deploy", "aws")

aws_policy <- function(path) {
  skip_if_not(dir.exists(aws_dir()), "deploy/aws is not in the image")
  env <- new.env()
  sys.source(file.path(aws_dir(), "render.R"), envir = env)
  values <- env$atlas_aws_values("111122223333", "us-east-2", "bucket", "vpc-0a", "sg-0b",
                                 c("subnet-0c", "subnet-0d"))
  text <- paste(readLines(file.path(aws_dir(), path), warn = FALSE), collapse = "\n")
  jsonlite::parse_json(env$atlas_render_aws_template(text, values))
}

statement <- function(policy, sid) Filter(function(s) identical(s$Sid, sid), policy$Statement)[[1]]

glob_matches <- function(patterns, value) {
  any(vapply(unlist(patterns), function(p) {
    grepl(paste0("^", gsub("[*]", ".*", gsub("[.]", "[.]", p)), "$"), value)
  }, logical(1)))
}

test_that("every launch the orchestrator makes is one its IAM policy allows", {
  policy <- aws_policy("orchestrator/permissions.json")
  launch <- statement(policy, "LaunchOnlyTaggedSpotWorkers")$Condition
  disks <- statement(policy, "WorkerDisksTaggedAndCapped")$Condition
  # The default types, as a box that sets no ATLAS_EC2_INSTANCE_TYPES uses them.
  config <- test_config(types = NULL)
  expect_true(length(config$instance_types) >= 2)
  for (type in config$instance_types) {
    request <- atlas_worker_request(config, "job1", 1L, "draft", 1L, config$subnets[[1]], type)
    expect_true(glob_matches(launch$StringLike$`ec2:InstanceType`, request$InstanceType))
    expect_equal(request$InstanceMarketOptions$MarketType, launch$StringEquals$`ec2:InstanceMarketType`)
    expect_equal(request$MetadataOptions$HttpTokens, launch$StringEquals$`ec2:MetadataHttpTokens`)
    expect_equal(sub(".*instance-profile/", "", launch$StringEquals$`ec2:InstanceProfile`),
                 request$IamInstanceProfile$Name)
    for (spec in request$TagSpecifications) {
      expect_equal(tag_values(spec$Tags)[["atlas"]], launch$StringEquals$`aws:RequestTag/atlas`)
    }
    expect_lte(request$BlockDeviceMappings[[1]]$Ebs$VolumeSize,
               as.numeric(disks$NumericLessThanEquals$`ec2:VolumeSize`))
  }
  # The IAM policy, not only this code, refuses a GPU box.
  expect_false(glob_matches(launch$StringLike$`ec2:InstanceType`, "p5.48xlarge"))
})

test_that("a worker may write its results, shard record and log, and nothing that changes a release", {
  policy <- aws_policy("worker/permissions.json")
  writes <- sub("^arn:aws:s3:::bucket/", "", unlist(statement(policy, "WriteResultsAndShardRecordsOnly")$Resource))
  may_write <- function(key) glob_matches(writes, key)
  expect_true(may_write(atlas_object_key(strrep("ab", 32))))
  expect_true(may_write("jobs/draft/job1/shards/1.json"))
  expect_true(may_write("jobs/draft/job1/shards/1.progress.json"))
  expect_true(may_write("jobs/draft/job1/logs/1.log"))
  for (key in c("current/draft.json", "releases/draft/r1.json", "layers/draft/current.json",
                "jobs/draft/job1/job.json", "jobs/draft/job1/finished.json")) {
    expect_false(may_write(key), info = key)
  }
  expect_false(any(grepl("Delete", unlist(lapply(policy$Statement, function(s) s$Action)))))
})

test_that("a list placeholder becomes one string per value, and a missing one is refused", {
  skip_if_not(dir.exists(aws_dir()), "deploy/aws is not in the image")
  env <- new.env()
  sys.source(file.path(aws_dir(), "render.R"), envir = env)
  out <- env$atlas_render_aws_template('{"R": ["${S}", "x"]}', list(S = c("a", "b")))
  expect_equal(jsonlite::parse_json(out)$R, list("a", "b", "x"))
  expect_error(env$atlas_render_aws_template('{"R": "${NOPE}"}', list(S = "a")), "no value for [$][{]NOPE[}]")
})

test_that("the committed AWS templates name no account, network or bucket of ours", {
  skip_if_not(dir.exists(aws_dir()), "deploy/aws is not in the image")
  files <- list.files(aws_dir(), pattern = "[.]json$", recursive = TRUE, full.names = TRUE)
  files <- files[!grepl("/rendered/", files)]
  expect_true(length(files) >= 5)
  for (file in files) {
    text <- paste(readLines(file, warn = FALSE), collapse = "\n")
    expect_false(grepl("[0-9]{12}|vpc-[0-9a-f]{4,}|sg-[0-9a-f]{4,}|subnet-[0-9a-f]{4,}|mycomap-atlas", text),
                 info = basename(file))
  }
})

# ---- workers lost part way -----------------------------------------------------

test_that("a worker lost after saving does not use up its shard's attempts, and its replacement starts from there", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  boss <- machine()
  on_machine(boss, orchestrator_data(synthetic_occurrences(MORE_TAXA)))
  job <- on_machine(boss, atlas_plan_job(store, algorithms = "maxnet", shards = 1L, quiet = TRUE))
  setup <- list(store = store, boss = boss, job = job)
  # Four workers in a row are taken back, each after saving one more model:
  # more than the three attempts a worker that saves nothing is allowed.
  ec2 <- fake_ec2(store, script = function(shard, attempt) if (attempt <= 4L) "partial" else "work")
  release <- run_on(setup, ec2)
  expect_length(ec2$state$requests, 5L)
  expect_length(release$index, 5L)
  expect_equal(release$job_results$fitted, 5L)
  expect_length(still_running(ec2), 0L)
})

test_that("a relaunched worker asks first for the next instance type", {
  skip_if_not_installed("terra")
  setup <- planned(shards = 1L)
  ec2 <- fake_ec2(setup$store, script = function(shard, attempt) if (attempt == 1L) "reclaim" else "work")
  run_on(setup, ec2)
  types <- vapply(ec2$state$requests, function(r) r$InstanceType, "")
  expect_equal(types, c("c7a.8xlarge", "m7a.8xlarge"))
})

test_that("a job past its deadline still publishes every model its workers saved", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  boss <- machine()
  on_machine(boss, orchestrator_data(synthetic_occurrences(MORE_TAXA)))
  job <- on_machine(boss, atlas_plan_job(store, algorithms = "maxnet", shards = 1L, quiet = TRUE))
  setup <- list(store = store, boss = boss, job = job)
  # The first worker saves one model and is taken back; the next hangs until
  # the deadline.
  ec2 <- fake_ec2(store, script = function(shard, attempt) if (attempt == 1L) "partial" else "hang")
  expect_error(run_on(setup, ec2, config = test_config(store$uri, ATLAS_EC2_MAX_HOURS = "1")),
               "past its 1 h deadline.*holds every model they saved")
  expect_length(still_running(ec2), 0L)
  release <- atlas_current_release(store)
  expect_false(is.null(release))
  expect_length(release$index, 1L)
  expect_true(isTRUE(release$partial))
})
