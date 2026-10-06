correlated_frame <- function(n = 200, seed = 4) {
  set.seed(seed)
  base <- stats::rnorm(n)
  data.frame(
    bio1 = base,                      # high priority
    bio10 = base + stats::rnorm(n, sd = 0.01), # a near-copy, lower priority
    bio12 = stats::rnorm(n),          # independent, highest priority
    soil_phh2o = stats::rnorm(n)      # independent
  )
}

test_that("one of a correlated pair is kept, and it is the higher priority one", {
  kept <- atlas_prune_correlated(correlated_frame())
  expect_true("bio1" %in% kept)
  expect_false("bio10" %in% kept)
})

test_that("independent predictors all survive", {
  kept <- atlas_prune_correlated(correlated_frame())
  expect_true(all(c("bio12", "soil_phh2o") %in% kept))
  expect_equal(length(kept), 3L)
})

test_that("priority decides, not the order the columns happen to be in", {
  frame <- correlated_frame()
  shuffled <- frame[, c("bio10", "soil_phh2o", "bio1", "bio12")]
  expect_setequal(atlas_prune_correlated(frame), atlas_prune_correlated(shuffled))
})

test_that("a looser threshold keeps more predictors", {
  frame <- correlated_frame()
  expect_gte(
    length(atlas_prune_correlated(frame, threshold = 0.99)),
    length(atlas_prune_correlated(frame, threshold = 0.5))
  )
})

test_that("negative correlation counts as correlation", {
  set.seed(7)
  base <- stats::rnorm(200)
  frame <- data.frame(bio1 = base, bio10 = -base + stats::rnorm(200, sd = 0.01))
  kept <- atlas_prune_correlated(frame)
  expect_equal(kept, "bio1")
})

test_that("a predictor that never varies is dropped", {
  frame <- correlated_frame()
  frame$soil_cec <- 5
  expect_false("soil_cec" %in% atlas_prune_correlated(frame))
  expect_false("soil_cec" %in% atlas_drop_constant(frame))
})

test_that("an all-missing predictor is dropped rather than breaking the maths", {
  frame <- correlated_frame()
  frame$soil_clay <- NA_real_
  expect_false("soil_clay" %in% atlas_prune_correlated(frame))
})

test_that("a predictor outside the priority list is still considered, last", {
  frame <- correlated_frame()
  frame$mystery <- stats::rnorm(nrow(frame))
  expect_true("mystery" %in% atlas_prune_correlated(frame))
})

test_that("correlations are read off the background, not the presences", {
  # Presences are few and unrepresentative; a pair correlated only among them
  # must not decide the choice.
  set.seed(11)
  background <- correlated_frame(n = 300)
  presence <- data.frame(
    bio1 = 1:5, bio10 = 1:5, bio12 = 1:5, soil_phh2o = 1:5 # perfectly aligned
  )
  training <- rbind(
    data.frame(presence = 1L, cell = 1:5, x = 0, y = 0, presence),
    data.frame(
      presence = 0L, cell = seq_len(nrow(background)) + 5L, x = 0, y = 0, background
    )
  )
  kept <- atlas_choose_predictors(training)
  expect_true(all(c("bio12", "soil_phh2o") %in% kept))
})

test_that("with no background at all, every predictor is offered", {
  training <- data.frame(
    presence = 1L, cell = 1:5, x = 0, y = 0,
    bio1 = stats::rnorm(5), bio12 = stats::rnorm(5)
  )
  expect_setequal(atlas_choose_predictors(training), c("bio1", "bio12"))
})

test_that("a sparse taxon gets a short predictor list", {
  set.seed(3)
  background <- data.frame(
    bio12 = stats::rnorm(400), bio1 = stats::rnorm(400),
    cover_trees = stats::rnorm(400), soil_phh2o = stats::rnorm(400),
    elevation = stats::rnorm(400), slope = stats::rnorm(400),
    roughness = stats::rnorm(400), bio15 = stats::rnorm(400)
  )
  training <- rbind(
    data.frame(presence = 1L, cell = 1:20, x = 0, y = 0, background[1:20, ]),
    data.frame(presence = 0L, cell = 21:420, x = 0, y = 0, background)
  )
  # 20 presences, one predictor per four records: five survive.
  expect_equal(length(atlas_choose_predictors(training)), 5L)
})

test_that("the cap keeps the ecologically primary variables", {
  set.seed(3)
  background <- data.frame(
    roughness = stats::rnorm(400), slope = stats::rnorm(400),
    bio12 = stats::rnorm(400), bio1 = stats::rnorm(400)
  )
  training <- rbind(
    data.frame(presence = 1L, cell = 1:8, x = 0, y = 0, background[1:8, ]),
    data.frame(presence = 0L, cell = 9:408, x = 0, y = 0, background)
  )
  kept <- atlas_choose_predictors(training, minimum = 2)
  expect_equal(kept, c("bio12", "bio1"))
})

test_that("a well-recorded taxon is not capped", {
  set.seed(3)
  background <- data.frame(
    bio12 = stats::rnorm(600), bio1 = stats::rnorm(600),
    cover_trees = stats::rnorm(600), soil_phh2o = stats::rnorm(600)
  )
  training <- rbind(
    data.frame(presence = 1L, cell = 1:400, x = 0, y = 0, background[1:400, ]),
    data.frame(presence = 0L, cell = 401:1000, x = 0, y = 0, background)
  )
  expect_equal(length(atlas_choose_predictors(training)), 4L)
})

test_that("even a tiny taxon keeps a workable minimum", {
  set.seed(3)
  background <- as.data.frame(matrix(stats::rnorm(400 * 8), ncol = 8))
  names(background) <- c("bio12", "bio1", "cover_trees", "soil_phh2o",
                         "elevation", "slope", "roughness", "bio15")
  training <- rbind(
    data.frame(presence = 1L, cell = 1:4, x = 0, y = 0, background[1:4, ]),
    data.frame(presence = 0L, cell = 5:404, x = 0, y = 0, background)
  )
  expect_equal(length(atlas_choose_predictors(training)), 5L)
})

test_that("an infinite ratio lifts the cap rather than shrinking the list", {
  set.seed(3)
  background <- as.data.frame(matrix(stats::rnorm(400 * 8), ncol = 8))
  names(background) <- c("bio12", "bio1", "cover_trees", "soil_phh2o",
                         "elevation", "slope", "roughness", "bio15")
  training <- rbind(
    data.frame(presence = 1L, cell = 1:20, x = 0, y = 0, background[1:20, ]),
    data.frame(presence = 0L, cell = 21:420, x = 0, y = 0, background)
  )
  expect_equal(length(atlas_choose_predictors(training, per_presence = Inf)), 8L)
})

# --- Where the host trees go -------------------------------------------------

test_that("an ectomycorrhizal fungus gets its host trees straight after soil pH", {
  order <- atlas_predictor_priority("ectomycorrhizal")
  expect_equal(order[[1]], "soil_phh2o")
  hosts <- atlas_host_columns()
  expect_equal(order[2:(1 + length(hosts))], hosts)
  expect_true(all(ATLAS_HOST_BANDS %in% hosts))
  expect_gt(match("bio12", order), max(match(hosts, order)))
})

test_that("every other guild, and an unknown one, gets host trees after the climate block", {
  for (guild in c("wood_saprotroph", "litter_saprotroph", "unknown", NA)) {
    order <- atlas_predictor_priority(guild)
    expect_equal(order[[1]], "soil_phh2o", info = guild)
    hosts <- match(atlas_host_columns(), order)
    expect_equal(hosts, seq(min(hosts), length.out = length(hosts)), info = guild)
    expect_equal(order[[min(hosts) - 1L]], "bio4", info = guild)
    expect_equal(order[[max(hosts) + 1L]], "forest_needleleaf", info = guild)
  }
  expect_equal(atlas_predictor_priority(), atlas_predictor_priority("unknown"))
})

test_that("the guild moves only the host trees; the rest keeps its order", {
  for (guild in c("ectomycorrhizal", "unknown")) {
    order <- atlas_predictor_priority(guild)
    expect_equal(setdiff(order, atlas_host_columns()), ATLAS_PREDICTOR_PRIORITY)
    expect_false(anyDuplicated(order) > 0)
  }
  expect_setequal(atlas_predictor_priority("ectomycorrhizal"), atlas_predictor_priority("unknown"))
})

test_that("when the cap binds, an ectomycorrhizal fungus keeps a host and a saprotroph its climate", {
  set.seed(3)
  background <- data.frame(
    soil_phh2o = stats::rnorm(400), bio12 = stats::rnorm(400), bio1 = stats::rnorm(400),
    host_conifer = stats::rnorm(400), host_pinus = stats::rnorm(400),
    cover_trees = stats::rnorm(400)
  )
  training <- rbind(
    data.frame(presence = 1L, cell = 1:12, x = 0, y = 0, background[1:12, ]),
    data.frame(presence = 0L, cell = 13:412, x = 0, y = 0, background)
  )
  # Twelve presences, one predictor per four: three survive, and a third of
  # them may be trees.
  mycorrhizal <- atlas_choose_predictors(training, minimum = 3,
                                         priority = atlas_predictor_priority("ectomycorrhizal"),
                                         host_share = atlas_host_allowance("ectomycorrhizal"))
  saprotroph <- atlas_choose_predictors(training, minimum = 3,
                                        priority = atlas_predictor_priority("wood_saprotroph"))
  expect_equal(mycorrhizal, c("soil_phh2o", "host_conifer", "bio12"))
  expect_equal(saprotroph, c("soil_phh2o", "bio12", "bio1"))
})

# --- How many host trees a model may take ------------------------------------

# Every host band of the layer, independent of one another and of the rest,
# with pine the commonest tree of the region and chestnut absent from it.
host_training <- function(presences, seed = 9) {
  set.seed(seed)
  n <- 600
  climate <- c("soil_phh2o", "bio12", "bio17", "bio15", "bio1", "bio6", "bio4",
               "cover_trees", "soil_clay", "elevation")
  background <- as.data.frame(matrix(stats::rnorm(n * length(climate)), n,
                                     dimnames = list(NULL, climate)))
  for (band in ATLAS_HOST_BANDS) background[[band]] <- stats::runif(n, 0, 0.02)
  background$host_pinus <- stats::runif(n, 0.3, 0.6)
  background$host_quercus <- stats::runif(n, 0.1, 0.3)
  background$host_castanea <- 0
  rbind(
    data.frame(presence = 1L, cell = seq_len(presences), x = 0, y = 0,
               background[seq_len(presences), ]),
    data.frame(presence = 0L, cell = presences + seq_len(n), x = 0, y = 0, background)
  )
}

test_that("a sparse ectomycorrhizal fungus still gets its climate", {
  # Forty sites allow ten predictors. Before the allowance they were soil pH
  # and nine trees, and no moisture or temperature at all.
  kept <- atlas_choose_predictors(
    host_training(40), priority = atlas_predictor_priority("ectomycorrhizal"),
    host_share = atlas_host_allowance("ectomycorrhizal")
  )
  expect_equal(length(kept), 10L)
  expect_equal(sum(atlas_is_host_share(kept)), 3L)
  expect_true(all(c("soil_phh2o", "bio12", "bio1") %in% kept))
})

test_that("the host trees kept are the conifer share and the region's commonest trees", {
  kept <- atlas_choose_predictors(
    host_training(40), priority = atlas_predictor_priority("ectomycorrhizal"),
    host_share = atlas_host_allowance("ectomycorrhizal")
  )
  expect_equal(kept[atlas_is_host_share(kept)],
               c("host_conifer", "host_pinus", "host_quercus"))
  # They keep the hosts' place in the order: straight after soil pH.
  expect_equal(kept[1:2], c("soil_phh2o", "host_conifer"))
})

test_that("the host trees are chosen from the non-detection sites, never the detections", {
  training <- host_training(40)
  # Every detection site is full of chestnut, which grows nowhere else: a
  # choice that looked at the detections would take it.
  training$host_castanea[training$presence == 1L] <- 0.9
  kept <- atlas_choose_predictors(
    training, priority = atlas_predictor_priority("ectomycorrhizal"),
    host_share = atlas_host_allowance("ectomycorrhizal")
  )
  expect_false("host_castanea" %in% kept)
})

test_that("any other guild spends a fifth of its predictors on trees, after its climate", {
  kept <- atlas_choose_predictors(host_training(40), priority = atlas_predictor_priority("unknown"),
                                  host_share = atlas_host_allowance("unknown"))
  expect_equal(sum(atlas_is_host_share(kept)), 2L)
  sparse <- atlas_choose_predictors(host_training(20), priority = atlas_predictor_priority("unknown"),
                                    host_share = atlas_host_allowance("unknown"))
  # Twenty sites allow five predictors, and for these fungi soil pH, moisture
  # and temperature come before the trees: the allowance is a ceiling, not a
  # promise.
  expect_equal(sum(atlas_is_host_share(sparse)), 0L)
  expect_true(all(c("soil_phh2o", "bio12", "bio1") %in% sparse))
  expect_equal(atlas_host_allowance("ectomycorrhizal"), 1 / 3)
  expect_equal(atlas_host_allowance(NA), 1 / 5)
})

test_that("with no cap there is no allowance either", {
  kept <- atlas_choose_predictors(host_training(40), per_presence = Inf,
                                  priority = atlas_predictor_priority("ectomycorrhizal"))
  # Chestnut never varies on the non-detection sites, so it alone is dropped.
  expect_equal(sum(atlas_is_host_share(kept)), length(ATLAS_HOST_BANDS) - 1L)
})

test_that("the flag for ground the inventories missed is not counted as a tree", {
  expect_false(any(atlas_is_host_share(ATLAS_HOST_KNOWN_BANDS)))
  expect_true(all(atlas_is_host_share(c("host_pinus", "host_conifer"))))
  expect_false(atlas_is_host_share("forest_known"))
  expect_false(atlas_is_host_share("cover_trees"))
})

test_that("which source described a cell is never a Maxent predictor", {
  training <- host_training(40)
  training$forest_known <- 1
  training$host_known <- 1
  training$forest_known[1:3] <- 0
  kept <- atlas_choose_predictors(training, per_presence = Inf)
  expect_false(any(ATLAS_SOURCE_FLAGS %in% kept))
  expect_setequal(ATLAS_SOURCE_FLAGS, c("host_known", "forest_known"))
})

# --- The decay and parasite hosts (R/hosts.R, hostsdecay) ----------------------

# The priority before the decay hosts existed, pinned: where their layer is not
# built, every model's order must be exactly what it was.
PRIORITY_BEFORE_DECAY_HOSTS <- list(
  ectomycorrhizal = c(
    "soil_phh2o", "host_known", "host_conifer", "host_pinus", "host_quercus",
    "host_picea", "host_abies", "host_pseudotsuga", "host_tsuga",
    "host_betula", "host_populus", "host_fagus", "host_larix", "host_castanea",
    "host_notholithocarpus", "host_carya", "host_alnus", "host_salix",
    "host_tilia", "host_carpinus", "host_ostrya", "host_arbutus",
    "clim_cmd", "bio12", "clim_ppt_autumn", "bio17", "bio15", "bio14",
    "bio1", "clim_tave_autumn", "clim_ffp", "bio6", "bio5", "bio4",
    "forest_needleleaf", "forest_broadleaf", "forest_mixed", "cover_trees",
    "cover_wetland", "cover_shrubs", "cover_grassland", "soil_soc",
    "soil_nitrogen", "soil_clay", "soil_sand", "soil_cec", "clim_rh",
    "clim_vpd", "clim_aet", "clim_pas", "elevation", "slope", "roughness"
  ),
  unknown = c(
    "soil_phh2o", "clim_cmd", "bio12", "clim_ppt_autumn", "bio17",
    "bio15", "bio14", "bio1", "clim_tave_autumn", "clim_ffp", "bio6",
    "bio5", "bio4", "host_known", "host_conifer", "host_pinus", "host_quercus",
    "host_picea", "host_abies", "host_pseudotsuga", "host_tsuga",
    "host_betula", "host_populus", "host_fagus", "host_larix", "host_castanea",
    "host_notholithocarpus", "host_carya", "host_alnus", "host_salix",
    "host_tilia", "host_carpinus", "host_ostrya", "host_arbutus",
    "forest_needleleaf", "forest_broadleaf", "forest_mixed", "cover_trees",
    "cover_wetland", "cover_shrubs", "cover_grassland", "soil_soc",
    "soil_nitrogen", "soil_clay", "soil_sand", "soil_cec", "clim_rh",
    "clim_vpd", "clim_aet", "clim_pas", "elevation", "slope", "roughness"
  )
)

test_that("the decay-host bands sit in the host block, after the host genera, for both guild kinds", {
  species <- atlas_host_species_bands()
  for (guild in c("ectomycorrhizal", "unknown")) {
    order <- atlas_predictor_priority(guild)
    last_host <- match("host_arbutus", order)
    expect_equal(order[last_host + seq_along(ATLAS_HOST_DECAY_BANDS)],
                 ATLAS_HOST_DECAY_BANDS, info = guild)
    expect_true(all(match(ATLAS_HOST_BANDS, order) < min(match(ATLAS_HOST_DECAY_BANDS, order))))
    # The species come after every genus, so a genus wins a tie with its species.
    last_genus <- max(match(ATLAS_HOST_DECAY_BANDS, order))
    expect_equal(order[last_genus + seq_along(species)], species, info = guild)
    after <- order[[max(match(species, order)) + 1L]]
    expect_equal(after, if (guild == "ectomycorrhizal") "clim_cmd" else "forest_needleleaf",
                 info = guild)
  }
})

test_that("without the decay-host bands, every guild's priority is exactly what it was", {
  for (guild in names(PRIORITY_BEFORE_DECAY_HOSTS)) {
    order <- atlas_predictor_priority(guild)
    expect_equal(order[!order %in% c(ATLAS_HOST_DECAY_BANDS, atlas_host_species_bands(),
                                     unname(ATLAS_CLIMATENA_CORE_VARS))], PRIORITY_BEFORE_DECAY_HOSTS[[guild]],
                 info = guild)
  }
  # What a model is offered depends only on the columns it has: on a table
  # without the decay hosts, pruning keeps what it kept.
  training <- host_training(40)
  for (guild in names(PRIORITY_BEFORE_DECAY_HOSTS)) {
    now <- atlas_choose_predictors(training, priority = atlas_predictor_priority(guild),
                                   host_share = atlas_host_allowance(guild))
    before <- atlas_choose_predictors(training, priority = PRIORITY_BEFORE_DECAY_HOSTS[[guild]],
                                      host_share = atlas_host_allowance(guild))
    expect_equal(now, before, info = guild)
  }
})

test_that("a decay host's share counts against the host allowance like any host", {
  expect_true(all(atlas_is_host_share(ATLAS_HOST_DECAY_BANDS)))
  training <- host_training(40)
  n <- nrow(training)
  set.seed(11)
  for (band in ATLAS_HOST_DECAY_BANDS) training[[band]] <- stats::runif(n, 0, 0.02)
  # Elm is all but absent here, so it is not pinned (see the elm test).
  training$host_ulmus <- stats::runif(n, 0, 0.002)
  # Maple is the region's commonest tree after pine.
  training$host_acer <- stats::runif(n, 0.2, 0.5)
  kept <- atlas_choose_predictors(training, priority = atlas_predictor_priority("ectomycorrhizal"),
                                  host_share = atlas_host_allowance("ectomycorrhizal"))
  # Still three trees in ten predictors, and maple takes oak's place.
  expect_equal(sum(atlas_is_host_share(kept)), 3L)
  expect_equal(kept[atlas_is_host_share(kept)], c("host_conifer", "host_pinus", "host_acer"))
})

test_that("elm keeps a place among the trees wherever it grows, and only there", {
  training <- host_training(40)
  n <- nrow(training)
  set.seed(12)
  for (band in ATLAS_HOST_DECAY_BANDS) training[[band]] <- stats::runif(n, 0, 0.002)
  training$host_acer <- stats::runif(n, 0.2, 0.5)
  # Elm: 3% of the trees on average, far less than pine or maple.
  training$host_ulmus <- stats::runif(n, 0.02, 0.04)
  choose <- function(t) {
    kept <- atlas_choose_predictors(t, priority = atlas_predictor_priority("ectomycorrhizal"),
                                    host_share = atlas_host_allowance("ectomycorrhizal"))
    kept[atlas_is_host_share(kept)]
  }
  expect_equal(choose(training), c("host_conifer", "host_ulmus", "host_pinus"))
  # Where elm is under 1% of the trees it competes on share like any tree.
  training$host_ulmus <- stats::runif(n, 0, 0.004)
  expect_false("host_ulmus" %in% choose(training))
  expect_equal(length(choose(training)), 3L)
})

test_that("tree species compete for the host allowance by share, so a northern and a southern oak region pick different oaks", {
  training <- host_training(40)
  n <- nrow(training)
  set.seed(13)
  for (band in ATLAS_HOST_DECAY_BANDS) training[[band]] <- stats::runif(n, 0, 0.002)
  north <- training
  north$host_quercus_rubra <- stats::runif(n, 0.3, 0.5)
  north$host_quercus_virginiana <- stats::runif(n, 0, 0.001)
  south <- training
  south$host_quercus_rubra <- stats::runif(n, 0, 0.001)
  south$host_quercus_virginiana <- stats::runif(n, 0.3, 0.5)
  pick <- function(t) {
    kept <- atlas_choose_predictors(t, priority = atlas_predictor_priority("ectomycorrhizal"),
                                    host_share = atlas_host_allowance("ectomycorrhizal"))
    kept[atlas_is_host_share(kept)]
  }
  expect_true("host_quercus_rubra" %in% pick(north))
  expect_false("host_quercus_virginiana" %in% pick(north))
  expect_true("host_quercus_virginiana" %in% pick(south))
  expect_false("host_quercus_rubra" %in% pick(south))
})
