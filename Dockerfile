# The image that computes and publishes Atlas. Iterate natively on a laptop,
# but a release that reaches mycomap.org is built here, so a Windows-versus-
# Linux difference can never silently change a published map.
#
# Everything that decides the output is pinned, so the same commit builds the
# same image:
#   - the base image by digest, because rocker rebuilds its version tags;
#   - R packages to a dated snapshot of Posit Package Manager, which also
#     serves them as Linux binaries, so the build does not compile them;
#   - the code, by the commit passed in as ATLAS_COMMIT, which every release
#     records.
#
# To move to newer packages, change CRAN_SNAPSHOT and rebuild; Dependabot
# proposes new base-image digests.
#
# The web app is built here too, in its own stage, so one image is one commit
# of both the API and the app, and the server never builds anything.

# node:22-bookworm-slim (Node 22.23.3), with the pnpm version CI uses.
FROM node:22-bookworm-slim@sha256:43ac6c60b8f89723f746e8a92ce91abd5017e627ce1ddfe4238355d3a30b772c AS web
RUN corepack enable && corepack prepare pnpm@10.26.1 --activate
WORKDIR /src/web
COPY web/package.json web/pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY web ./
# The app imports the API description and the sources list from inst/api.
COPY inst/api /src/inst/api
RUN pnpm build

# rocker/geospatial:4.6.1
FROM rocker/geospatial:4.6.1@sha256:e67737e30c66e6d2237570cd647e2bfec59315e533713473ab2ba391992bfa2c

ARG CRAN_SNAPSHOT=2026-09-28
# The same day in Ubuntu's snapshot of its archive, for the few system
# packages the image adds: pinned by date like the R packages.
ARG UBUNTU_SNAPSHOT=20260928T000000Z

# ssh, for the nightly pull through mycomap.org's read-only SQL route.
RUN apt-get update --snapshot "${UBUNTU_SNAPSHOT}" \
 && apt-get install -y --no-install-recommends --snapshot "${UBUNTU_SNAPSHOT}" openssh-client \
 && rm -rf /var/lib/apt/lists/*

# Only what Atlas uses. terra and sf come with the base image (blockCV needs
# sf); paws.compute
# and curl are the nightly job's (EC2, and checking the workers' image).
RUN . /etc/os-release \
 && install2.r --error --skipinstalled --ncpus -1 \
      -r "https://p3m.dev/cran/__linux__/${VERSION_CODENAME}/${CRAN_SNAPSHOT}" \
      digest jsonlite plumber maxnet glmnet xgboost ranger blockCV paws.storage paws.compute curl openssl testthat targets \
 && rm -rf /tmp/downloaded_packages

WORKDIR /atlas
COPY DESCRIPTION NAMESPACE LICENSE.md _targets.R ./
COPY R ./R
COPY inst ./inst
COPY tests ./tests
# The built app, for the web server to serve (deploy/lightsail copies it out).
# Outside /atlas: that is the package's source tree, whose tests read web/.
COPY --from=web /src/web/dist /opt/atlas-web

# Install, then run the whole suite inside the image: an image whose tests
# fail is never built.
RUN R CMD INSTALL --no-test-load . \
 && Rscript -e "testthat::test_local(stop_on_failure = TRUE)"

# The commit this image was built from; releases record it.
ARG ATLAS_COMMIT=unknown
ENV ATLAS_COMMIT=${ATLAS_COMMIT} \
    ATLAS_ROOT=/atlas \
    ATLAS_DATA_DIR=/data

# Compute as an ordinary user, not root.
RUN useradd --create-home --uid 10001 atlas \
 && mkdir -p /data \
 && chown atlas:atlas /data
USER atlas
VOLUME ["/data"]

ENTRYPOINT ["Rscript", "/atlas/inst/run.R"]
CMD ["help"]
