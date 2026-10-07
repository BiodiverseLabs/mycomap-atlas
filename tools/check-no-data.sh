#!/usr/bin/env bash
# Refuse anything that could carry collection coordinates into the repository.
#
# data/ holds exact coordinates of DNA-validated collections. Nothing under it,
# and no raster or table of records, belongs in git — not in a commit, not as a
# test fixture, not "just this once". Tests use the synthetic records in
# tests/testthat/helper-occurrences.R instead.
#
#   bash tools/check-no-data.sh              # a pull request's added files, or
#                                            # every tracked file otherwise
#   bash tools/check-no-data.sh <path>...    # just these paths
#   bash tools/check-no-data.sh --self-test  # check the checker
set -euo pipefail

FORBIDDEN_PATH='^data/|(^|/)_targets/'
FORBIDDEN_EXT='\.(tif|tiff|gpkg|shp|rds|duckdb|sqlite|parquet|tsv|csv)(\.gz)?$'
MAX_BYTES=2000000

# Published reference tables that hold no records and no places, named one by
# one. A table here is still refused if its header names a coordinate column.
REFERENCE_TABLES=(
  "inst/extdata/fia-tree-species.csv" # FIA REF_SPECIES codes and names (public domain)
)
COORDINATE_COLUMN='(^|,)"?(lat|lon|lng|latitude|longitude|x|y|decimallatitude|decimallongitude)"?(,|$)'

is_reference_table() {
  local table
  for table in "${REFERENCE_TABLES[@]}"; do
    [ "$1" = "$table" ] && return 0
  done
  return 1
}

# Prints why a path is refused and returns 0; returns 1 when the path is fine.
why_forbidden() {
  local path="$1"
  if printf '%s' "$path" | grep -Eq "$FORBIDDEN_PATH"; then
    echo "lives under data/ or _targets/"
    return 0
  fi
  if is_reference_table "$path"; then
    if [ -f "$path" ] && head -n 1 "$path" | tr -d '\r' | grep -Eiq "$COORDINATE_COLUMN"; then
      echo "is a listed reference table, but its header names a coordinate column"
      return 0
    fi
    return 1
  fi
  if printf '%s' "$path" | grep -Eiq "$FORBIDDEN_EXT"; then
    echo "has a data-file extension"
    return 0
  fi
  return 1
}

check_paths() {
  local failed=0 path reason size
  for path in "$@"; do
    [ -n "$path" ] || continue
    if reason=$(why_forbidden "$path"); then
      echo "REFUSED  $path — $reason" >&2
      failed=1
      continue
    fi
    if [ -f "$path" ]; then
      size=$(wc -c <"$path")
      if [ "$size" -gt "$MAX_BYTES" ]; then
        echo "REFUSED  $path — $size bytes, over the $MAX_BYTES limit" >&2
        failed=1
      fi
    fi
  done
  return "$failed"
}

self_test() {
  local failures=0
  expect_refused() {
    if why_forbidden "$1" >/dev/null; then
      echo "  ok      refuses $1"
    else
      echo "  FAILED  allowed $1" >&2
      failures=1
    fi
  }
  expect_allowed() {
    if why_forbidden "$1" >/dev/null; then
      echo "  FAILED  refused $1" >&2
      failures=1
    else
      echo "  ok      allows  $1"
    fi
  }

  echo "self-test:"
  expect_refused "data/occurrences/occurrences-20260928T203955Z.tsv.gz"
  expect_refused "data/layers/draft/bioclim.tif"
  expect_refused "_targets/objects/occurrences"
  expect_refused "notes/records.csv"
  expect_refused "somewhere/deep/points.gpkg"
  expect_allowed "R/layers.R"
  expect_allowed "tests/testthat/helper-occurrences.R"
  expect_allowed "web/pnpm-lock.yaml"
  expect_allowed "README.md"
  # A listed reference table is allowed by its exact path, nothing near it.
  expect_allowed "inst/extdata/fia-tree-species.csv"
  expect_refused "inst/extdata/other.csv"
  expect_refused "inst/extdata/fia-tree-species.csv.gz"
  expect_refused "data/inst/extdata/fia-tree-species.csv"

  # Even a listed table is refused once its header names a coordinate column.
  local scratch
  scratch=$(mktemp -d)
  mkdir -p "$scratch/inst/extdata"
  printf 'spcd,genus,latitude,longitude\n1,Abies,40.1,-96.2\n' >"$scratch/inst/extdata/fia-tree-species.csv"
  if (cd "$scratch" && why_forbidden "inst/extdata/fia-tree-species.csv" >/dev/null); then
    echo "  ok      refuses a listed table with coordinate columns"
  else
    echo "  FAILED  allowed a listed table with coordinate columns" >&2
    failures=1
  fi
  rm -rf "$scratch"

  if [ "$failures" -ne 0 ]; then
    echo "self-test failed" >&2
    return 1
  fi
  echo "self-test passed"
}

main() {
  if [ "${1:-}" = "--self-test" ]; then
    self_test
    return
  fi

  if [ "$#" -gt 0 ]; then
    check_paths "$@"
    return
  fi

  local files
  if [ -n "${GITHUB_BASE_REF:-}" ]; then
    git fetch --no-tags --depth=1 origin "$GITHUB_BASE_REF" >/dev/null 2>&1 || true
    files=$(git diff --name-only --diff-filter=AM "origin/$GITHUB_BASE_REF...HEAD")
  else
    files=$(git ls-files)
  fi

  if [ -z "$files" ]; then
    echo "nothing to check"
    return
  fi

  # shellcheck disable=SC2086
  if check_paths $files; then
    echo "checked $(printf '%s\n' "$files" | wc -l | tr -d ' ') path(s); no data files"
  else
    echo "" >&2
    echo "These files can carry collection coordinates. Keep them under data/," >&2
    echo "which is git-ignored. See CONTRIBUTING.md." >&2
    return 1
  fi
}

main "$@"
