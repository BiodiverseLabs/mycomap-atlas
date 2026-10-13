# The Atlas paper

A living draft of the peer-reviewed paper on MycoMap Atlas, improved over the
coming months until it is submitted. The draft is [`draft.md`](draft.md).

## Rules

- **One editor.** The paper coordinator edits `draft.md`. Other work reaches
  the draft as results: an analysis, a figure, a table, with the release and
  commit it came from.
- **Numbers come from the frozen release.** Every number in Results is
  computed from one named release (its id, Zenodo DOI and code commit, in the
  draft's front matter), never from whatever release is live. A number from
  an earlier study is tagged `[pre-freeze]` until it is rerun on the frozen
  release; decisions taken from such a number are provisional until then.
- **Pending work is marked.** `[PENDING E<n>]` names the analysis in
  Appendix A that will supply a number or figure. `[CHECK]` marks a fact or
  reference still to verify against its source.
- **This repository is public.** No coordinates, record lists, people's
  addresses, machine names, account ids or internal session names in these
  files. Name the work by its role ("the rebuild"), not by who ran it.
- **Changes are logged** at the end of `draft.md`, newest first.
