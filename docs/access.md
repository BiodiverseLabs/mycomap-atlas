# Access, sign-in and tokens

Back to the [README](../README.md). The routes themselves are listed on the
[Developers page](https://atlas.mycomap.org/developers) and in
[`inst/api/openapi.json`](../inst/api/openapi.json).

Reads are open: every page, map image, score and count is served to anyone.
Two things need the caller to be known, as a person signed in on the site or
a script with a token: **downloading a model's GeoTIFF**
(`/api/taxa/<name>/raster.tif`) and a **higher rate limit**.

Every caller is rate limited: anonymous callers per address, signed-in people
per person, tokens per token. Tokens identify a caller; they do not protect
the server, since a flood arrives before any key can be checked. Caching does
that work: responses carry `Cache-Control`, and a map requested with its
version (`?v=`) never changes at that address, so a CDN in front of the API
answers repeat requests without reaching it. `/api/me` and downloads are
`private, no-store`.

**Signing in** uses mycomap.org's sign-in bridge; Atlas has no accounts. The
browser goes to `/auth/dev-bridge/start`, on to mycomap.org, and back to
`/auth/dev-bridge/callback` with a token .org signed with its Ed25519 private
key. Atlas holds only the public key, so it can check a token but never make
one. The token must be fresh (60 s), for this site's origin and for the nonce
this browser was given; then Atlas sets its own cookie, `__Host-atlas_session`
(HMAC-signed, 14 days, HttpOnly, Secure, SameSite=Lax), and nothing is shared
with mycomap.org's cookies. `POST /auth/logout` from the site's own pages
clears it. The code is in `R/auth.R`.

**Tokens** are issued by mycomap.org, per account, and approved there by an
admin (`https://mycomap.org/atlas-tokens`). A script sends
`Authorization: Bearer <token>`. Atlas asks .org's introspection route whether
a token is live and caches the answer for five minutes (a minute for a
rejection), keyed by a hash of the token. A token .org rejects gets `401` with
the reason. If .org cannot be reached the caller is treated as anonymous for
that request (read at the anonymous rate, no downloads), and nothing is
cached. The code is in `R/access.R`.

**Downloads** (`R/download.R`): the public server keeps only a release's PNGs
and JSON, so a raster is looked up in the current release's manifest and
answered with a `302` to a presigned S3 link that works for five minutes. A
file on the machine, or a store that is a local folder, is sent directly.

**Addresses.** The API trusts `X-Forwarded-For` only when the request comes
from this machine (nginx on the same host), and only its right-most entry, the
one nginx wrote. Behind Cloudflare, nginx has to restore the visitor's address
first (`set_real_ip_from` for Cloudflare's ranges and
`real_ip_header CF-Connecting-IP`), or everyone arriving through one
Cloudflare edge shares an allowance.

The settings are environment variables, so no secret enters the repository.
Anything missing is named in a `[CONFIG-ALERT]` line when the API starts, and
that feature stays off rather than the API failing:

| Variable | Default | Meaning |
|---|---|---|
| `ATLAS_PUBLIC_ORIGIN` | unset | This site's origin, e.g. `https://atlas.mycomap.org`. Sign-in tokens must name it exactly, and sign-out must come from it. |
| `ATLAS_SIGNIN_ISSUER` | `https://mycomap.org` | Who signs people in, and whose introspection route checks tokens. |
| `ATLAS_BRIDGE_PUBLIC_KEY` | unset | .org's bridge public key (Ed25519, PEM; literal `
` allowed). |
| `ATLAS_SESSION_SECRET` | unset | At least 32 characters, for signing the session cookie. Unset, sign-in answers 503 and nobody is signed in. Changing it signs everyone out. |
| `ATLAS_INTROSPECTION_SECRET` | unset | The shared secret .org gave Atlas for its introspection route. Unset, tokens are ignored. |
| `ATLAS_KEY_INTROSPECT_URL` | issuer's `/api/service-keys/introspect` | Only to point at a stand-in. |
| `ATLAS_STORE` | unset | The release store; downloads not on disk are looked up there. |
| `ATLAS_RATE_ANONYMOUS` / `_STANDARD` / `_BULK` | 300 / 1,200 / 6,000 | Requests per minute. Signed-in people get the standard rate. The spec's `x-rate-limits` must match the defaults (a test checks). |
| `ATLAS_REQUIRE_TOKEN` | off | `true` makes every route need a token or a session. |
| `ATLAS_ALLOWED_ORIGINS` | the dev app | `*` on the public server, so any site can call the API from a browser. No response allows credentials, so another site's page never uses a visitor's session. |
