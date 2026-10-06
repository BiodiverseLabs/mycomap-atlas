#!/bin/bash
# Record that one of the server's checks failed or passed, where the operator
# will see it.
#
#   alert.sh <check> <message>   # failed
#   alert.sh --ok <check>        # passed
#   alert.sh --summary           # one line per failing check
#
# A failure is written twice:
#   - to the journal as an error tagged atlas-alert
#     (journalctl -t atlas-alert, or journalctl -p err);
#   - to <check>.json in the health directory, which says since when the check
#     has failed, how many times, and why.
# --summary is the login banner (/etc/update-motd.d/90-atlas-health), so a
# failing check greets whoever next signs in to the box.
#
# The health directory is /srv/atlas/data/health: inside the data directory
# the API container mounts at /data, so the API can show it (/data/health).
# ATLAS_HEALTH_DIR moves it, for tests.
#
# The box has no mailer, and this sends nothing anywhere: an alert that must
# reach someone who is not signing in needs a mail relay or a webhook, which
# is a new outside service (README.md, "When something fails").
#
# Called by atlas-alert@.service (OnFailure= of the nightly job and the uptime
# check) and by their ExecStartPost= when they pass.
set -uo pipefail

dir="${ATLAS_HEALTH_DIR:-/srv/atlas/data/health}"
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

usage() { echo "usage: alert.sh <check> <message> | --ok <check> | --summary" >&2; exit 64; }

# The check names a file, so it is a unit-like name and nothing more.
valid_check() { [[ "$1" =~ ^[a-z0-9][a-z0-9-]*$ ]]; }

# A message comes from a unit's own text, but it goes into JSON: no quotes,
# backslashes or control characters get through as such.
json_text() { printf '%s' "$1" | tr -d '\000-\037' | sed 's/\\/\\\\/g; s/"/\\"/g'; }

field() { # file, name: a string or number field of a state file
  sed -n "s/.*\"$2\":\"\{0,1\}\([^\",}]*\).*/\1/p" "$1" 2>/dev/null | head -1
}
message() { # file: the message, which is last and may hold commas
  sed -n 's/.*"message":"\(.*\)"}$/\1/p' "$1" 2>/dev/null | head -1
}

journal() { # priority, text
  logger -t atlas-alert -p "user.$1" -- "$2" 2>/dev/null || echo "atlas-alert: $2" >&2
}

write_state() { # check, json
  mkdir -p "$dir"
  local file="$dir/$1.json" tmp="$dir/.$1.json.tmp"
  printf '%s\n' "$2" > "$tmp"
  chmod 640 "$tmp"
  # The API runs as atlas (uid 10001) and reads this directory.
  if [ "$(id -u)" -eq 0 ] && id atlas >/dev/null 2>&1; then chown atlas:atlas "$dir" "$tmp"; fi
  mv -f "$tmp" "$file"
}

case "${1:-}" in
  --summary)
    [ $# -eq 1 ] || usage
    for file in "$dir"/*.json; do
      [ -f "$file" ] || continue
      [ "$(field "$file" state)" = failed ] || continue
      echo "ATLAS: $(field "$file" check) failing since $(field "$file" since)" \
        "($(field "$file" failures) failures): $(message "$file")"
    done
    exit 0
    ;;
  --ok)
    [ $# -eq 2 ] && valid_check "$2" || usage
    check="$2"; file="$dir/$check.json"; since="$now"
    if [ "$(field "$file" state)" = failed ]; then
      journal notice "$check recovered (failing since $(field "$file" since))"
    elif [ -f "$file" ]; then
      since="$(field "$file" since)"
    fi
    write_state "$check" "{\"check\":\"$check\",\"state\":\"ok\",\"since\":\"$since\",\"checked\":\"$now\"}"
    ;;
  -*|"") usage ;;
  *)
    [ $# -eq 2 ] && valid_check "$1" || usage
    check="$1"; message="$(json_text "$2")"; file="$dir/$check.json"
    since="$now"; failures=1
    if [ "$(field "$file" state)" = failed ]; then
      since="$(field "$file" since)"
      failures=$(( $(field "$file" failures) + 1 ))
    fi
    journal err "$check failed: $2"
    write_state "$check" "{\"check\":\"$check\",\"state\":\"failed\",\"since\":\"$since\",\"checked\":\"$now\",\"failures\":$failures,\"message\":\"$message\"}"
    ;;
esac
