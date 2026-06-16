# gphotos-takeout-sync

A small container that mirrors a **Google Photos** library into **Immich** by
importing **Google Takeout** archives. Google closed the Photos Library API to
third-party full-library reads in 2025, so the only reliable path is Takeout —
this image automates the download + import half of that pipeline and **fails
loud** (emits metrics for Prometheus/Telegraf) so a broken run never goes
unnoticed.

It bundles:

- [`rclone`](https://rclone.org) — pulls scheduled Takeout ZIPs from Google Drive
- [`immich-go`](https://github.com/simulot/immich-go) — imports Takeout into Immich (albums, EXIF, dates from the JSON sidecars)
- [`supercronic`](https://github.com/aptible/supercronic) — cron with proper exit-code logging to stdout

## How it runs

Two modes, selected by the first arg / `SYNC_SOURCE`:

| Mode | What it does |
|------|--------------|
| `drive` (default, scheduled) | `rclone copy ${RCLONE_REMOTE}` → `/work/zips`, then `immich-go` import |
| `local` (one-shot backfill) | `immich-go` import of `${LOCAL_PATH}` directly (no rclone) |

### Scheduled (the normal case)

Designed to be deployed from the **brok-stacks** `downloaders/` stack. The
container sleeps under `supercronic` and fires `${CRON_SCHEDULE}` (default:
`0 4 5 */2 *` — 04:00 on the 5th, every 2nd month, after Google's bi-monthly
Incremental Takeout export email lands). It reaches Immich over the shared
`immich_internal` Docker network.

### One-shot backfill (initial import)

```bash
docker run --rm --network immich_internal \
  -e DRY_RUN=1 \
  -v /path/to/extracted/takeout:/backfill:ro \
  -v /path/to/immich_api_key.txt:/run/secrets/immich_api_key:ro \
  ghcr.io/jasonm4130-labs/gphotos-takeout-sync:latest backfill
```

Drop `-e DRY_RUN=1` for the real import. `immich-go` is idempotent (skips
assets already on the server by checksum), so re-running is safe.

## Configuration

| Env | Default | Purpose |
|-----|---------|---------|
| `SYNC_SOURCE` | `drive` | `drive` or `local` |
| `IMMICH_SERVER` | `http://immich-server:2283` | Immich API base URL |
| `RCLONE_REMOTE` | `gdrive:Takeout` | rclone source for `drive` mode |
| `LOCAL_PATH` | `/backfill` | source folder for `local` mode |
| `CRON_SCHEDULE` | `0 4 5 */2 *` | supercronic schedule |
| `DRY_RUN` | `0` | `1` adds `immich-go --dry-run` |
| `PUID` / `PGID` / `UMASK` | `99` / `100` / `002` | Unraid file ownership |

Secrets are read from files (never env), Docker-secret style:

- `/run/secrets/immich_api_key` — Immich API key
- `/run/secrets/rclone_conf` — rclone config with the Google Drive remote (`drive` mode only)

`--include-unmatched=true` is always set so media without a JSON sidecar still imports.

## Metrics (fail-loud)

After each run, writes `/work/state/metrics` (`KEY=VALUE`) for Telegraf's
`inputs.exec` to scrape:

```
gphotos_sync_exit_code=0
gphotos_sync_assets_imported=1234
gphotos_sync_last_success=1718600000
gphotos_sync_last_run=1718600000
```

The brok-stacks monitoring stack alerts on staleness (>65 d), non-zero exit, and
zero-growth.

## Releasing

Tag a semver (`git tag v0.1.0 && git push --tags`); GitHub Actions builds on
Blacksmith and pushes `ghcr.io/jasonm4130-labs/gphotos-takeout-sync` (public).
brok-stacks pins the image by digest.
