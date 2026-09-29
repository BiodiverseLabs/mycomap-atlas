# The server's settings template, deploy/lightsail/atlas.env.example, is what
# the operator copies to /etc/atlas/atlas.env. A setting the code requires but
# the template forgets is found at the first nightly run; this finds it first.

env_template <- function() {
  path <- testthat::test_path("..", "..", "deploy", "lightsail", "atlas.env.example")
  skip_if_not(file.exists(path), "deploy/ is not in the image")
  lines <- readLines(path, warn = FALSE)
  lines <- grep("^[A-Z][A-Z0-9_]*=", lines, value = TRUE)
  stats::setNames(sub("^[^=]*=", "", lines), sub("=.*$", "", lines))
}

test_that("the server's settings template names every setting the server needs", {
  settings <- env_template()
  needed <- c(
    ATLAS_EC2_REQUIRED,
    "AWS_REGION", "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY",
    "ATLAS_PUBLIC_ORIGIN", "ATLAS_ALLOWED_ORIGINS", "ATLAS_BRIDGE_PUBLIC_KEY",
    "ATLAS_SESSION_SECRET", "ATLAS_INTROSPECTION_SECRET"
  )
  expect_equal(setdiff(needed, names(settings)), character(0))
  expect_false(anyDuplicated(names(settings)) > 0)
})

test_that("the settings template carries no secret, and no quotes docker would keep", {
  settings <- env_template()
  for (secret in c("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "ATLAS_SESSION_SECRET",
                   "ATLAS_INTROSPECTION_SECRET")) {
    expect_equal(unname(settings[[secret]]), "", info = secret)
  }
  # docker run --env-file keeps quotes as part of the value.
  expect_false(any(grepl("^[\"']", settings)))
})
