#!/bin/bash
# Is the API answering? Run every 5 minutes by atlas-uptime.timer.
#
# Passes when GET /api/status answers 2xx. Fails (exit 1, so the unit fails
# and atlas-alert@ records it) only when it has not in 5 tries 30 s apart:
# a deploy or the nightly job restarts the API, and deploy.sh itself allows
# the API 2 minutes to come back, so a restart is not an outage.
#
# ATLAS_STATUS_URL, ATLAS_UPTIME_TRIES and ATLAS_UPTIME_WAIT change the
# address, tries and seconds between them (tests).
set -uo pipefail

url="${ATLAS_STATUS_URL:-http://127.0.0.1:5100/api/status}"
tries="${ATLAS_UPTIME_TRIES:-5}"
wait="${ATLAS_UPTIME_WAIT:-30}"

code=000
for i in $(seq 1 "$tries"); do
  code="$(curl -s -o /dev/null -m 10 -w '%{http_code}' "$url")" || true
  case "$code" in 2??) exit 0 ;; esac
  [ "$i" -lt "$tries" ] && sleep "$wait"
done
if [ "$code" = 000 ]; then
  echo "GET $url: no answer in $tries tries" >&2
else
  echo "GET $url: HTTP $code in $tries tries" >&2
fi
exit 1
