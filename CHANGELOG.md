# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.4] - 2026-06-17

### Added

- `HEALTHCHECK` in the image: probes the supercronic scheduler process so a
  wedged scheduler is detectable. (A metrics-file check is unsuitable on a
  bi-monthly cron — the file may not exist for weeks, and persists even if the
  scheduler dies.)
- OCI image labels (`org.opencontainers.image.*`) for provenance.
- Lint CI (`.github/workflows/lint.yml`): shellcheck + hadolint on every push
  and pull request.
- Project/community docs: `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md` (Contributor
  Covenant 2.1), `SECURITY.md`, this `CHANGELOG.md`, GitHub issue/PR templates,
  and `.editorconfig`.
- Explicit `DRY_RUN=0` default in the image `ENV` (matches the existing
  `${DRY_RUN:-0}` fallback in `sync.sh`).

### Changed

- Rewrote `README.md` as a general-purpose open-source readme (badges, mermaid
  flow, full env-var reference, setup, monitoring, security, troubleshooting).

### Security

- Verify the supercronic binary with **SHA-256** instead of SHA-1.
- Renovate now pins the Alpine base image and all GitHub Actions to digests
  (`pinDigests` + `helpers:pinGitHubActionDigests`).

### Fixed

- `sync.sh` warns when the `tee` of immich-go output to `last-import.log` fails
  (it captures both pipeline exit codes), instead of silently ignoring a
  truncated log.

The sync/import behaviour of `sync.sh` and `entrypoint.sh` is otherwise
unchanged.

## [0.1.3] - 2026-06-17

### Fixed

- Export `HOME` to `WORK_DIR` in the entrypoint so immich-go can create its
  cache directory. Without this, Go's `os.UserCacheDir` fell back to `/.cache`
  (root-owned) and every import failed with `mkdir /.cache: permission denied`.

## [0.1.2] - 2026-06-17

### Fixed

- Re-stage Docker file secrets in the entrypoint before dropping privileges.
  Docker Compose bind-mounts file secrets as `0600 root:root` and ignores the
  `mode:` key, so the non-root run user (PUID/PGID) could not read the Immich
  API key or rclone config. The entrypoint now copies them into an ephemeral
  `/tmp/secrets/` directory owned by the run user while still running as root,
  then passes the new paths via `IMMICH_API_KEY_FILE` / `RCLONE_CONF_FILE`
  before `su-exec` drops privileges.

## [0.1.1] - 2026-06-17

### Fixed

- Drive mode now extracts `.tgz`/`.tar.gz` Takeout chunks before importing.
  Scheduled Google Takeout delivered to Google Drive arrives as multi-GB
  tarballs; immich-go only reads `.zip` archives or plain extracted directories,
  so recurring runs were silently importing nothing. Tarballs are now extracted
  into a staging directory (`/work/extracted`) and deleted one-by-one to keep
  peak local disk usage near a single extracted tree plus one chunk.

## [0.1.0] - 2026-06-16

### Added

- Initial release.
- Alpine-based Docker image bundling rclone, immich-go v0.31.0, supercronic,
  su-exec, and tini.
- `drive` mode: rclone copies archives from a configurable Google Drive remote
  (`RCLONE_REMOTE`, default `gdrive:Takeout`), then immich-go imports them into
  Immich on a cron schedule (`CRON_SCHEDULE`, default bi-monthly at 04:00).
- `local`/`backfill` mode: one-shot import from a bind-mounted local directory
  (`LOCAL_PATH`), useful for seeding Immich from an existing Takeout export.
- Privilege drop via `su-exec` to a configurable PUID/PGID (default 99/100 for
  Unraid nobody/users).
- Fail-loud `KEY=VALUE` metrics written to `/work/state/metrics` after every
  run (`gphotos_sync_exit_code`, `gphotos_sync_assets_imported`,
  `gphotos_sync_last_success`, `gphotos_sync_last_run`) for Telegraf scraping.
- Last import log tee'd to `/work/state/last-import.log`.
- `DRY_RUN=1` support passes `--dry-run` to immich-go and skips local cleanup.
- GitHub Actions CI on Blacksmith runners publishing versioned images to the
  public GitHub Container Registry (`ghcr.io/jasonm4130-labs/gphotos-takeout-sync`).
- Renovate config tracking immich-go and supercronic release versions.

[Unreleased]: https://github.com/jasonm4130-labs/gphotos-takeout-sync/compare/v0.1.4...HEAD
[0.1.4]: https://github.com/jasonm4130-labs/gphotos-takeout-sync/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/jasonm4130-labs/gphotos-takeout-sync/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/jasonm4130-labs/gphotos-takeout-sync/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/jasonm4130-labs/gphotos-takeout-sync/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/jasonm4130-labs/gphotos-takeout-sync/releases/tag/v0.1.0
