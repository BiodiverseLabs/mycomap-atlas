# Only this image publishes a release. Iterate natively on a laptop, but any
# map that reaches mycomap.org is produced here, so a Windows-versus-Linux
# difference can never silently change a published map.
#
# Pin this tag to a specific R version before the first release.
FROM rocker/geospatial:latest

RUN R -e "install.packages(c('digest','jsonlite','plumber','targets','tarchetypes','maxnet','ENMeval','blockCV','ecospat','xgboost','testthat'), repos = 'https://cloud.r-project.org')"

WORKDIR /atlas
COPY DESCRIPTION NAMESPACE LICENSE _targets.R ./
COPY R ./R
COPY inst ./inst
COPY tests ./tests

RUN R CMD INSTALL . && Rscript -e "testthat::test_local()"

ENV ATLAS_ROOT=/atlas
ENV ATLAS_DATA_DIR=/data
VOLUME ["/data"]

ENTRYPOINT ["Rscript", "/atlas/inst/run.R"]
CMD ["help"]
