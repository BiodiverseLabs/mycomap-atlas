#!/bin/bash
# Checks the server configuration in deploy/lightsail without a server.
#
#   bash deploy/lightsail/test-box-config.sh                    # needs Docker
#   bash deploy/lightsail/test-box-config.sh --check-cloudflare # needs the internet
#
# The scripts: they parse, and refuse bad arguments before touching anything.
# nginx: Ubuntu 24.04's own nginx (the server's) loads the site, and with a
# stand-in API that echoes what it receives:
#   - /api/ and /auth/ reach the API, never the app's fallback page;
#   - a client's own X-Forwarded-For never reaches the API;
#   - an API error is the API's answer, not nginx's;
#   - app routes fall back to index.html, missing assets do not;
#   - plain HTTP is redirected.
# --check-cloudflare compares cloudflare-real-ip.conf with Cloudflare's list.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
failures=0
pass() { echo "ok   $*"; }
fail() { echo "FAIL $*"; failures=$((failures + 1)); }

if [ "${1:-}" = "--check-cloudflare" ]; then
  live="$(curl -fsS https://www.cloudflare.com/ips-v4; echo; curl -fsS https://www.cloudflare.com/ips-v6)"
  ours="$(sed -n 's/^set_real_ip_from \(.*\);$/\1/p' "$here/nginx/cloudflare-real-ip.conf")"
  if diff <(grep . <<<"$live" | sort) <(sort <<<"$ours") >/dev/null; then
    pass "cloudflare-real-ip.conf matches Cloudflare's list"
  else
    fail "cloudflare-real-ip.conf differs from Cloudflare's list:"
    diff <(grep . <<<"$live" | sort) <(sort <<<"$ours")
  fi
  exit "$failures"
fi

echo "== scripts"
for script in setup-box.sh deploy.sh nightly.sh; do
  if bash -n "$here/$script"; then pass "$script parses"; else fail "$script does not parse"; fi
done
expect_exit() { # name, expected status, command...
  local name="$1" want="$2"; shift 2
  "$@" >/dev/null 2>&1; local got=$?
  if [ "$got" = "$want" ]; then pass "$name"; else fail "$name: exit $got, expected $want"; fi
}
expect_exit "deploy.sh refuses no commit"          64 bash "$here/deploy.sh"
expect_exit "deploy.sh refuses a short commit"     64 bash "$here/deploy.sh" 7a2bc18
expect_exit "deploy.sh refuses a tag"              64 bash "$here/deploy.sh" latest
expect_exit "setup-box.sh refuses an unknown flag" 64 bash "$here/setup-box.sh" --sqlhost=x
expect_exit "nightly.sh refuses with no image"     1  env -u ATLAS_IMAGE bash "$here/nightly.sh"

echo "== systemd units"
grep -q 'ExecStart=/usr/bin/flock --nonblock /run/atlas-nightly.lock /usr/local/lib/atlas/nightly.sh' "$here/systemd/atlas-nightly.service" \
  && grep -q 'install -m 755 "$here/nightly.sh" /usr/local/lib/atlas/nightly.sh' "$here/setup-box.sh" \
  && pass "the nightly unit runs the script setup installs, one run at a time" \
  || fail "the nightly unit and setup-box.sh disagree about nightly.sh"
grep -q -- '--network host' "$here/systemd/atlas-api.service" && grep -q 'api --port=5100' "$here/systemd/atlas-api.service" \
  && pass "the API shares the host network on port 5100 (nginx reaches it from 127.0.0.1)" \
  || fail "atlas-api.service must run the API with --network host on 5100"

echo "== nginx (Ubuntu 24.04's)"
name="atlas-box-test-$$"
docker run -d --rm --name "$name" ubuntu:24.04 sleep 600 >/dev/null || { fail "could not start a container"; exit 1; }
trap 'docker rm -f "$name" >/dev/null 2>&1 || true' EXIT
docker exec "$name" bash -c 'apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx openssl curl python3 >/dev/null 2>&1' \
  || { fail "could not install nginx in the container"; exit 1; }
# Through stdin rather than docker cp, whose paths Git Bash on Windows mangles.
put() { docker exec -i "$name" sh -c "cat > '$2'" < "$1"; }
put "$here/nginx/cloudflare-real-ip.conf" /etc/nginx/snippets/cloudflare-real-ip.conf
put "$here/nginx/atlas-proxy.conf" /etc/nginx/snippets/atlas-proxy.conf
put "$here/nginx/atlas.conf" /etc/nginx/sites-enabled/atlas
docker exec -i "$name" bash -s <<'SETUP'
set -e
rm -f /etc/nginx/sites-enabled/default
mkdir -p /etc/ssl/atlas /srv/atlas/web/assets
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=atlas.mycomap.org \
  -keyout /etc/ssl/atlas/origin.key -out /etc/ssl/atlas/origin.pem 2>/dev/null
echo '<html>the app</html>' > /srv/atlas/web/index.html
echo 'console.log(1)' > /srv/atlas/web/assets/app-abc123.js
cat > /tmp/api.py <<'PY'
import http.server, json
class H(http.server.BaseHTTPRequestHandler):
    def reply(self):
        status = 502 if self.path.startswith("/api/broken") else 200
        body = json.dumps({"path": self.path, "xff": self.headers.get("X-Forwarded-For"),
                           "proto": self.headers.get("X-Forwarded-Proto")}).encode()
        self.send_response(status); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
    do_GET = do_POST = reply
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", 5100), H).serve_forever()
PY
nohup python3 /tmp/api.py >/dev/null 2>&1 &
SETUP
if ! docker exec "$name" nginx -T 2>/dev/null | grep -q 'server_name atlas.mycomap.org'; then
  fail "the Atlas site is not in nginx's configuration"; exit 1
fi
if docker exec "$name" nginx -t >/dev/null 2>&1; then pass "nginx -t accepts the site"; else
  fail "nginx -t: $(docker exec "$name" nginx -t 2>&1 | tail -2)"; exit 1; fi
docker exec "$name" nginx
sleep 1

get() { docker exec "$name" curl -sk --resolve atlas.mycomap.org:443:127.0.0.1 "$@"; }
body="$(get -H 'X-Forwarded-For: 6.6.6.6' https://atlas.mycomap.org/api/status)"
grep -q '"path": "/api/status"' <<<"$body" && pass "/api/ reaches the API" || fail "/api/status: $body"
grep -q '6.6.6.6' <<<"$body" && fail "a client's X-Forwarded-For reached the API: $body" \
  || pass "a client's X-Forwarded-For never reaches the API"
grep -q '"proto": "https"' <<<"$body" && pass "the API is told the visit was https" || fail "X-Forwarded-Proto: $body"
body="$(get https://atlas.mycomap.org/auth/dev-bridge/start)"
grep -q '"path": "/auth/dev-bridge/start"' <<<"$body" && pass "/auth/ reaches the API" || fail "/auth/: $body"
code="$(get -o /dev/null -w '%{http_code}' https://atlas.mycomap.org/api/broken)"
body="$(get https://atlas.mycomap.org/api/broken)"
[ "$code" = 502 ] && grep -q '/api/broken' <<<"$body" && pass "an API error is the API's own answer" \
  || fail "/api/broken: $code $body"
body="$(get https://atlas.mycomap.org/taxa/Pluteus%20petasatus)"
grep -q 'the app' <<<"$body" && pass "app routes fall back to index.html" || fail "app route: $body"
code="$(get -o /dev/null -w '%{http_code}' https://atlas.mycomap.org/assets/missing-000.js)"
[ "$code" = 404 ] && pass "a missing asset is a 404, not the app" || fail "missing asset: $code"
cache="$(get -o /dev/null -D - https://atlas.mycomap.org/assets/app-abc123.js | grep -i '^cache-control')"
grep -qi immutable <<<"$cache" && pass "hashed assets are cached for good" || fail "asset caching: $cache"
code="$(docker exec "$name" curl -s -o /dev/null -w '%{http_code}' -H 'Host: atlas.mycomap.org' http://127.0.0.1/)"
[ "$code" = 301 ] && pass "plain HTTP is redirected" || fail "http: $code"

[ "$failures" -eq 0 ] && echo "PASS" || { echo "$failures failure(s)"; exit 1; }
