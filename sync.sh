#!/bin/bash
# gphotos-takeout-sync: pull a Google Takeout (from Google Drive or a local
# folder) and import it into Immich via immich-go. Writes fail-loud metrics
# that telegraf scrapes (see the brok-stacks monitoring stack).
#
# Usage:  sync.sh <drive|local>
#   drive  - rclone copy ${RCLONE_REMOTE} -> /work/zips, then import the zips
#   local  - import ${LOCAL_PATH} directly (used for the one-shot backfill)
# Env:    DRY_RUN=1 adds --dry-run; see the Dockerfile for the rest.
set -euo pipefail
umask "${UMASK:-002}"

SOURCE="${1:-${SYNC_SOURCE:-drive}}"
WORK_DIR="${WORK_DIR:-/work}"
STATE_DIR="${WORK_DIR}/state"
ZIP_DIR="${WORK_DIR}/zips"
METRICS_FILE="${STATE_DIR}/metrics"
IMMICH_SERVER="${IMMICH_SERVER:-http://immich-server:2283}"
LOCAL_PATH="${LOCAL_PATH:-/backfill}"
API_KEY_FILE="${IMMICH_API_KEY_FILE:-/run/secrets/immich_api_key}"
RCLONE_CONF="${RCLONE_CONF_FILE:-/run/secrets/rclone_conf}"
RCLONE_REMOTE="${RCLONE_REMOTE:-gdrive:Takeout}"

mkdir -p "${ZIP_DIR}" "${STATE_DIR}"
log() { echo "$(date -u +%FT%TZ) [gphotos-sync] $*"; }

# Atomically write the metrics file telegraf reads. Preserves the prior
# last_success epoch on a failed run so the staleness alert stays meaningful.
write_metrics() {
  local code="$1" imported="${2:-0}" now last_success
  now="$(date +%s)"
  if [ "${code}" = "0" ]; then
    last_success="${now}"
  else
    last_success="$(grep -oE '^gphotos_sync_last_success=[0-9]+' "${METRICS_FILE}" 2>/dev/null | cut -d= -f2 || true)"
    last_success="${last_success:-0}"
  fi
  {
    echo "gphotos_sync_exit_code=${code}"
    echo "gphotos_sync_assets_imported=${imported}"
    echo "gphotos_sync_last_success=${last_success}"
    echo "gphotos_sync_last_run=${now}"
  } > "${METRICS_FILE}.tmp"
  mv "${METRICS_FILE}.tmp" "${METRICS_FILE}"
}

trap 'rc=$?; log "FAILED (exit ${rc})"; write_metrics 1 0; exit ${rc}' ERR

[ -r "${API_KEY_FILE}" ] || { log "missing immich api key at ${API_KEY_FILE}"; exit 1; }
API_KEY="$(cat "${API_KEY_FILE}")"

case "${SOURCE}" in
  drive)
    [ -r "${RCLONE_CONF}" ] || { log "missing rclone conf at ${RCLONE_CONF}"; exit 1; }
    log "rclone copy ${RCLONE_REMOTE} -> ${ZIP_DIR}"
    rclone copy "${RCLONE_REMOTE}" "${ZIP_DIR}" \
      --config "${RCLONE_CONF}" \
      --transfers 4 --checkers 8 --fast-list --checksum
    IMPORT_PATH="${ZIP_DIR}"
    ;;
  local)
    IMPORT_PATH="${LOCAL_PATH}"
    [ -d "${IMPORT_PATH}" ] || { log "local path ${IMPORT_PATH} not found"; exit 1; }
    ;;
  *)
    log "unknown source '${SOURCE}' (want drive|local)"; exit 1 ;;
esac

DRY_ARGS=()
if [ "${DRY_RUN:-0}" = "1" ]; then DRY_ARGS+=(--dry-run); log "DRY RUN — no assets will be written"; fi

log "immich-go import from ${IMPORT_PATH}"
IMPORT_LOG="${STATE_DIR}/last-import.log"
set +e
immich-go upload from-google-photos \
  --server="${IMMICH_SERVER}" \
  --api-key="${API_KEY}" \
  --include-unmatched=true \
  "${DRY_ARGS[@]}" \
  "${IMPORT_PATH}" 2>&1 | tee "${IMPORT_LOG}"
RC=${PIPESTATUS[0]}
set -e

if [ "${RC}" -ne 0 ]; then
  log "immich-go exited ${RC}"
  write_metrics 1 0
  exit "${RC}"
fi

# Best-effort imported-asset count from immich-go's summary (format varies by
# version, so this is advisory — the staleness/exit-code alerts are the robust
# signals; zero-growth is the soft one).
IMPORTED="$(grep -oiE '[0-9]+ (uploaded|added|imported|new)' "${IMPORT_LOG}" | grep -oE '[0-9]+' | sort -n | tail -1 || true)"
IMPORTED="${IMPORTED:-0}"

# Free Drive quota: clear staged zips after a successful real drive run.
if [ "${SOURCE}" = "drive" ] && [ "${DRY_RUN:-0}" != "1" ]; then
  rm -rf "${ZIP_DIR:?}/"* 2>/dev/null || true
fi

write_metrics 0 "${IMPORTED}"
log "DONE (imported≈${IMPORTED})"
