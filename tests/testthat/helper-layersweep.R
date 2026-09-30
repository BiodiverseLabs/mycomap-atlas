# The layer sweep's synthetic landscape, for the sweep and importance tests.

# In the synthetic landscape v1 carries the signal and v2 is noise; v3 is a
# second noise layer, because maxnet cannot fit a single predictor. Treat the
# noise as the baseline and the signal as a new layer: adding it must help.
signal_setup <- function() {
  world <- synthetic_landscape()
  set.seed(11)
  v3 <- world$stack[[2]]
  terra::values(v3) <- stats::runif(terra::ncell(v3))
  names(v3) <- "v3"
  world$stack <- c(world$stack, v3)
  bands <- list(noise = c("v2", "v3"), signal = "v1")
  arms <- atlas_layer_sweep_arms(list(signal = "signal"), base = "noise")
  list(world = world, bands = bands, arms = arms)
}
