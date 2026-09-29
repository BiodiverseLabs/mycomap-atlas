#!/bin/bash
# The nightly job, run by atlas-nightly.service (as root, which runs Docker).
#
# In the image of the deployed commit: pull the validated records from
# mycomap.org, plan what changed, fit it on EC2 and publish the release
# (`atlas nightly`); then, whatever that did, bring this server up to the
# current release without its rasters and restart the API on it.
#
# Exits non-zero if either step failed, so the unit shows as failed.
set -uo pipefail
: "${ATLAS_IMAGE:?ATLAS_IMAGE is not set: deploy a commit first}"

run() {
  local name="$1"; shift
  docker run --rm --name "$name" --network host --memory 1g \
    --env-file /etc/atlas/atlas.env \
    -v /srv/atlas/data:/data \
    -v /home/atlas/.ssh:/home/atlas/.ssh:ro \
    "$ATLAS_IMAGE" "$@"
}

status=0
run atlas-nightly nightly || status=$?
if run atlas-pull pull-release --no-rasters; then
  systemctl restart atlas-api
else
  status=1
fi
exit "$status"
