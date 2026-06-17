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
    # Scheduled Google Takeout delivered to Drive arrives as multi-GB .tgz
    # chunks; immich-go reads .zip archives and extracted folders, NOT tarballs.
    # Extract any tarballs into a staging folder and import that; pass .zip
    # archives straight through. Each chunk is deleted right after it extracts
    # so peak local use stays near one extracted tree + one chunk, not double.
    shopt -s nullglob
    tarballs=( "${ZIP_DIR}"/*.tgz "${ZIP_DIR}"/*.tar.gz )
    zips=( "${ZIP_DIR}"/*.zip )
    if [ "${#tarballs[@]}" -gt 0 ]; then
      EXTRACT_DIR="${WORK_DIR}/extracted"
      rm -rf "${EXTRACT_DIR}"; mkdir -p "${EXTRACT_DIR}"
      for t in "${tarballs[@]}"; do
        log "extracting $(basename "${t}")"
        tar -xzf "${t}" -C "${EXTRACT_DIR}"
        [ "${DRY_RUN:-0}" = "1" ] || rm -f "${t}"
      done
      IMPORT_PATH="${EXTRACT_DIR}"
    elif [ "${#zips[@]}" -gt 0 ]; then
      IMPORT_PATH="${ZIP_DIR}"
    else
      log "no .tgz/.tar.gz/.zip in ${ZIP_DIR} after rclone copy — nothing to import"
      exit 1
    fi
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
# Capture the whole pipe status at once — any later command resets PIPESTATUS.
PIPE=( "${PIPESTATUS[@]}" )
set -e
RC="${PIPE[0]}"
[ "${PIPE[1]:-0}" -eq 0 ] || log "warning: tee to ${IMPORT_LOG} failed (rc=${PIPE[1]}); last-import.log may be truncated"

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

# Free LOCAL staging after a successful real drive run (the .tgz chunks are
# already removed during extraction; this clears any .zip passthrough and the
# extracted tree). rclone copy leaves the source in Drive untouched — Drive
# housekeeping is intentionally manual.
if [ "${SOURCE}" = "drive" ] && [ "${DRY_RUN:-0}" != "1" ]; then
  rm -rf "${ZIP_DIR:?}/"* "${WORK_DIR:?}/extracted" 2>/dev/null || true
fi

write_metrics 0 "${IMPORTED}"
log "DONE (imported≈${IMPORTED})"
