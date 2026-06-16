# syntax=docker/dockerfile:1
FROM alpine:3.20

# Pinned tool versions (Renovate-tracked via the comment annotations below).
# renovate: datasource=github-releases depName=simulot/immich-go
ARG IMMICH_GO_VERSION=0.31.0
# renovate: datasource=github-releases depName=aptible/supercronic
ARG SUPERCRONIC_VERSION=0.2.46
ARG SUPERCRONIC_SHA1=5bcefed628e32adc08e32634db2d10e9230dbca0

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

# supercronic — verified against the published SHA1
RUN set -eux; \
    curl -fsSL -o /usr/local/bin/supercronic \
      "https://github.com/aptible/supercronic/releases/download/v${SUPERCRONIC_VERSION}/supercronic-linux-amd64"; \
    echo "${SUPERCRONIC_SHA1}  /usr/local/bin/supercronic" | sha1sum -c -; \
    chmod 0755 /usr/local/bin/supercronic

COPY --chmod=0755 sync.sh /usr/local/bin/sync.sh
COPY --chmod=0755 entrypoint.sh /usr/local/bin/entrypoint.sh

ENV SYNC_SOURCE=drive \
    IMMICH_SERVER=http://immich-server:2283 \
    RCLONE_REMOTE=gdrive:Takeout \
    CRON_SCHEDULE="0 4 5 */2 *" \
    WORK_DIR=/work \
    LOCAL_PATH=/backfill \
    PUID=99 \
    PGID=100 \
    UMASK=002

VOLUME ["/work"]
ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["cron"]
