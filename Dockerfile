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

# rocker/geospatial:4.6.1
FROM rocker/geospatial:4.6.1@sha256:e67737e30c66e6d2237570cd647e2bfec59315e533713473ab2ba391992bfa2c

ARG CRAN_SNAPSHOT=2026-09-28

# Only what Atlas uses. terra and sf come with the base image.
RUN . /etc/os-release \
 && install2.r --error --skipinstalled --ncpus -1 \
      -r "https://p3m.dev/cran/__linux__/${VERSION_CODENAME}/${CRAN_SNAPSHOT}" \
      digest jsonlite plumber maxnet xgboost ranger paws.storage testthat targets \
 && rm -rf /tmp/downloaded_packages

WORKDIR /atlas
COPY DESCRIPTION NAMESPACE LICENSE.md _targets.R ./
COPY R ./R
COPY inst ./inst
COPY tests ./tests

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
