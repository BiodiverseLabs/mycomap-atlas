# How the sources stand now, as atlas_cells_now_status answers: every record
# of the pull answered, nothing hidden, unless told otherwise.
planted_status <- function(pull, inat_hidden = character(), inat_unanswered = character(),
                           mo_not_shown = character(), mo_unanswered = character(), deleted = character(),
                           checked_at = "2026-11-08T10:00:00Z") {
  inat <- unique(pull$observation_id[pull$source == ATLAS_INAT_SOURCE])
  inat <- setdiff(inat, inat_unanswered)
  mo <- unique(pull$observation_id[pull$source == ATLAS_MO_SOURCE])
  mo <- setdiff(mo, mo_unanswered)
  list(
    inat = data.frame(number = inat, hidden = ifelse(inat %in% inat_hidden, "t", "f"), stringsAsFactors = FALSE),
    mo = data.frame(number = mo, shown = ifelse(mo %in% mo_not_shown, "f", "t"), stringsAsFactors = FALSE),
    deleted = deleted,
    checked_at = checked_at
  )
}

# Cells made now for this data directory's current release, as cells-now
# leaves them, with nothing more left out than the release's own list.
planted_cells_now <- function(store, grid = "draft", status = NULL) {
  manifest <- atlas_current_release(store, grid)
  pull <- atlas_read_occurrences()
  listed <- atlas_read_privacy() %||% character()
  result <- atlas_cells_now(pull, listed, atlas_public_cells_path(), status %||% planted_status(pull),
                            release = manifest$id)
  dir <- tempfile("cells-now-")
  atlas_write_cells_now(result, dir)
  dir
}

# The guards stop a status answer that reads as too much left out; the
# planted pull is tiny, so for the cases below they are lifted.
without_guards <- function(code) {
  old <- c(ATLAS_CELLS_NOW_MAX_UNANSWERED, ATLAS_CELLS_NOW_MAX_BEYOND)
  ns <- asNamespace("mycomapatlas")
  unlockBinding("ATLAS_CELLS_NOW_MAX_UNANSWERED", ns)
  unlockBinding("ATLAS_CELLS_NOW_MAX_BEYOND", ns)
  assign("ATLAS_CELLS_NOW_MAX_UNANSWERED", 1, envir = ns)
  assign("ATLAS_CELLS_NOW_MAX_BEYOND", 1, envir = ns)
  on.exit({
    assign("ATLAS_CELLS_NOW_MAX_UNANSWERED", old[[1]], envir = ns)
    assign("ATLAS_CELLS_NOW_MAX_BEYOND", old[[2]], envir = ns)
    lockBinding("ATLAS_CELLS_NOW_MAX_UNANSWERED", ns)
    lockBinding("ATLAS_CELLS_NOW_MAX_BEYOND", ns)
  }, add = TRUE)
  force(code)
}
