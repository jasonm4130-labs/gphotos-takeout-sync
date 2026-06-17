# syntax=docker/dockerfile:1
FROM alpine:3.20

LABEL org.opencontainers.image.title="gphotos-takeout-sync" \
      org.opencontainers.image.description="Mirror a Google Photos library into a self-hosted Immich server via scheduled Google Takeout, rclone, and immich-go." \
      org.opencontainers.image.source="https://github.com/jasonm4130-labs/gphotos-takeout-sync" \
      org.opencontainers.image.licenses="MIT"

# Pinned tool versions (Renovate-tracked via the comment annotations below).
# renovate: datasource=github-releases depName=simulot/immich-go
ARG IMMICH_GO_VERSION=0.31.0
# renovate: datasource=github-releases depName=aptible/supercronic
ARG SUPERCRONIC_VERSION=0.2.46
ARG SUPERCRONIC_SHA256=5adff01c5a797663948e656d2b61d10932369ee437eb5cb54fa872b2960f222b

RUN apk add --no-cache \
      bash \
      ca-certificates \
      coreutils \
      curl \
      jq \
      rclone \
      su-exec \
      tini \
      tzdata

# immich-go — verified against the release's own checksums.txt.
# Download with -O so the local filename matches the name in checksums.txt.
RUN set -eux; \
    cd /tmp; \
    curl -fsSL -O \
      "https://github.com/simulot/immich-go/releases/download/v${IMMICH_GO_VERSION}/immich-go_Linux_x86_64.tar.gz"; \
    curl -fsSL -O \
      "https://github.com/simulot/immich-go/releases/download/v${IMMICH_GO_VERSION}/checksums.txt"; \
    grep "immich-go_Linux_x86_64.tar.gz" checksums.txt | sha256sum -c -; \
    tar -xzf immich-go_Linux_x86_64.tar.gz immich-go; \
    install -m 0755 immich-go /usr/local/bin/immich-go; \
    rm -rf /tmp/*

# supercronic — verified against the binary's SHA-256. The release publishes only
# the binary (no checksums file), so this digest is of the immutable
# v${SUPERCRONIC_VERSION} asset; bump it alongside SUPERCRONIC_VERSION.
RUN set -eux; \
    curl -fsSL -o /usr/local/bin/supercronic \
      "https://github.com/aptible/supercronic/releases/download/v${SUPERCRONIC_VERSION}/supercronic-linux-amd64"; \
    echo "${SUPERCRONIC_SHA256}  /usr/local/bin/supercronic" | sha256sum -c -; \
    chmod 0755 /usr/local/bin/supercronic

COPY --chmod=0755 sync.sh /usr/local/bin/sync.sh
COPY --chmod=0755 entrypoint.sh /usr/local/bin/entrypoint.sh

ENV SYNC_SOURCE=drive \
    IMMICH_SERVER=http://immich-server:2283 \
    RCLONE_REMOTE=gdrive:Takeout \
    CRON_SCHEDULE="0 4 5 */2 *" \
    WORK_DIR=/work \
    LOCAL_PATH=/backfill \
    DRY_RUN=0 \
    PUID=99 \
    PGID=100 \
    UMASK=002

VOLUME ["/work"]

# Liveness: supercronic is the long-running scheduler (cron mode). A metrics-file
# check is unsuitable here — on a bi-monthly schedule the file may not exist for
# weeks after first start, and once written it persists even if supercronic dies.
# Probe the scheduler process instead; run *freshness* is alerted on separately
# from the scraped metrics. (backfill mode is one-shot and ignores HEALTHCHECK.)
HEALTHCHECK --interval=5m --timeout=10s --start-period=30s --retries=3 \
  CMD pidof supercronic >/dev/null 2>&1 || exit 1

ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["cron"]
