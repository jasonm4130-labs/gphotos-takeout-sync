#!/bin/bash
# Entrypoint: either run supercronic on a schedule ("cron"), or run a single
# one-shot import ("backfill"). Drops privileges to PUID:PGID so files written
# to the bind-mounted /work stay owned by Unraid's nobody:users.
set -euo pipefail

umask "${UMASK:-002}"

WORK_DIR="${WORK_DIR:-/work}"
mkdir -p "${WORK_DIR}/zips" "${WORK_DIR}/state"
chown -R "${PUID:-99}:${PGID:-100}" "${WORK_DIR}" 2>/dev/null || true

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
