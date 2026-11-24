# A small pull for the QA tests (test-qa.R, test-qa-baseline.R): n_inat iNaturalist
# and n_mo Mushroom Observer records of two names.
qa_pull <- function(n_inat = 100, n_mo = 50) {
  data.frame(
    id = as.character(seq_len(n_inat + n_mo)),
    source = c(rep("iNaturalist", n_inat), rep("MO Observations", n_mo)),
    observation_id = as.character(c(seq_len(n_inat), seq_len(n_mo) + 5000)),
    scientific_name = rep(c("Amanita muscaria", "Russula emetica"), length.out = n_inat + n_mo),
    stringsAsFactors = FALSE
  )
}
