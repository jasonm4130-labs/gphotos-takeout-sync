#!/bin/bash
# Entrypoint: either run supercronic on a schedule ("cron"), or run a single
# one-shot import ("backfill"). Drops privileges to PUID:PGID so files written
# to the bind-mounted /work stay owned by Unraid's nobody:users.
set -euo pipefail

umask "${UMASK:-002}"

WORK_DIR="${WORK_DIR:-/work}"
mkdir -p "${WORK_DIR}/zips" "${WORK_DIR}/state"
chown -R "${PUID:-99}:${PGID:-100}" "${WORK_DIR}" 2>/dev/null || true

# immich-go (and Go's os.UserCacheDir) writes to $HOME/.cache. The run user has
# no HOME, so it falls back to /.cache (root-owned) and dies with "mkdir
# /.cache: permission denied". Point HOME at the writable work dir — immich-go
# then keeps its cache/logs under ${WORK_DIR}/.cache (survives the drive-mode
# zip/extract cleanup).
export HOME="${WORK_DIR}"

# Docker Compose (non-swarm) bind-mounts file secrets as 0600 root:root, which
# the unprivileged run user (PUID:PGID) cannot read — so the job would fail to
# read the API key / rclone config. We run as root here (before su-exec), so
# re-stage readable copies in the container's ephemeral fs and point sync.sh at
# them. Host secrets stay root:root 600 (repo convention); these copies live
# only in the container layer and vanish on recreate.
if [ -d /run/secrets ]; then
  SECRETS_DIR=/tmp/secrets
  rm -rf "${SECRETS_DIR}"
  mkdir -p "${SECRETS_DIR}"
  for s in /run/secrets/*; do
    [ -e "${s}" ] || continue
    # 0600 (not 0400) so rclone can write OAuth token refreshes to its copy.
    install -m 0600 -o "${PUID:-99}" -g "${PGID:-100}" "${s}" "${SECRETS_DIR}/$(basename "${s}")"
  done
  chown "${PUID:-99}:${PGID:-100}" "${SECRETS_DIR}"
  chmod 0500 "${SECRETS_DIR}"
  export IMMICH_API_KEY_FILE="${SECRETS_DIR}/immich_api_key"
  export RCLONE_CONF_FILE="${SECRETS_DIR}/rclone_conf"
fi

MODE="${1:-cron}"

case "${MODE}" in
  backfill)
    # One-shot local-folder import (no rclone). Honours DRY_RUN=1 and LOCAL_PATH.
    echo "[entrypoint] backfill: importing ${LOCAL_PATH:-/backfill} (dry_run=${DRY_RUN:-0})"
    exec su-exec "${PUID:-99}:${PGID:-100}" /usr/local/bin/sync.sh local
    ;;
  cron)
    CRON_FILE=/tmp/crontab
    printf '%s /usr/local/bin/sync.sh %s\n' "${CRON_SCHEDULE}" "${SYNC_SOURCE}" > "${CRON_FILE}"
    echo "[entrypoint] schedule='${CRON_SCHEDULE}' source='${SYNC_SOURCE}'"
    exec su-exec "${PUID:-99}:${PGID:-100}" supercronic -passthrough-logs "${CRON_FILE}"
    ;;
  *)
    # Debug passthrough: run an arbitrary command as the unprivileged user.
    exec su-exec "${PUID:-99}:${PGID:-100}" "$@"
    ;;
esac
