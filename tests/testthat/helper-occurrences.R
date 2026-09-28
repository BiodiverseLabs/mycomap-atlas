# A small eligible pull. The first two records sit about 20 m apart, well
# inside one locality cell and away from a cell boundary; the third is several
# kilometres away, in another cell.
fake_occurrences <- function() {
  data.frame(
    id = c("1", "2", "3"),
    observation_id = c("a", "b", "c"),
    source = "iNaturalist",
    scientific_name = "Amanita muscaria",
    genus = "Amanita",
    observed_on = c("2025-10-01", "2025-10-02", "2025-10-03"),
    latitude = c("45.1030", "45.1032", "45.1500"),
    longitude = c("-122.5050", "-122.5052", "-122.5500"),
    state = "Oregon",
    country = "US",
    sequence_id = c("11", "12", "13"),
    updated_at = c("2026-01-01", "2026-01-02", "2026-01-03"),
    stringsAsFactors = FALSE
  )
}
